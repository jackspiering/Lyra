import SwiftUI

/// Lightweight ⇧⌘F results list: note path plus one snippet.
struct VaultSearchPalette: View {
    @Binding var query: String
    var search: (String) -> [VaultFullTextSearch.Hit]
    var onOpen: (URL) -> Void
    var onClose: () -> Void
    @FocusState private var queryFocused: Bool
    @State private var debouncedQuery = ""

    private var hits: [VaultFullTextSearch.Hit] {
        search(debouncedQuery)
    }

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
                    .onSubmit {
                        if let first = search(query).first {
                            onOpen(first.url)
                        }
                    }
                    .task(id: query) {
                        try? await Task.sleep(nanoseconds: 120_000_000)
                        guard !Task.isCancelled else { return }
                        debouncedQuery = query
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
                List(hits) { hit in
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
                }
                .frame(minHeight: 160, maxHeight: 320)
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
}
