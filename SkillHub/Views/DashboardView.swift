import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showDriftPopover = false
    @State private var showCoveragePopover = false
    @State private var pendingRemoval: Set<String> = []
    /// Folders chosen for import whose names already exist in the store.
    @State private var pendingImport: [URL] = []
    @State private var pendingImportDuplicates: [String] = []
    @State private var dropTargeted = false

    var body: some View {
        @Bindable var state = appState
        NavigationSplitView {
            TagSidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220)
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
            .navigationSplitViewColumnWidth(min: 320, ideal: 380)
        } detail: {
            detailPane
        }
        .toolbar { toolbarContent }
        .sheet(isPresented: $state.showGitPanel) {
            NavigationStack {
                GitPanelView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { state.showGitPanel = false }
                        }
                    }
            }
            .frame(minWidth: 520, minHeight: 420)
        }
        .sheet(isPresented: $state.showNewSkill) { NewSkillSheet() }
        .sheet(isPresented: $state.showInstall) { InstallSheet() }
        .onChange(of: state.showImport) { _, wanted in
            guard wanted else { return }
            state.showImport = false
            chooseFoldersToImport()
        }
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
        // Notices: the one place every action reports back.
        .overlay(alignment: .bottom) {
            if let notice = state.notice {
                NoticeBanner(notice: notice) { state.notice = nil }
                    .padding(.bottom, 14)
                    .transition(Motion.popIn(reduceMotion: reduceMotion))
            }
        }
        .animation(Motion.small, value: state.notice)
        .confirmationDialog(
            pendingImportDuplicates.count == 1
                ? "\(pendingImportDuplicates[0]) already exists in the library"
                : "\(pendingImportDuplicates.count) of these skills already exist in the library",
            isPresented: Binding(
                get: { !pendingImportDuplicates.isEmpty },
                set: { if !$0 { pendingImportDuplicates = []; pendingImport = [] } }
            )
        ) {
            Button("Replace Existing", role: .destructive) {
                _ = appState.importLocalSkills(pendingImport, replaceExisting: true)
                pendingImport = []; pendingImportDuplicates = []
            }
            Button("Import Only New Ones") {
                _ = appState.importLocalSkills(pendingImport, replaceExisting: false)
                pendingImport = []; pendingImportDuplicates = []
            }
            Button("Cancel", role: .cancel) { pendingImport = []; pendingImportDuplicates = [] }
        } message: {
            Text("Replacing swaps in the new files for every tool at once. The previous version stays in git history.")
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
                .contextMenu { rowMenu(for: skill) }
        }
        .confirmationDialog(
            pendingRemoval.count > 1
                ? "Remove \(pendingRemoval.count) skills from the library?"
                : "Remove \(pendingRemoval.first ?? "") from the library?",
            isPresented: Binding(
                get: { !pendingRemoval.isEmpty },
                set: { if !$0 { pendingRemoval = [] } }
            )
        ) {
            Button("Remove from Library and All Tools", role: .destructive) {
                appState.deleteSkills(pendingRemoval)
                pendingRemoval = []
            }
            Button("Cancel", role: .cancel) { pendingRemoval = [] }
        } message: {
            Text("Unlinks from every tool and deletes from the store. Git history keeps copies; locally-modified tool copies are never deleted.")
        }
        .searchable(text: $state.searchText, prompt: searchPrompt)
        .navigationTitle(contentTitle)
        // Things that need attention live above the list, where there is
        // room for words — the toolbar squeezed them down to bare icons.
        .safeAreaInset(edge: .top, spacing: 0) {
            if hasAttentionItems {
                statusItems
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
                    .overlay(alignment: .bottom) { Divider() }
            }
        }
        .overlay {
            if state.skills.isEmpty {
                ContentUnavailableView {
                    Label("No skills yet", systemImage: "square.stack.3d.up")
                } description: {
                    Text(state.loadError ?? "Create one (⌘N), install from GitHub (⇧⌘I), or drop skill folders here.")
                }
            } else if state.filteredSkills.isEmpty && !state.searchText.isEmpty {
                ContentUnavailableView.search(text: state.searchText)
            } else if state.filteredSkills.isEmpty {
                emptyScopeView
            }
        }
        // Drop skill folders (or SKILL.md files) from Finder to import them.
        .dropDestination(for: URL.self) { urls, _ in
            let candidates = urls.filter { $0.isFileURL }
            guard !candidates.isEmpty else { return false }
            beginImport(candidates)
            return true
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.brand, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(Color.brand.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        Label("Drop to import into the library", systemImage: "square.and.arrow.down")
                            .font(AppText.bodySemibold)
                            .foregroundStyle(Color.brand)
                            .padding(10)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func rowMenu(for skill: Skill) -> some View {
        let selection = appState.selectedSkillNames.contains(skill.name) && appState.selectedSkillNames.count > 1
            ? appState.selectedSkillNames : [skill.name]
        let n = selection.count
        if !Set(appState.activeTools).isSubset(of: skill.liveTools) || n > 1 {
            Button {
                appState.enableEverywhere(selection)
            } label: {
                Label(n > 1 ? "Make \(n) Skills Available in Every Tool" : "Make Available in Every Tool",
                      systemImage: "link")
            }
        }
        Button {
            NSWorkspace.shared.open(skill.folderURL.appendingPathComponent("SKILL.md"))
        } label: {
            Label("Open SKILL.md in Default Editor", systemImage: "arrow.up.forward.app")
        }
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([skill.folderURL])
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }
        ShareMenu(skill: skill)
        Divider()
        Button(role: .destructive) {
            pendingRemoval = selection
        } label: {
            Label(n > 1 ? "Remove \(n) Skills from Library…" : "Remove from Library…",
                  systemImage: "trash")
        }
    }

    @ViewBuilder
    private var emptyScopeView: some View {
        switch appState.sidebarSelection {
        case .issues:
            ContentUnavailableView("All healthy", systemImage: "checkmark.seal",
                description: Text("No skills have doctor findings."))
        case .gaps:
            ContentUnavailableView("Everything, everywhere", systemImage: "checkmark.seal",
                description: Text("Every skill is available in every tool."))
        case .unused:
            ContentUnavailableView("Everything gets used", systemImage: "chart.bar",
                description: Text("Every skill has at least one recorded use."))
        case .tool(let tool):
            ContentUnavailableView("Nothing linked yet", systemImage: "link",
                description: Text("Right-click \(tool.displayName) in the sidebar to link every skill."))
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
                Text("\(state.skills.count) skills across \(state.activeTools.count) tools — one source of truth. ⌘K to jump, ⌘N to create, ⇧⌘I to install.")
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    appState.showNewSkill = true
                } label: {
                    Label("New Skill…", systemImage: "square.and.pencil")
                }
                Button {
                    appState.showInstall = true
                } label: {
                    Label("Install from GitHub…", systemImage: "arrow.down.to.line")
                }
                Button {
                    appState.showImport = true
                } label: {
                    Label("Import Skill Folder…", systemImage: "folder.badge.plus")
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .help("Create (⌘N), install from GitHub (⇧⌘I), or import a folder (⌘O)")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                appState.showGitPanel = true
            } label: {
                Label("Git Sync", systemImage: "arrow.triangle.branch")
            }
            .help("Repo status, commit, push, pull (⇧⌘G)")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                appState.reload()
                appState.checkForUpdates(force: true)
            } label: {
                if appState.checkingUpdates {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .disabled(appState.checkingUpdates)
            .help("Reload catalog and check for upstream updates (⌘R)")
        }
    }

    private var contentTitle: String {
        switch appState.sidebarSelection {
        case .all: return "All Skills"
        case .updates: return "Updates"
        case .issues: return "Issues"
        case .gaps: return "Not in every tool"
        case .unused: return "No recorded uses"
        case .conflicts: return "Conflicts"
        case .inbox: return "Inbox"
        case .tool(let tool): return tool.displayName
        case .tag(let tag): return "#\(tag)"
        }
    }

    private var searchPrompt: String {
        switch appState.sidebarSelection {
        case .all: return "Search \(appState.skills.count) skills"
        case .tag(let tag): return "Search #\(tag)"
        case .tool(let tool): return "Search \(tool.displayName)"
        default: return "Search"
        }
    }

    // MARK: - Status pills

    private var hasAttentionItems: Bool {
        !appState.isMigrated || !appState.drift.isEmpty
            || !appState.gapSkills.isEmpty || !appState.updateAvailable.isEmpty
    }

    private var statusItems: some View {
        HStack(spacing: 6) {
            if !appState.isMigrated {
                Label("Legacy layout — run Adopt to unify", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
            if !appState.drift.isEmpty {
                statusPill("\(appState.drift.count) drift",
                           icon: "exclamationmark.arrow.triangle.2.circlepath", color: .orange) {
                    showDriftPopover = true
                }
                .popover(isPresented: $showDriftPopover) {
                    DriftListView()
                        .frame(minWidth: 460, minHeight: 240)
                }
            }
            if !appState.gapSkills.isEmpty {
                statusPill("\(appState.gapSkills.count) not everywhere",
                           icon: "circle.dotted", color: .brand) {
                    showCoveragePopover = true
                }
                .popover(isPresented: $showCoveragePopover) {
                    CoveragePopover()
                }
            }
            if !appState.updateAvailable.isEmpty {
                statusPill("\(appState.updateAvailable.count) updates",
                           icon: "arrow.down.circle", color: .brand) {
                    appState.sidebarSelection = .updates
                }
            }
        }
        .animation(Motion.small, value: appState.drift.count)
        .animation(Motion.small, value: appState.gapSkills.count)
        .animation(Motion.small, value: appState.updateAvailable.count)
    }

    private func statusPill(_ text: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(text, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color.opacity(0.14), in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .transition(Motion.popIn(reduceMotion: reduceMotion))
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
        .help(appState.serverError ?? "Agents read the live catalog from this address")
    }

    // MARK: - Import

    private func chooseFoldersToImport() {
        let panel = NSOpenPanel()
        panel.title = "Import skills"
        panel.message = "Choose skill folders (each containing a SKILL.md) or SKILL.md files."
        panel.prompt = "Import"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.folder, .plainText, UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        beginImport(panel.urls)
    }

    /// Ask before replacing existing skills; otherwise import straight away.
    private func beginImport(_ urls: [URL]) {
        let names = urls.map { url -> String in
            let folder = url.lastPathComponent == "SKILL.md" ? url.deletingLastPathComponent() : url
            return folder.lastPathComponent
        }
        let existing = Set(appState.skills.map(\.name))
        let duplicates = names.filter { existing.contains($0) }
        if duplicates.isEmpty {
            let result = appState.importLocalSkills(urls, replaceExisting: false)
            if result.imported.isEmpty, let first = result.skipped.first {
                appState.notify(.error, "Nothing imported — \(first.name): \(first.reason)")
            }
        } else {
            pendingImport = urls
            pendingImportDuplicates = duplicates
        }
    }
}

/// Per-tool coverage at a glance with the one button that matters.
private struct CoveragePopover: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Coverage").font(.headline)
                Text("Which of your tools can see every skill.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(appState.activeTools) { tool in
                    let linked = appState.linkedCount(for: tool)
                    let total = appState.skills.count
                    GridRow {
                        Label {
                            Text(tool.displayName)
                        } icon: {
                            ToolLogo(tool: tool, size: 12)
                        }
                        .font(AppText.secondary)
                        ProgressView(value: Double(linked), total: Double(max(total, 1)))
                            .tint(linked == total ? Color.green : Color.brand)
                            .frame(width: 140)
                        Text("\(linked)/\(total)")
                            .font(AppText.small.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
            HStack {
                Button("Show Skills") {
                    appState.sidebarSelection = .gaps
                    dismiss()
                }
                Spacer()
                Button {
                    appState.linkEverythingEverywhere()
                    dismiss()
                } label: {
                    Label("Link Every Skill to Every Tool", systemImage: "link")
                }
                .buttonStyle(.borderedProminent)
                .help("Symlinks every skill into every detected tool (⇧⌘L)")
            }
        }
        .padding(16)
        .frame(width: 380)
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
