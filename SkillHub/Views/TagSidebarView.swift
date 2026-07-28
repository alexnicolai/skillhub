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
                        TagRow(tag: entry.tag, count: entry.count)
                            .tag(SidebarItem.tag(entry.tag))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("SkillHub")
    }

    /// One tag row: drop target for skills dragged from the list.
    private struct TagRow: View {
        @Environment(AppState.self) private var appState
        let tag: String
        let count: Int
        @State private var targeted = false

        var body: some View {
            Label {
                Text(tag)
            } icon: {
                Image(systemName: "number")
                    .foregroundStyle(Color.brand)
            }
            .badge(count)
            .padding(.horizontal, targeted ? 4 : 0)
            .background(
                Color.brand.opacity(targeted ? 0.18 : 0),
                in: RoundedRectangle(cornerRadius: 5)
            )
            .animation(Motion.press, value: targeted)
            .dropDestination(for: String.self) { names, _ in
                let dropped = names.filter { name in
                    appState.skills.contains { $0.name == name }
                }
                guard !dropped.isEmpty else { return false }
                appState.addTag(tag, toAll: dropped)
                return true
            } isTargeted: { targeted = $0 }
            .contextMenu {
                Button(role: .destructive) {
                    appState.deleteTagEverywhere(tag)
                } label: {
                    Label("Remove Tag from All Skills", systemImage: "trash")
                }
            }
            .help("Drop skills here to tag them #\(tag)")
        }
    }
}
