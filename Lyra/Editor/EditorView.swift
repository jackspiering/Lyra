import SwiftUI

struct EditorView: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        Group {
            if viewModel.document != nil {
                MarkdownTextView(text: $viewModel.text) { newValue in
                    viewModel.textDidChange(newValue)
                }
            } else {
                ContentUnavailableView(
                    "Select a note",
                    systemImage: "doc.text",
                    description: Text("Choose a Markdown file from the sidebar, or create a new note.")
                )
            }
        }
    }
}
