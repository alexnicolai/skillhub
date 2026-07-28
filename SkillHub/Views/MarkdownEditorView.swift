import SwiftUI

/// Raw SKILL.md editor. Writes are atomic and always land in the canonical file
/// (symlinks resolved) so tool dirs can never diverge from the store.
struct MarkdownEditorView: View {
    let fileURL: URL
    @Binding var content: String

    @State private var savedContent: String = ""
    @State private var saveError: String?

    private var isDirty: Bool { content != savedContent }

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $content)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)

            Divider()
            HStack {
                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                if isDirty {
                    Button("Revert") { content = savedContent }
                    Button("Save") { save() }
                        .keyboardShortcut("s", modifiers: .command)
                        .buttonStyle(.borderedProminent)
                } else {
                    Text("Saved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
        .onAppear { savedContent = content }
        .onChange(of: fileURL) {
            savedContent = content
            saveError = nil
        }
    }

    private func save() {
        do {
            try SkillFileWriter.write(content, to: fileURL)
            savedContent = content
            saveError = nil
        } catch {
            saveError = "Save failed: \(error.localizedDescription)"
        }
    }
}
