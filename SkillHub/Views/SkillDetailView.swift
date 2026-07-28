import SwiftUI
import MarkdownUI

struct SkillDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let skill: Skill
    @State private var updateError: String?
    @State private var confirmOverwrite = false

    enum Tab: Int, CaseIterable {
        case preview, edit, files, provenance

        var title: String {
            switch self {
            case .preview: return "Preview"
            case .edit: return "Edit"
            case .files: return "Files"
            case .provenance: return "Provenance"
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
            Divider()

            Picker("", selection: tabBinding) {
                ForEach(Tab.allCases, id: \.self) { Text($0.title) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)
            .padding(.vertical, 10)

            // Crossfade + subtle directional shift between structurally-similar
            // panes; exits are plain fades (shorter/simpler than entries).
            ZStack {
                switch tab {
                case .preview: previewTab
                case .edit: MarkdownEditorView(fileURL: skillMdURL, content: $skillMdContent)
                case .files: filesTab
                case .provenance: provenanceTab
                }
            }
            .id(tab)
            .transition(Motion.paneSwap(direction: tabDirection, reduceMotion: reduceMotion))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .navigationTitle(skill.name)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(skill.name)
                    .font(.title2.bold())
                    .textSelection(.enabled)
                if skill.updateAvailable {
                    Button {
                        applyUpdate(override: false)
                    } label: {
                        Label("Update", systemImage: "arrow.down.circle.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.blue.opacity(0.14), in: Capsule())
                    .foregroundStyle(.blue)
                    .transition(Motion.popIn(reduceMotion: reduceMotion))
                    .help("Update from \(skill.provenance.source ?? "upstream")")
                }
                Spacer()
                if skill.usageCount > 0 {
                    Label("\(skill.usageCount)", systemImage: "chart.bar.fill")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .help("Used \(skill.usageCount) times (Claude Code transcripts)")
                }
            }

            Text(skill.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let updateError {
                Label(updateError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .transition(Motion.popIn(reduceMotion: reduceMotion))
            }

            ToolTogglesView(skill: skill)
                .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
                Markdown(FrontmatterParser.body(of: skillMdContent))
                    .markdownTheme(.gitHub)
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
            HStack(spacing: 8) {
                Image(systemName: iconForFile(rel))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(rel)
                    .font(.system(.callout, design: .monospaced))
                Spacer()
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [skill.folderURL.appendingPathComponent(rel)])
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
            }
            .padding(.vertical, 1)
        }
        .scrollContentBackground(.hidden)
    }

    private func iconForFile(_ path: String) -> String {
        if path.hasSuffix(".md") { return "doc.text" }
        if path.hasSuffix(".yaml") || path.hasSuffix(".yml") || path.hasSuffix(".json") { return "gearshape" }
        if path.hasSuffix(".css") || path.hasSuffix(".mjs") || path.hasSuffix(".js") { return "curlybraces" }
        return "doc"
    }

    private var provenanceTab: some View {
        Form {
            Section("Source") {
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
            Section("State") {
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
            Section("Location") {
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
