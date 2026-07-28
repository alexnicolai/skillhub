import SwiftUI
import MarkdownUI

struct SkillDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let skill: Skill
    @State private var updateError: String?
    @State private var confirmOverwrite = false
    @State private var confirmDelete = false
    @State private var showDiff = false
    @State private var upstreamDiff = ""
    @State private var diffLoading = false
    @State private var showIssues = false
    @State private var historyEntries: [GitService.HistoryEntry] = []

    enum Tab: Int, CaseIterable {
        case preview, edit, files, info

        var title: String {
            switch self {
            case .preview: return "Preview"
            case .edit: return "Edit"
            case .files: return "Files"
            case .info: return "Info"
            }
        }
    }

    @State private var tab: Tab = .preview
    /// +1 when moving to a later tab, -1 earlier — drives the directional hint.
    @State private var tabDirection: CGFloat = 1
    @State private var skillMdContent: String = ""

    private var skillMdURL: URL {
        skill.folderURL.appendingPathComponent("SKILL.md")
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            UnderlineTabs(
                tabs: Tab.allCases.map { ($0, $0.title) },
                selection: tabBinding
            )
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Divider() }

            // Crossfade + subtle directional shift between structurally-similar
            // panes; exits are plain fades (shorter/simpler than entries).
            ZStack {
                switch tab {
                case .preview: previewTab
                case .edit: MarkdownEditorView(fileURL: skillMdURL, content: $skillMdContent)
                case .files: filesTab
                case .info: infoTab
                }
            }
            .id(tab)
            .transition(Motion.paneSwap(direction: tabDirection, reduceMotion: reduceMotion))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .navigationTitle(skill.name)
        .toolbar {
            // One overflow menu instead of scattered lone icons.
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([skill.folderURL])
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    ShareMenu(skill: skill)
                    Divider()
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Remove from Hub…", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .help("Reveal, share, or remove this skill")
            }
        }
        // Loading history in .task (not during body evaluation) — the git
        // subprocess in the Form was wedging the tab transition until the next
        // window event.
        .task(id: skill.name) {
            let name = skill.name
            let entries = await Task.detached {
                GitService().history(path: "skills/\(name)", limit: 8)
            }.value
            if name == skill.name { historyEntries = entries }
        }
        .sheet(isPresented: $showDiff) {
            DiffSheet(
                title: "\(skill.name): local vs upstream",
                diff: upstreamDiff,
                confirmLabel: "Update Skill File"
            ) {
                applyUpdate(override: false)
            }
        }
        .onAppear { loadContent() }
        .onChange(of: skill.name) {
            loadContent()
            // Selection changes are high-frequency: swap content instantly,
            // never animate the pane on a new skill.
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { tab = .preview }
        }
        .confirmationDialog(
            "Overwrite local changes?",
            isPresented: $confirmOverwrite
        ) {
            Button("Overwrite with upstream", role: .destructive) { applyUpdate(override: true) }
            Button("Keep local version", role: .cancel) { updateError = nil }
        } message: {
            Text("This skill was modified locally after install. Updating replaces those edits (git history keeps them).")
        }
        .confirmationDialog(
            "Remove \(skill.name) from the hub?",
            isPresented: $confirmDelete
        ) {
            Button("Remove from Hub and All Tools", role: .destructive) {
                appState.deleteSkill(skill.name)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unlinks it from every tool and deletes it from the store. Git history keeps a copy; locally-modified tool copies are never deleted.")
        }
    }

    /// Tab switches animate; direction follows index order (forward = right).
    private var tabBinding: Binding<Tab> {
        Binding(
            get: { tab },
            set: { newTab in
                tabDirection = newTab.rawValue >= tab.rawValue ? 1 : -1
                withAnimation(Motion.content) { tab = newTab }
            }
        )
    }

    private func loadContent() {
        skillMdContent = (try? String(contentsOf: skillMdURL, encoding: .utf8)) ?? ""
    }

    private func loadDiff() {
        guard let entry = appState.manifest.skills[skill.name] else { return }
        diffLoading = true
        let folder = skill.folderURL
        Task.detached {
            let diff = (try? UpdateChecker().diff(skill: entry, canonicalFolder: folder)) ?? ""
            await MainActor.run {
                upstreamDiff = diff
                diffLoading = false
                showDiff = true
            }
        }
    }

    private func applyUpdate(override: Bool) {
        do {
            try appState.applyUpdate(skill.name, overrideLocalChanges: override)
            updateError = nil
            loadContent()
        } catch {
            updateError = error.localizedDescription
            confirmOverwrite = true
        }
    }

    // MARK: - Header

    /// Micro-label for header groups: quiet, uppercase, adds structure without weight.
    private func groupLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(.tertiary)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Identity: name, update pill, usage.
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(skill.name)
                    .font(.system(size: 24, weight: .bold))
                    .textSelection(.enabled)
                if skill.updateAvailable {
                    HStack(spacing: 4) {
                        Button {
                            applyUpdate(override: false)
                        } label: {
                            Label("Update Skill File", systemImage: "arrow.down.circle.fill")
                                .font(AppText.secondary.weight(.semibold))
                        }
                        .buttonStyle(PressableButtonStyle())
                        .help("A newer version exists in \(skill.provenance.source ?? "the upstream repo") — click to update")
                        Divider().frame(height: 12)
                        Button {
                            loadDiff()
                        } label: {
                            if diffLoading {
                                ProgressView().controlSize(.mini)
                            } else {
                                Text("View changes")
                                    .font(AppText.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("See what changed upstream before updating")
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.brand.opacity(0.14), in: Capsule())
                    .foregroundStyle(Color.brand)
                    .transition(Motion.popIn(reduceMotion: reduceMotion))
                }
                Spacer()
                if skill.usageCount > 0 {
                    Label("\(skill.usageCount) uses", systemImage: "chart.bar.fill")
                        .font(AppText.secondary.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .help("Used \(skill.usageCount) times (Claude Code transcripts)")
                }
            }

            Text(skill.summary)
                .font(AppText.body)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.top, 6)

            if !skill.issues.isEmpty {
                Button {
                    showIssues = true
                } label: {
                    Label(
                        skill.issues.count == 1
                            ? skill.issues[0].message
                            : "\(skill.issues.count) issues found",
                        systemImage: skill.hasErrors ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(AppText.secondary.weight(.medium))
                    .lineLimit(1)
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background((skill.hasErrors ? Color.red : .orange).opacity(0.12), in: Capsule())
                .foregroundStyle(skill.hasErrors ? Color.red : .orange)
                .padding(.top, 8)
                .help("Click for details")
                .popover(isPresented: $showIssues, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(skill.issues.enumerated()), id: \.offset) { _, issue in
                            Label {
                                Text(issue.message).font(AppText.secondary)
                            } icon: {
                                Image(systemName: issue.severity == .error
                                      ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(issue.severity == .error ? .red : .orange)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: 400)
                }
            }

            if let updateError {
                Label(updateError, systemImage: "exclamationmark.triangle.fill")
                    .font(AppText.secondary)
                    .foregroundStyle(.orange)
                    .transition(Motion.popIn(reduceMotion: reduceMotion))
                    .padding(.top, 10)
            }

            // Metadata groups: labeled, stacked so pills never wrap mid-word.
            VStack(alignment: .leading, spacing: 7) {
                groupLabel("Tags")
                TagEditorView(skill: skill)
            }
            .padding(.top, 18)

            VStack(alignment: .leading, spacing: 7) {
                groupLabel("Available in")
                ToolTogglesView(skill: skill)
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Motion.small, value: skill.updateAvailable)
        .animation(Motion.small, value: updateError)
    }

    // MARK: - Tabs

    private var previewTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                frontmatterCard
                // Frontmatter is stripped: raw YAML reads as a giant setext
                // heading in Markdown. The header + card above cover it.
                // .docC theme inherits the window background — .gitHub paints
                // its own, which showed as a mismatched box in dark mode.
                Markdown(FrontmatterParser.body(of: skillMdContent))
                    .markdownTheme(.docC)
                    .textSelection(.enabled)
            }
            .padding(16)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    @State private var frontmatterExpanded = false

    @ViewBuilder
    private var frontmatterCard: some View {
        let fields = FrontmatterParser.parse(skillMdContent).fields
            .filter { $0.key != "description" }   // already in the header
        if !fields.isEmpty {
            DisclosureGroup(isExpanded: $frontmatterExpanded) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    ForEach(fields, id: \.key) { field in
                        GridRow {
                            Text(field.key)
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                                .gridColumnAlignment(.trailing)
                            Text(field.value)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Frontmatter · \(fields.count) fields", systemImage: "list.bullet.rectangle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var filesTab: some View {
        List(CatalogService.fileList(for: skill), id: \.self) { rel in
            FileRow(rel: rel, icon: iconForFile(rel), folderURL: skill.folderURL)
        }
        .scrollContentBackground(.hidden)
    }

    /// One file row: hover highlights the row and reveals its action.
    private struct FileRow: View {
        let rel: String
        let icon: String
        let folderURL: URL
        @State private var hovering = false

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(rel)
                    .font(AppText.mono)
                Spacer()
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [folderURL.appendingPathComponent(rel)])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                        .font(AppText.secondary)
                }
                .buttonStyle(.borderless)
                .opacity(hovering ? 1 : 0)
                .help("Show \(rel) in a Finder window")
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .background(
                Color.primary.opacity(hovering ? 0.06 : 0),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .onHover { h in
                withAnimation(.easeOut(duration: 0.12)) { hovering = h }
            }
        }
    }

    private func iconForFile(_ path: String) -> String {
        if path.hasSuffix(".md") { return "doc.text" }
        if path.hasSuffix(".yaml") || path.hasSuffix(".yml") || path.hasSuffix(".json") { return "gearshape" }
        if path.hasSuffix(".css") || path.hasSuffix(".mjs") || path.hasSuffix(".js") { return "curlybraces" }
        return "doc"
    }

    private var infoTab: some View {
        Form {
            if !skill.issues.isEmpty {
                Section("Health") {
                    ForEach(Array(skill.issues.enumerated()), id: \.offset) { _, issue in
                        Label {
                            Text(issue.message)
                                .font(AppText.secondary)
                        } icon: {
                            Image(systemName: issue.severity == .error
                                  ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(issue.severity == .error ? .red : .orange)
                        }
                    }
                }
            }
            Section("History") {
                if historyEntries.isEmpty {
                    Text("No commits recorded yet.")
                        .font(AppText.secondary)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(historyEntries.enumerated()), id: \.element.sha) { index, entry in
                        HStack(spacing: 8) {
                            Text(String(entry.sha.prefix(7)))
                                .font(AppText.mono)
                                .foregroundStyle(.tertiary)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(entry.subject)
                                    .font(AppText.secondary)
                                    .lineLimit(1)
                                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(AppText.small)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if index > 0 {
                                Button("Restore") {
                                    appState.restoreSkill(skill.name, to: entry.sha)
                                    loadContent()
                                }
                                .controlSize(.small)
                                .help("Bring back this version (the restore itself becomes a new commit — nothing is lost)")
                            } else {
                                Text("current")
                                    .font(AppText.small)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            Section("Where this skill came from") {
                LabeledContent("Type", value: skill.provenance.sourceType.rawValue)
                if let repo = skill.provenance.source {
                    LabeledContent("Repository", value: repo)
                }
                if let url = skill.provenance.sourceUrl, let link = URL(string: url) {
                    LabeledContent("URL") { Link(url, destination: link) }
                }
                if let path = skill.provenance.skillPath {
                    LabeledContent("Upstream path", value: path)
                }
            }
            Section("Versions & dates") {
                if let hash = skill.provenance.upstreamHash {
                    LabeledContent("Upstream hash", value: String(hash.prefix(12)))
                }
                if !skill.contentHash.isEmpty {
                    LabeledContent("Content hash", value: String(skill.contentHash.dropFirst(7).prefix(12)))
                }
                if let installed = skill.provenance.installedAt {
                    LabeledContent("Installed", value: installed.formatted(date: .abbreviated, time: .shortened))
                }
                if let updated = skill.provenance.updatedAt {
                    LabeledContent("Updated", value: updated.formatted(date: .abbreviated, time: .shortened))
                }
                if let last = skill.lastUsed {
                    LabeledContent("Last used", value: last.formatted(date: .abbreviated, time: .shortened))
                }
            }
            Section("On disk") {
                LabeledContent("Folder") {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([skill.folderURL])
                    } label: {
                        Text(skill.folderURL.path)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .formStyle(.grouped)
    }
}
