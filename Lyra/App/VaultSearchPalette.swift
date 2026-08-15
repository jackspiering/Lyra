import SwiftUI

/// Lightweight ⇧⌘F results list: note path plus one snippet.
struct VaultSearchPalette: View {
    @Binding var query: String
    var search: (String) -> [VaultFullTextSearch.Hit]
    var onOpen: (URL) -> Void
    var onClose: () -> Void
    @FocusState private var queryFocused: Bool

    private var hits: [VaultFullTextSearch.Hit] {
        search(query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search Vault")
                .font(LyraFonts.headline)
            TextField("Find in notes", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($queryFocused)
                .onAppear { queryFocused = true }
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(hit.relativePath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(hit.snippet)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
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
