import SwiftUI

/// Editable note title at the top of the writing column. Commits on Return or focus loss.
struct NoteTitleBar: View {
    /// Live display title (filename stem).
    let title: String
    /// Vault name and folders above the note, shown quietly over the title.
    var breadcrumb: [String] = []
    /// Called with the committed title string (Return / focus loss).
    /// Returns `false` when the rename failed; the field then shows the
    /// real name again instead of the rejected one.
    var onCommit: (String) -> Bool

    @State private var draft: String = ""
    @State private var suppressFocusCommit = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !breadcrumb.isEmpty {
                Text(breadcrumb.joined(separator: "  ›  "))
                    .font(LyraFonts.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .accessibilityLabel("In \(breadcrumb.joined(separator: ", "))")
            }
            titleField
        }
        .frame(maxWidth: LyraTheme.columnWidth, alignment: .leading)
        .padding(.horizontal, LyraTheme.columnMargin)
        .padding(.top, 36)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
    }

    private var titleField: some View {
        TextField("Title", text: $draft)
            .font(LyraFonts.title)
            .textFieldStyle(.plain)
            .accessibilityLabel("Note title")
            .focused($focused)
            .onSubmit { commit() }
            .onExitCommand { revertAndBlur() }
            .onAppear { draft = title }
            .onChange(of: title) { _, newValue in
                // Keep draft in sync when the file is renamed elsewhere, unless the user is editing.
                if !focused {
                    draft = newValue
                }
            }
            .onChange(of: focused) { _, isFocused in
                guard !isFocused else { return }
                if suppressFocusCommit {
                    suppressFocusCommit = false
                    return
                }
                commit()
            }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            draft = title
            return
        }
        if trimmed == title {
            return
        }
        if !onCommit(trimmed) {
            draft = title
        }
    }

    private func revertAndBlur() {
        if focused {
            suppressFocusCommit = true
        }
        draft = title
        focused = false
    }
}
