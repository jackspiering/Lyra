import SwiftUI

/// Editable note title above Source / Reading. Commits on Return or focus loss.
struct NoteTitleBar: View {
    /// Live display title (H1 or filename stem).
    let title: String
    /// Called with the committed title string (Return / focus loss).
    var onCommit: (String) -> Void

    @State private var draft: String = ""
    @State private var suppressFocusCommit = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Title", text: $draft)
            .font(LyraFonts.heading(1))
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit { commit() }
            .onExitCommand { revertAndBlur() }
            .onAppear { draft = title }
            .onChange(of: title) { _, newValue in
                // Keep draft in sync when H1/filename changes elsewhere, unless the user is editing.
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
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        onCommit(trimmed)
    }

    private func revertAndBlur() {
        if focused {
            suppressFocusCommit = true
        }
        draft = title
        focused = false
    }
}
