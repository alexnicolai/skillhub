import SwiftUI
import MarkdownUI

struct SkillDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let skill: Skill
    @State private var updateError: String?
    @State private var confirmOverwrite = false
    @State private var confirmDelete = false

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
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Remove Skill", systemImage: "trash")
                }
                .help("Remove \(skill.name) from the hub and from every tool using it")
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
                    Button {
                        applyUpdate(override: false)
                    } label: {
                        Label("Update Skill File", systemImage: "arrow.down.circle.fill")
                            .font(AppText.secondary.weight(.semibold))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.brand.opacity(0.14), in: Capsule())
                    .foregroundStyle(Color.brand)
                    .transition(Motion.popIn(reduceMotion: reduceMotion))
                    .help("A newer version exists in \(skill.provenance.source ?? "the upstream repo") — click to update")
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

            if let updateError {
                Label(updateError, systemImage: "exclamationmark.triangle.fill")
                    .font(AppText.secondary)
                    .foregroundStyle(.orange)
                    .transition(Motion.popIn(reduceMotion: reduceMotion))
                    .padding(.top, 10)
            }

            // Metadata groups: labeled, evenly spaced, room to breathe.
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 7) {
                    groupLabel("Tags")
                    TagEditorView(skill: skill)
                }
                VStack(alignment: .leading, spacing: 7) {
                    groupLabel("Available in")
                    ToolTogglesView(skill: skill)
                }
            }
            .padding(.top, 18)
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
