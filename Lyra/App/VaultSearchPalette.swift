import SwiftUI

/// Lightweight ⇧⌘F results list: note path plus one snippet.
/// ↑/↓ move the selection; Return opens it.
struct VaultSearchPalette: View {
    @Binding var query: String
    var search: (String) -> [VaultFullTextSearch.Hit]
    var onOpen: (URL) -> Void
    var onClose: () -> Void
    @FocusState private var queryFocused: Bool
    /// Computed once per (debounced) query, not on every body pass.
    @State private var hits: [VaultFullTextSearch.Hit] = []
    @State private var selection: VaultFullTextSearch.Hit.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search Vault")
                .font(LyraFonts.headline)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Find in notes", text: $query)
                    .textFieldStyle(.plain)
                    .font(LyraFonts.headline)
                    .focused($queryFocused)
                    .onAppear { queryFocused = true }
                    .onSubmit(openSelection)
                    .onKeyPress(.downArrow) {
                        moveSelection(by: 1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        moveSelection(by: -1)
                        return .handled
                    }
                    .task(id: query) {
                        try? await Task.sleep(nanoseconds: 120_000_000)
                        guard !Task.isCancelled else { return }
                        hits = search(query)
                        selection = hits.first?.id
                    }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LyraTheme.fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(LyraTheme.hairlineColor, lineWidth: 1)
            )
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Type to search note bodies.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            } else if hits.isEmpty {
                Text("No matches.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            } else {
                ScrollViewReader { proxy in
                    List(hits, selection: $selection) { hit in
                        Button {
                            onOpen(hit.url)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text((((hit.relativePath as NSString).lastPathComponent) as NSString).deletingPathExtension)
                                    .font(LyraFonts.labelEmphasized)
                                    .lineLimit(1)
                                Text(hit.relativePath)
                                    .font(LyraFonts.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(hit.snippet)
                                    .font(LyraFonts.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .tag(hit.id)
                    }
                    .frame(minHeight: 160, maxHeight: 320)
                    .onChange(of: selection) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
                if hits.count >= VaultFullTextSearch.defaultLimit {
                    Text("Showing the first \(hits.count) matches. Refine the search to narrow them.")
                        .font(LyraFonts.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(width: 480)
    }

    private func moveSelection(by offset: Int) {
        guard !hits.isEmpty else { return }
        let current = hits.firstIndex { $0.id == selection } ?? -1
        let next = min(max(current + offset, 0), hits.count - 1)
        selection = hits[next].id
    }

    /// Return opens the selected hit, or searches now if the debounce has
    /// not landed yet.
    private func openSelection() {
        if let hit = hits.first(where: { $0.id == selection }) {
            onOpen(hit.url)
        } else if let first = search(query).first {
            onOpen(first.url)
        }
    }
}
