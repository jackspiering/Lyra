import SwiftUI

/// Ambiguous-match picker or Create confirmation after following a wiki link.
enum WikiFollowPrompt: Identifiable, Equatable {
    case pick(query: String, candidates: [WikiCandidate])
    case create(query: String, destination: URL)

    var id: String {
        switch self {
        case .pick(let query, let candidates):
            return "pick:\(query):\(candidates.map(\.id).joined(separator: ","))"
        case .create(let query, let destination):
            return "create:\(query):\(destination.path)"
        }
    }
}

struct WikiFollowSheet: View {
    let prompt: WikiFollowPrompt
    var onPick: (URL) -> Void
    var onCreate: (URL) -> Void
    var onCancel: () -> Void

    var body: some View {
        switch prompt {
        case .pick(let query, let candidates):
            VStack(alignment: .leading, spacing: 12) {
                Text("Multiple notes match")
                    .font(LyraFonts.headline)
                Text("“\(query)” matches more than one note. Choose one.")
                    .foregroundStyle(.secondary)
                List(candidates) { candidate in
                    Button(candidate.relativePath) {
                        onPick(candidate.url)
                    }
                }
                .frame(minHeight: 120, maxHeight: 240)
                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                }
            }
            .padding()
            .frame(width: 400)
        case .create(let query, let destination):
            VStack(alignment: .leading, spacing: 12) {
                Text("Create note")
                    .font(LyraFonts.headline)
                Text("No note matches “\(query)”. Create \(destination.lastPathComponent) at \(displayPath(destination))?")
                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                    Button("Create") {
                        onCreate(destination)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 400)
        }
    }

    private func displayPath(_ url: URL) -> String {
        let parent = url.deletingLastPathComponent()
        return parent.lastPathComponent + "/" + url.lastPathComponent
    }
}
