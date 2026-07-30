import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showGitPanel = false
    @State private var showDriftPopover = false
    @State private var showNewSkill = false
    @State private var showInstall = false
    @State private var pendingRemoval: Set<String> = []

    var body: some View {
        @Bindable var state = appState
        NavigationSplitView {
            TagSidebarView()
                .navigationSplitViewColumnWidth(min: 170, ideal: 200)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    sidebarFooter
                }
        } content: {
            Group {
                switch state.sidebarSelection {
                case .conflicts: ConflictsListView()
                case .inbox: InboxListView()
                default: skillList
                }
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 360)
        } detail: {
            detailPane
        }
        .toolbar { toolbarContent }
        .sheet(isPresented: $showGitPanel) {
            NavigationStack {
                GitPanelView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showGitPanel = false }
                        }
                    }
            }
            .frame(minWidth: 520, minHeight: 420)
        }
        .sheet(isPresented: $showNewSkill) { NewSkillSheet() }
        .sheet(isPresented: $showInstall) { InstallSheet() }
        // Quick open is an overlay, not a sheet: click anywhere outside (or esc)
        // dismisses it.
        .overlay {
            if state.showQuickOpen {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { state.showQuickOpen = false }
                    QuickOpenView()
                        .padding(.top, 90)
                }
                .ignoresSafeArea()
                .transition(Motion.popIn(reduceMotion: reduceMotion))
            }
        }
        .animation(Motion.small, value: state.showQuickOpen)
        // Menu-less access points for the command shortcuts.
        .background {
            Group {
                Button("") { showNewSkill = true }
                    .keyboardShortcut("n", modifiers: .command)
                Button("") { state.showQuickOpen = true }
                    .keyboardShortcut("k", modifiers: .command)
                Button("") { showInstall = true }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            .hidden()
        }
    }

    // MARK: - Columns

    private var skillList: some View {
        @Bindable var state = appState
        // Selection highlight is high-frequency: List stays un-animated.
        // Rows are draggable onto sidebar tags; drag any selected row to
        // carry the whole selection.
        return List(state.filteredSkills, selection: $state.selectedSkillNames) { skill in
            SkillRowView(skill: skill)
                .tag(skill.name)
                .draggable(skill.name)
                .contextMenu {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([skill.folderURL])
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    ShareMenu(skill: skill)
                    Divider()
                    Button(role: .destructive) {
                        pendingRemoval = state.selectedSkillNames.contains(skill.name) && state.selectedSkillNames.count > 1
                            ? state.selectedSkillNames
                            : [skill.name]
                    } label: {
                        let n = state.selectedSkillNames.contains(skill.name)
                            ? max(state.selectedSkillNames.count, 1) : 1
                        Label(n > 1 ? "Remove \(n) Skills from Hub…" : "Remove from Hub…",
                              systemImage: "trash")
                    }
                }
        }
        .confirmationDialog(
            pendingRemoval.count > 1
                ? "Remove \(pendingRemoval.count) skills from the hub?"
                : "Remove \(pendingRemoval.first ?? "") from the hub?",
            isPresented: Binding(
                get: { !pendingRemoval.isEmpty },
                set: { if !$0 { pendingRemoval = [] } }
            )
        ) {
            Button("Remove from Hub and All Tools", role: .destructive) {
                appState.deleteSkills(pendingRemoval)
                pendingRemoval = []
            }
            Button("Cancel", role: .cancel) { pendingRemoval = [] }
        } message: {
            Text("Unlinks from every tool and deletes from the store. Git history keeps copies; locally-modified tool copies are never deleted.")
        }
        .searchable(text: $state.searchText, prompt: searchPrompt)
        .navigationTitle(contentTitle)
        .overlay {
            if state.skills.isEmpty {
                ContentUnavailableView(
                    "No skills found",
                    systemImage: "square.stack.3d.up",
                    description: Text(state.loadError ?? "Nothing in \(CatalogService.isMigrated ? "skills/" : "claude-skills/ or cursor-skills/") yet.")
                )
            } else if state.filteredSkills.isEmpty && !state.searchText.isEmpty {
                ContentUnavailableView.search(text: state.searchText)
            } else if state.filteredSkills.isEmpty {
                emptyScopeView
            }
        }
    }

    @ViewBuilder
    private var emptyScopeView: some View {
        switch appState.sidebarSelection {
        case .issues:
            ContentUnavailableView("All healthy", systemImage: "checkmark.seal",
                description: Text("No skills have doctor findings."))
        case .unused:
            ContentUnavailableView("Everything gets used", systemImage: "chart.bar",
                description: Text("Every skill has at least one recorded use."))
        default:
            ContentUnavailableView("No skills here", systemImage: "number",
                description: Text("Nothing carries this tag yet — add it from a skill's header, or drag skills onto the tag."))
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        @Bindable var state = appState
        if state.sidebarSelection == .conflicts || state.sidebarSelection == .inbox {
            ContentUnavailableView {
                Label(state.sidebarSelection == .conflicts ? "Review conflicts" : "Review submissions",
                      systemImage: state.sidebarSelection == .conflicts ? "exclamationmark.triangle" : "tray")
            } description: {
                Text(state.sidebarSelection == .conflicts
                     ? "Resolve each parked copy in the middle column."
                     : "Approve or reject each proposal in the middle column.")
            }
        } else if let skill = state.selectedSkill {
            SkillDetailView(skill: skill)
        } else if state.selectedSkillNames.count > 1 {
            BulkActionsView(names: state.selectedSkillNames) {
                pendingRemoval = state.selectedSkillNames
            }
        } else {
            ContentUnavailableView {
                Label("Select a skill", systemImage: "wand.and.stars")
            } description: {
                Text("\(state.skills.count) skills across \(activeToolCount) tools — one source of truth. ⌘K to jump, ⌘N to create, ⇧⌘I to install.")
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .status) {
            statusItem
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    showNewSkill = true
                } label: {
                    Label("New Skill…", systemImage: "square.and.pencil")
                }
                Button {
                    showInstall = true
                } label: {
                    Label("Install from GitHub…", systemImage: "arrow.down.to.line")
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .help("Create a new skill (⌘N) or install from a GitHub repo (⇧⌘I)")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                showGitPanel = true
            } label: {
                Label("Git Sync", systemImage: "arrow.triangle.branch")
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .help("Repo status, commit, push, pull")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                appState.reload()
                appState.checkForUpdates()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .help("Reload catalog and check for upstream updates")
        }
    }

    private var activeToolCount: Int {
        Tool.active.count
    }

    private var contentTitle: String {
        switch appState.sidebarSelection {
        case .all: return "All Skills"
        case .updates: return "Updates"
        case .issues: return "Issues"
        case .unused: return "No recorded uses"
        case .conflicts: return "Conflicts"
        case .inbox: return "Inbox"
        case .tag(let tag): return "#\(tag)"
        }
    }

    private var searchPrompt: String {
        switch appState.sidebarSelection {
        case .all: return "Search \(appState.skills.count) skills"
        case .tag(let tag): return "Search #\(tag)"
        default: return "Search"
        }
    }

    // MARK: - Status / drift

    @ViewBuilder
    private var statusItem: some View {
        if !appState.isMigrated {
            Label("Legacy layout — run Adopt to unify", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.caption)
        } else if !appState.drift.isEmpty {
            Button {
                showDriftPopover = true
            } label: {
                Label("\(appState.drift.count) drift", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.orange.opacity(0.14), in: Capsule())
            .transition(Motion.popIn(reduceMotion: reduceMotion))
            .popover(isPresented: $showDriftPopover) {
                DriftListView()
                    .frame(minWidth: 440, minHeight: 220)
            }
            .animation(Motion.small, value: appState.drift.count)
        } else if !appState.updateAvailable.isEmpty {
            Label("\(appState.updateAvailable.count) updates", systemImage: "arrow.down.circle")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.brand)
                .transition(Motion.popIn(reduceMotion: reduceMotion))
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.serverPort > 0 ? .green : .red)
                .frame(width: 6, height: 6)
            Text(appState.serverPort > 0
                 ? "API · 127.0.0.1:\(String(appState.serverPort))"
                 : "API offline")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(appState.skills.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// Share actions for a skill: export a zip, copy path/source.
struct ShareMenu: View {
    let skill: Skill

    var body: some View {
        Menu {
            Button {
                exportZip()
            } label: {
                Label("Export as Zip…", systemImage: "doc.zipper")
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(skill.folderURL.path, forType: .string)
            } label: {
                Label("Copy Folder Path", systemImage: "doc.on.doc")
            }
            if let url = skill.provenance.sourceUrl {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                } label: {
                    Label("Copy Source URL", systemImage: "link")
                }
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }

    private func exportZip() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(skill.name).zip"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent",
                             skill.folderURL.resolvingSymlinksInPath().path, dest.path]
        try? process.run()
        process.waitUntilExit()
    }
}
