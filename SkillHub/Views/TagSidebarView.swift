import SwiftUI

/// Leftmost column: library scopes + user-defined tags.
/// Tags replace folders — one skill can carry many, and clicking one scopes
/// the skill list instantly.
struct TagSidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        List(selection: $state.sidebarSelection) {
            Section("Library") {
                Label("All Skills", systemImage: "square.stack.3d.up")
                    .badge(appState.skills.count)
                    .tag(SidebarItem.all)
                if !appState.updateAvailable.isEmpty {
                    Label("Updates", systemImage: "arrow.down.circle")
                        .badge(appState.updateAvailable.count)
                        .tag(SidebarItem.updates)
                }
            }

            Section("Tags") {
                if appState.allTags.isEmpty {
                    Text("Tag a skill to group it — tags show up here for one-click filtering.")
                        .font(AppText.secondary)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.allTags, id: \.tag) { entry in
                        Label {
                            Text(entry.tag)
                        } icon: {
                            Image(systemName: "number")
                                .foregroundStyle(Color.brand)
                        }
                        .badge(entry.count)
                        .tag(SidebarItem.tag(entry.tag))
                        .contextMenu {
                            Button(role: .destructive) {
                                appState.deleteTagEverywhere(entry.tag)
                            } label: {
                                Label("Remove Tag from All Skills", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("SkillHub")
    }
}
