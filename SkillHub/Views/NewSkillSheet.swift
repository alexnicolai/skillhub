import SwiftUI

/// ⌘N — scaffold a new skill in the store and link it to chosen tools.
struct NewSkillSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var tagsText = ""
    @State private var tools: Set<Tool> = Set(Tool.active)
    @State private var errorText: String?
    @FocusState private var nameFocused: Bool

    private var validationHint: String? {
        name.isEmpty ? nil : SkillScaffold.validate(name: name, store: AppPaths.skillsDir)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Skill")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 4) {
                TextField("skill-name (lowercase-kebab)", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(AppText.mono)
                    .focused($nameFocused)
                if let hint = validationHint {
                    Text(hint)
                        .font(AppText.small)
                        .foregroundStyle(.orange)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                TextField("Description — models choose skills by this text", text: $description, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                Text("Say when a model should reach for it, not just what it does.")
                    .font(AppText.small)
                    .foregroundStyle(.tertiary)
            }

            TextField("Tags (comma separated, optional)", text: $tagsText)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("AVAILABLE IN")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(.tertiary)
                FlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(Tool.active) { tool in
                        let on = tools.contains(tool)
                        Button {
                            if on { tools.remove(tool) } else { tools.insert(tool) }
                        } label: {
                            HStack(spacing: 5) {
                                ToolLogo(tool: tool, size: 11)
                                Text(tool.displayName)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4.5)
                            .background(on ? Color.primary.opacity(0.1) : Color.clear, in: Capsule())
                            .overlay(
                                Capsule().strokeBorder(
                                    on ? Color.clear : Color.primary.opacity(0.18),
                                    style: StrokeStyle(lineWidth: 1, dash: on ? [] : [3, 2.5]))
                            )
                            .foregroundStyle(on ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
            }

            if let errorText {
                Text(errorText).font(AppText.secondary).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create & Edit") { create() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || validationHint != nil)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { nameFocused = true }
    }

    private func create() {
        let tags = tagsText.split(separator: ",").compactMap { Tags.normalize(String($0)) }
        do {
            try appState.createSkill(
                name: name, description: description, tags: tags, tools: tools)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
