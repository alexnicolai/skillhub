import SwiftUI

/// Raw SKILL.md editor with autosave. Writes are atomic and always land in the
/// canonical file (symlinks resolved) so tool dirs can never diverge from the
/// store. Edits save ~1s after typing stops, on ⌘S, and when the editor goes
/// away — nothing is lost by clicking another skill.
struct MarkdownEditorView: View {
    let fileURL: URL
    @Binding var content: String
    /// Called after every successful write so the catalog can refresh.
    var onSaved: (() -> Void)? = nil

    @State private var savedContent: String = ""
    @State private var saveError: String?
    @State private var saveTask: Task<Void, Never>?
    @State private var lastSavedAt: Date?

    private var isDirty: Bool { content != savedContent }

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $content)
                .font(.system(size: 14, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)

            Divider()
            HStack(spacing: 10) {
                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                } else if isDirty {
                    Label("Unsaved changes — saving automatically", systemImage: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label(lastSavedAt.map { "Saved \($0.formatted(.relative(presentation: .named)))" } ?? "Saved",
                          systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isDirty {
                    Button("Revert") { revert() }
                    Button("Save Now") { save() }
                        .keyboardShortcut("s", modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            .padding(8)
        }
        .onAppear { savedContent = content }
        .onDisappear { flush() }
        .onChange(of: fileURL) {
            // A different skill was loaded into the binding: nothing to carry over.
            saveTask?.cancel()
            savedContent = content
            saveError = nil
            lastSavedAt = nil
        }
        .onChange(of: content) { scheduleSave() }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        guard isDirty else { return }
        let url = fileURL
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, url == fileURL else { return }
            save()
        }
    }

    /// Write immediately if there is anything unsaved.
    private func flush() {
        saveTask?.cancel()
        if isDirty { save() }
    }

    private func revert() {
        saveTask?.cancel()
        content = savedContent
    }

    private func save() {
        guard isDirty else { return }
        // Skip writes that wouldn't change the file (e.g. the binding was
        // re-populated from disk).
        if let onDisk = try? String(contentsOf: fileURL, encoding: .utf8), onDisk == content {
            savedContent = content
            return
        }
        do {
            try SkillFileWriter.write(content, to: fileURL)
            savedContent = content
            saveError = nil
            lastSavedAt = Date()
            onSaved?()
        } catch {
            saveError = "Save failed: \(error.localizedDescription)"
        }
    }
}
