import SwiftUI

/// Leftmost column: the library, one "Needs Attention" queue, and tags.
/// Per-tool coverage sits in a compact footer (ToolCoverageBar) instead of a
/// section of its own. Tags replace folders — one skill can carry many.
struct TagSidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        List(selection: $state.sidebarSelection) {
            Section("Library") {
                Label("All Skills", systemImage: "square.stack.3d.up")
                    .badge(appState.skills.count)
                    .tag(SidebarItem.all)
                if appState.attentionCount > 0 {
                    Label("Needs Attention", systemImage: "exclamationmark.circle")
                        .badge(appState.attentionCount)
                        .tag(SidebarItem.attention)
                        .help("Skills missing from a tool, with an update, or with health problems — plus broken links and conflicts")
                }
                if !appState.inbox.isEmpty {
                    Label("Inbox", systemImage: "tray")
                        .badge(appState.inbox.count)
                        .tag(SidebarItem.inbox)
                        .help("Skills proposed by your agents, waiting for approval")
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
        .navigationTitle(Brand.displayName)
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

/// Sidebar footer: a glass capsule with one segment per tool showing how many skills it has.
/// Click a tool to list its skills (click again to go back to All Skills).
/// The dot on the right is the local API's status.
struct ToolCoverageBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 6) {
            // One glass capsule holding a segment per tool.
            if !appState.activeTools.isEmpty {
                HStack(spacing: 0) {
                    ForEach(appState.activeTools) { tool in
                        ToolChip(tool: tool)
                    }
                }
                .padding(2)
                .glassSurface()
            }
            Spacer(minLength: 0)
            Circle()
                .fill(appState.serverPort > 0 ? Color.green : Color.red)
                .frame(width: 6, height: 6)
                .help(appState.serverError
                      ?? (appState.serverPort > 0
                          ? "Agents read the live catalog from 127.0.0.1:\(String(appState.serverPort))"
                          : "API offline"))
                .accessibilityLabel(appState.serverPort > 0 ? "API online" : "API offline")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay {
            if appState.activeTools.isEmpty {
                Text("No AI tools detected — turn one on in Settings → Tools.")
                    .font(AppText.small)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private struct ToolChip: View {
        @Environment(AppState.self) private var appState
        let tool: Tool

        private var linked: Int { appState.linkedCount(for: tool) }
        private var total: Int { appState.skills.count }
        private var complete: Bool { total > 0 && linked == total }
        private var selected: Bool { appState.sidebarSelection == .tool(tool) }

        var body: some View {
            Button {
                appState.sidebarSelection = selected ? .all : .tool(tool)
            } label: {
                HStack(spacing: 4) {
                    ToolLogo(tool: tool, size: 11)
                    if complete {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                    } else {
                        Text("\(linked)")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                    }
                }
                .foregroundStyle(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(selected ? Color.brand : Color.clear, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(complete
                  ? "\(tool.displayName) has every skill"
                  : "\(tool.displayName): \(linked) of \(total) skills — click to list them, right-click to add the rest")
            .contextMenu {
                if !complete {
                    Button {
                        appState.enableAll(for: tool)
                    } label: {
                        Label("Add All \(total) Skills to \(tool.displayName)", systemImage: "link")
                    }
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([tool.skillsDir])
                } label: {
                    Label("Reveal Skills Folder in Finder", systemImage: "folder")
                }
            }
        }
    }
}
