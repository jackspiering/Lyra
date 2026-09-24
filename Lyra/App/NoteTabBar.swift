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
                HStack(spacing: 2) {
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
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("New Tab")
                    .accessibilityLabel("New Tab")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LyraTheme.chromeColor)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LyraTheme.hairlineColor)
                .frame(height: 1)
        }
    }
}

// MARK: - Chip

/// One tab. Unsaved notes show a gold dot where the close button sits; hovering
/// swaps the dot for the close button (the button stays reachable to VoiceOver).
private struct NoteTabChip: View {
    let title: String
    let isSelected: Bool
    let isDirty: Bool
    var onSelect: () -> Void
    var onClose: () -> Void

    @State private var isHovering = false

    private var showsClose: Bool { isHovering || (isSelected && !isDirty) }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 170, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDirty ? "\(title), edited" : title)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            ZStack {
                if isDirty && !isHovering {
                    Circle()
                        .fill(LyraTheme.accentColor)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                }
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(showsClose ? 1 : 0)
                .help("Close Tab")
                .accessibilityLabel("Close \(title)")
            }
            .frame(width: 16, height: 16)
        }
        .font(isSelected ? LyraFonts.labelEmphasized : LyraFonts.label)
        .foregroundStyle(isSelected ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
        .padding(.leading, 12)
        .padding(.trailing, 7)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? LyraTheme.fillColor : (isHovering ? LyraTheme.fillColor.opacity(0.5) : .clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isSelected ? LyraTheme.hairlineColor : .clear, lineWidth: 1)
        )
        .onHover { isHovering = $0 }
    }
}
