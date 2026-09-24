import SwiftUI

/// Trailing list of notes that uniquely `[[wiki]]` this file, each with a line of context.
struct BacklinksInspector: View {
    let items: [Backlink]
    var onOpen: (URL) -> Void
    var onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if items.isEmpty {
                Text("No notes link here yet.")
                    .font(LyraFonts.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(items) { item in
                            BacklinkCard(item: item, onOpen: onOpen)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(width: 260)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(LyraTheme.sidebarColor)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("BACKLINKS")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            if !items.isEmpty {
                Text("\(items.count)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(LyraTheme.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(LyraTheme.accentSoftColor))
            }
            Spacer()
            Button(action: onHide) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Hide Backlinks")
            .accessibilityLabel("Hide Backlinks")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

// MARK: - Card

private struct BacklinkCard: View {
    let item: Backlink
    var onOpen: (URL) -> Void
    @State private var isHovering = false

    private var name: String {
        ((item.relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    private var folder: String {
        (item.relativePath as NSString).deletingLastPathComponent
    }

    var body: some View {
        Button {
            onOpen(item.url)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(LyraFonts.labelEmphasized)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !folder.isEmpty {
                    Text(folder)
                        .font(LyraFonts.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                if let context = item.context {
                    Text(snippet(context))
                        .font(LyraFonts.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovering ? LyraTheme.accentSoftColor : LyraTheme.fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(LyraTheme.hairlineColor, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(item.relativePath)
        .accessibilityLabel("Open \(item.relativePath)")
    }

    private func snippet(_ context: BacklinkContext) -> AttributedString {
        var link = AttributedString(context.link)
        link.foregroundColor = LyraTheme.accentColor
        link.font = LyraFonts.captionEmphasized
        return AttributedString(context.before) + link + AttributedString(context.after)
    }
}
