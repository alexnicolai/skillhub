import SwiftUI

/// Inline tag chips + add field for one skill, shown in the detail header.
struct TagEditorView: View {
    @Environment(AppState.self) private var appState
    let skill: Skill

    @State private var adding = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(skill.tags, id: \.self) { tag in
                TagChip(tag: tag) {
                    appState.removeTag(tag, from: skill.name)
                }
                .contextMenu {
                    Button("Show all #\(tag)") { appState.sidebarSelection = .tag(tag) }
                }
            }

            if adding {
                TextField("tag name", text: $draft)
                    .textFieldStyle(.plain)
                    .font(AppText.secondary)
                    .frame(width: 110)
                    .focused($fieldFocused)
                    .onSubmit { commit() }
                    .onExitCommand { adding = false; draft = "" }
            } else {
                Button {
                    adding = true
                    fieldFocused = true
                } label: {
                    if skill.tags.isEmpty {
                        Label("Add tag", systemImage: "plus")
                            .font(AppText.small)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Tag this skill to group it — tags appear in the sidebar")

                // Quick-add from existing tags not yet on this skill.
                let candidates = appState.allTags.map(\.tag).filter { !skill.tags.contains($0) }
                if !candidates.isEmpty {
                    Menu {
                        ForEach(candidates, id: \.self) { tag in
                            Button("#\(tag)") { appState.addTag(tag, to: skill.name) }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 16)
                    .help("Add an existing tag")
                }
            }
        }
        .onChange(of: skill.name) { adding = false; draft = "" }
    }

    private func commit() {
        appState.addTag(draft, to: skill.name)
        draft = ""
        adding = false
    }
}

/// One tag chip: brand-tinted, × appears on hover.
struct TagChip: View {
    let tag: String
    var onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 3) {
            Text("#\(tag)")
                .font(.system(size: 11, weight: .medium))
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                }
                .buttonStyle(.plain)
                .help("Remove #\(tag) from this skill")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.brand.opacity(0.13), in: Capsule())
        .foregroundStyle(Color.brand)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) { hovering = h }
        }
    }
}
