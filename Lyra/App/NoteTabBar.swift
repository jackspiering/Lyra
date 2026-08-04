import AppKit
import SwiftUI

/// Left-growing in-window tab strip: tab chips then `+` immediately after the last tab.
struct NoteTabBar: View {
    @Bindable var tabs: NoteTabController
    var onNewTab: () -> Void
    var onCloseTab: (NoteTab.ID) -> Void
    var onSelectTab: (NoteTab.ID) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tabs.tabs) { tab in
                        NoteTabChip(
                            title: tab.title,
                            isSelected: tab.id == tabs.selectedTabID,
                            isDirty: tab.editor.isDirty,
                            onSelect: { onSelectTab(tab.id) },
                            onClose: { onCloseTab(tab.id) }
                        )
                    }
                    Button(action: onNewTab) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("New Tab")
                    .accessibilityLabel("New Tab")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

// MARK: - Chip

private struct NoteTabChip: View {
    let title: String
    let isSelected: Bool
    let isDirty: Bool
    var onSelect: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSelect) {
                HStack(spacing: 4) {
                    if isDirty {
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 6, height: 6)
                    }
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: 160, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close Tab")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isSelected ? Color.secondary.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .font(LyraFonts.caption)
    }
}
