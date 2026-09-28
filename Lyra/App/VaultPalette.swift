import SwiftUI

/// One row in the Go to File / Search palette.
struct VaultPaletteItem: Identifiable, Hashable, Sendable {
    let url: URL
    /// Note name (filename stem).
    let title: String
    /// Folders above the note; empty at the vault root.
    let folder: String
    /// Matching line from the body (Search only).
    let snippet: String?

    var id: String { url.path }
}

/// Spotlight-style panel over the vault window. Go to File (⌘O) jumps to a
/// note by name; Search Vault (⇧⌘F) searches note bodies. ↑/↓ move, Return
/// opens, Esc or a click outside closes. Not a third workspace: it opens a
/// note and gets out of the way.
struct VaultPalette: View {
    enum Mode: Equatable {
        case goToFile
        case searchVault
    }

    let mode: Mode
    @Binding var query: String
    /// Results for a query; may do its work off the main actor.
    var results: (String) async -> [VaultPaletteItem]
    var onOpen: (URL) -> Void
    var onClose: () -> Void

    @FocusState private var queryFocused: Bool
    @State private var items: [VaultPaletteItem] = []
    @State private var selection: VaultPaletteItem.ID?
    @State private var hasResults = false
    /// Measured height of the result rows; the list hugs it up to a cap.
    @State private var contentHeight: CGFloat = 0

    /// Row limit shared with the search index, so "200+" means "refine".
    private static let limit = VaultFullTextSearch.defaultLimit

    var body: some View {
        ZStack(alignment: .top) {
            LyraTheme.scrimColor
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)
            panel
                .padding(.top, 56)
                .padding(.horizontal, 32)
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            queryField
            hairline
            resultList
            hairline
            footer
        }
        .frame(maxWidth: 620)
        .background(LyraTheme.raisedColor)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(LyraTheme.hairlineColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 32, y: 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(mode == .goToFile ? "Go to File" : "Search Vault")
    }

    private var hairline: some View {
        Rectangle()
            .fill(LyraTheme.hairlineColor)
            .frame(height: 1)
    }

    // MARK: - Query

    private var queryField: some View {
        HStack(spacing: 12) {
            Image(systemName: mode == .goToFile ? "doc.text.magnifyingglass" : "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LyraTheme.accentColor)
                .accessibilityHidden(true)
            TextField(mode == .goToFile ? "Go to note…" : "Search every note…", text: $query)
                .textFieldStyle(.plain)
                .font(LyraFonts.paletteQuery)
                .focused($queryFocused)
                .accessibilityLabel(mode == .goToFile ? "Note name" : "Search text")
                .onSubmit(openSelection)
                .onKeyPress(.downArrow) {
                    moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveSelection(by: -1)
                    return .handled
                }
                .onExitCommand(perform: onClose)
            KeyHint("esc")
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .onAppear {
            // After the overlay is in the window, or the focus request is lost.
            DispatchQueue.main.async { queryFocused = true }
        }
        .task(id: query) {
            // Body search waits for a typing pause; names are instant.
            if mode == .searchVault {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
            }
            let found = await results(query)
            guard !Task.isCancelled else { return }
            items = found
            selection = found.first?.id
            hasResults = true
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultList: some View {
        if items.isEmpty {
            Text(emptyMessage)
                .font(LyraFonts.label)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 92)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(items) { item in
                            PaletteRow(item: item, query: query, isSelected: item.id == selection)
                                .id(item.id)
                                .onTapGesture { onOpen(item.url) }
                                .onHover { inside in
                                    if inside { selection = item.id }
                                }
                        }
                    }
                    .padding(6)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        contentHeight = height
                    }
                }
                .frame(height: listHeight)
                .onChange(of: selection) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
    }

    /// Hug short result lists; scroll long ones. Until the rows are
    /// measured, estimate from the row count so the panel does not jump.
    private var listHeight: CGFloat {
        let estimate = CGFloat(items.count) * (mode == .goToFile ? 35 : 53) + 12
        return min(contentHeight > 0 ? contentHeight : estimate, 392)
    }

    private var emptyMessage: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .goToFile:
            if !hasResults { return "" }
            return trimmed.isEmpty ? "This vault has no notes yet." : "No note is called “\(trimmed)”."
        case .searchVault:
            if trimmed.isEmpty { return "Type to search every note in the vault." }
            return hasResults ? "No notes contain “\(trimmed)”." : ""
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 16) {
            FooterHint(keys: "↑↓", label: "Move")
            FooterHint(keys: "↩", label: "Open")
            FooterHint(keys: "esc", label: "Close")
            Spacer(minLength: 0)
            if !items.isEmpty {
                Text(countLabel)
                    .monospacedDigit()
            }
        }
        .font(LyraFonts.caption)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(LyraTheme.fillColor.opacity(0.6))
    }

    private var countLabel: String {
        let singular = mode == .goToFile ? "note" : "match"
        let plural = mode == .goToFile ? "notes" : "matches"
        if items.count >= Self.limit {
            return "First \(items.count) \(plural)"
        }
        return items.count == 1 ? "1 \(singular)" : "\(items.count) \(plural)"
    }

    // MARK: - Keyboard

    private func moveSelection(by offset: Int) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selection } ?? -1
        let next = min(max(current + offset, 0), items.count - 1)
        selection = items[next].id
    }

    /// Return opens the selected row, or the best match if results have not
    /// landed yet.
    private func openSelection() {
        if let item = items.first(where: { $0.id == selection }) ?? items.first {
            onOpen(item.url)
            return
        }
        Task {
            if let first = await results(query).first {
                onOpen(first.url)
            }
        }
    }
}

// MARK: - Row

private struct PaletteRow: View {
    let item: VaultPaletteItem
    let query: String
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? LyraTheme.accentColor : Color.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(PaletteHighlight.attributed(item.title, query: query, emphasis: LyraFonts.labelEmphasized))
                        .font(LyraFonts.labelEmphasized)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !item.folder.isEmpty {
                        Text(item.folder)
                            .font(LyraFonts.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                if let snippet = item.snippet {
                    Text(PaletteHighlight.attributed(snippet, query: query, emphasis: LyraFonts.captionEmphasized))
                        .font(LyraFonts.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? LyraTheme.accentSoftColor : Color.clear)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }
}

// MARK: - Hints

/// A key in a small outlined chip, as on a keycap.
struct KeyHint: View {
    let keys: String

    init(_ keys: String) {
        self.keys = keys
    }

    var body: some View {
        Text(keys)
            .font(LyraFonts.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(LyraTheme.hairlineColor, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

private struct FooterHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            KeyHint(keys)
            Text(label)
        }
    }
}

/// Query words drawn in the accent colour inside a title or snippet.
enum PaletteHighlight {
    static func attributed(_ text: String, query: String, emphasis: Font) -> AttributedString {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        var ranges: [Range<String.Index>] = []
        for word in words {
            var start = text.startIndex
            while start < text.endIndex,
                  let found = text.range(of: word, options: .caseInsensitive, range: start..<text.endIndex) {
                ranges.append(found)
                start = found.upperBound
            }
        }
        guard !ranges.isEmpty else { return AttributedString(text) }
        ranges.sort { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for range in ranges {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        var result = AttributedString()
        var cursor = text.startIndex
        for range in merged {
            result += AttributedString(String(text[cursor..<range.lowerBound]))
            var hit = AttributedString(String(text[range]))
            hit.foregroundColor = LyraTheme.accentColor
            hit.font = emphasis
            result += hit
            cursor = range.upperBound
        }
        result += AttributedString(String(text[cursor...]))
        return result
    }
}
