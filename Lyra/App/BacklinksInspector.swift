import SwiftUI

/// Trailing list of notes that uniquely `[[wiki]]` this file.
struct BacklinksInspector: View {
    let items: [WikiCandidate]
    var onOpen: (URL) -> Void
    var onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Backlinks")
                    .font(LyraFonts.headline)
                Spacer()
                Button(action: onHide) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Hide Backlinks")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider()
            if items.isEmpty {
                Text("No backlinks")
                    .foregroundStyle(.secondary)
                    .padding(12)
                Spacer()
            } else {
                List(items) { item in
                    Button {
                        onOpen(item.url)
                    } label: {
                        Text(item.relativePath)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 220)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
