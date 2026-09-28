import SwiftUI

/// Ambiguous-match picker or Create confirmation after following a wiki link.
enum WikiFollowPrompt: Identifiable, Equatable {
    case pick(query: String, candidates: [WikiCandidate])
    case create(query: String, destination: URL, relativePath: String)

    var id: String {
        switch self {
        case .pick(let query, let candidates):
            return "pick:\(query):\(candidates.map(\.id).joined(separator: ","))"
        case .create(let query, let destination, let relativePath):
            return "create:\(query):\(destination.path):\(relativePath)"
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
            VStack(alignment: .leading, spacing: 14) {
                SheetHeader(
                    systemImage: "arrow.triangle.branch",
                    tint: LyraTheme.accentColor,
                    title: "Multiple notes match",
                    message: "“\(query)” matches more than one note. Choose one."
                )
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(candidates) { candidate in
                            CandidateRow(candidate: candidate) {
                                onPick(candidate.url)
                            }
                        }
                    }
                    .padding(4)
                }
                // Hug a short list; scroll a long one.
                .frame(height: min(CGFloat(candidates.count) * 34 + 8, 240))
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LyraTheme.fillColor)
                )
                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(20)
            .frame(width: 420)
        case .create(let query, let destination, let relativePath):
            VStack(alignment: .leading, spacing: 16) {
                SheetHeader(
                    systemImage: "doc.badge.plus",
                    tint: LyraTheme.accentColor,
                    title: "Create “\(query)”?",
                    message: "No note matches this link yet. Lyra will create \(relativePath)."
                )
                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Button("Create") {
                        onCreate(destination)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 420)
        }
    }
}

/// One candidate note in the ambiguous-link picker.
private struct CandidateRow: View {
    let candidate: WikiCandidate
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .foregroundStyle(isHovering ? LyraTheme.accentColor : Color.secondary)
                    .frame(width: 16)
                Text(candidate.relativePath)
                    .font(LyraFonts.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovering ? LyraTheme.accentSoftColor : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// Icon, title, and one line of explanation at the top of a Lyra sheet.
struct SheetHeader: View {
    let systemImage: String
    let tint: Color
    let title: String
    var message: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(Circle().fill(tint.opacity(0.14)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(LyraFonts.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message)
                        .font(LyraFonts.label)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
