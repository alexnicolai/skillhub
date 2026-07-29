import SwiftUI

/// First-run flow: welcome → pick/create/clone the skill store → connect tools.
struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage(AppPaths.defaultsKey) private var repoRootPath = ""

    enum Step: Int { case welcome, store, connect, done }
    @State private var step: Step = .welcome
    @State private var direction: CGFloat = 1

    // Store step state
    enum StoreMode: String, CaseIterable { case create = "Start fresh", clone = "Clone existing" }
    @State private var storeMode: StoreMode = .create
    @State private var pathText = "~/ai-skills"
    @State private var cloneURL = ""
    @State private var busy = false
    @State private var errorText: String?

    // Connect step state
    @State private var adoptLog: [String] = []
    @State private var adoptDone = false

    private var resolvedRoot: URL {
        URL(fileURLWithPath: (pathText as NSString).expandingTildeInPath)
    }

    private var storeExists: Bool {
        FileManager.default.fileExists(
            atPath: resolvedRoot.appendingPathComponent("skills").path)
            || FileManager.default.fileExists(
                atPath: resolvedRoot.appendingPathComponent("skillhub.json").path)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case .welcome: welcome
                case .store: store
                case .connect: connect
                case .done: done
                }
            }
            .id(step)
            .transition(Motion.paneSwap(direction: direction, reduceMotion: reduceMotion))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(width: 560, height: 460)
        .overlay { if busy { ProgressView().controlSize(.large) } }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.linearGradient(
                    colors: [Color.brand, .purple], startPoint: .top, endPoint: .bottom))
            Text("Welcome to \(Brand.displayName)")
                .font(.title.bold())
            Text("One source of truth for your AI agent skills.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                bullet("square.stack.3d.up", "One store, every tool",
                       "Claude Code, Cursor, Codex, OpenCode, Gemini CLI, and Kiro all read the same skill folders via symlinks.")
                bullet("arrow.down.circle", "Updates & provenance",
                       "See where each skill came from and pull upstream updates with one click.")
                bullet("antenna.radiowaves.left.and.right", "A catalog agents can query",
                       "A local API + meta-skill lets any model look up your latest skills.")
            }
            .padding(.top, 8)
            .frame(maxWidth: 420, alignment: .leading)
        }
        .padding(28)
    }

    private var store: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Where should your skills live?")
                .font(.title2.bold())
            Text("A git repository holds every skill — push it to GitHub to sync across machines.")
                .foregroundStyle(.secondary)

            HStack {
                TextField("Path", text: $pathText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button("Choose…") { choosePath() }
                    .help("Pick a folder with an open panel")
            }

            if storeExists {
                Label("Existing skill store detected — \(Brand.displayName) will use it as-is.",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                Picker("", selection: $storeMode) {
                    ForEach(StoreMode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if storeMode == .clone {
                    TextField("https://github.com/you/your-skills.git", text: $cloneURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.callout, design: .monospaced))
                    Text("Clones your existing skills repo (e.g. from another machine).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Creates the folder, runs `git init`, and starts an empty store. Skills already installed in your tools get imported in the next step.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorText {
                ScrollView {
                    Text(errorText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 80)
            }
            Spacer()
        }
        .padding(28)
    }

    private var connect: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect your tools")
                .font(.title2.bold())
            Text("\(Brand.displayName) imports every skill your tools already have into the store (originals are backed up), then links the tools to it.")
                .foregroundStyle(.secondary)

            let detected = Tool.allCases.filter {
                FileManager.default.fileExists(atPath: $0.skillsDir.deletingLastPathComponent().path)
            }
            HStack(spacing: 6) {
                ForEach(detected) { tool in
                    Badge(text: tool.displayName, systemImage: "checkmark", color: .tool(tool))
                }
            }

            if adoptLog.isEmpty {
                Text("Nothing is touched until you click Connect. Every changed directory is backed up first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(adoptLog.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(line.hasPrefix("✓") ? .green : .secondary)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 180)
                    .padding(8)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    .onChange(of: adoptLog.count) {
                        proxy.scrollTo("bottom")
                    }
                }
            }
            Spacer()
        }
        .padding(28)
    }

    private var done: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("You're set")
                .font(.title.bold())
            VStack(alignment: .leading, spacing: 12) {
                bullet("wand.and.stars", "The skillhub meta-skill is installed",
                       "Ask any of your models \"what skills do I have?\" — they'll query the live catalog.")
                bullet("arrow.triangle.branch", "Sync across machines",
                       "Add a GitHub remote in the Git panel (⇧⌘G), then clone + adopt on other Macs.")
                bullet("gearshape", "Settings",
                       "GitHub token for update checks, per-tool link modes, launch at login.")
            }
            .frame(maxWidth: 420, alignment: .leading)
        }
        .padding(28)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if step != .welcome && step != .done {
                Button("Back") { go(to: Step(rawValue: step.rawValue - 1) ?? .welcome) }
                    .disabled(busy)
            }
            Spacer()
            if step == .connect && !adoptDone {
                Button("Skip for now") { go(to: .done) }
                    .disabled(busy)
            }
            Button(primaryTitle) { primaryAction() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(busy || (step == .store && storeMode == .clone && !storeExists && cloneURL.isEmpty))
        }
        .padding(14)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return "Get Started"
        case .store: return storeExists ? "Use This Store" : (storeMode == .clone ? "Clone" : "Create")
        case .connect: return adoptDone ? "Continue" : "Connect Tools"
        case .done: return "Open \(Brand.displayName)"
        }
    }

    private func primaryAction() {
        switch step {
        case .welcome:
            go(to: .store)
        case .store:
            prepareStore()
        case .connect:
            if adoptDone { go(to: .done) } else { runAdopt() }
        case .done:
            onboarded = true
            appState.reload()
            appState.startServer()
            appState.checkForUpdates()
        }
    }

    private func go(to next: Step) {
        direction = next.rawValue >= step.rawValue ? 1 : -1
        withAnimation(Motion.content) { step = next }
    }

    private func bullet(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(Color.brand)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold))
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        if panel.runModal() == .OK, let url = panel.url {
            pathText = url.path.replacingOccurrences(
                of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        }
    }

    private func prepareStore() {
        let root = resolvedRoot
        let mode = storeMode
        let url = cloneURL
        let exists = storeExists
        busy = true
        errorText = nil
        Task.detached {
            let failure: String?
            do {
                let fm = FileManager.default
                if !exists {
                    if mode == .clone {
                        try fm.createDirectory(
                            at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try GitService(repoRoot: root.deletingLastPathComponent())
                            .run(["clone", url, root.lastPathComponent])
                    } else {
                        try fm.createDirectory(
                            at: root.appendingPathComponent("skills"), withIntermediateDirectories: true)
                        let git = GitService(repoRoot: root)
                        if !fm.fileExists(atPath: root.appendingPathComponent(".git").path) {
                            try git.run(["init", "-b", "main"])
                        }
                    }
                }
                failure = nil
            } catch {
                failure = error.localizedDescription
            }
            await MainActor.run {
                busy = false
                if let failure {
                    errorText = failure
                } else {
                    UserDefaults.standard.set(pathText, forKey: AppPaths.defaultsKey)
                    go(to: .connect)
                }
            }
        }
    }

    private func runAdopt() {
        busy = true
        adoptLog = ["→ Starting… (backups go to .backups/ inside the store)"]
        Task.detached {
            let engine = SyncEngine()
            let git = GitService(repoRoot: engine.repoRoot)
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            func log(_ line: String) {
                Task { @MainActor in adoptLog.append(line) }
            }
            do {
                if FileManager.default.fileExists(
                    atPath: engine.repoRoot.appendingPathComponent("claude-skills").path) {
                    log("→ Migrating legacy layout…")
                    try engine.migrateRepoLayout(git: git)
                }
                log("→ Importing skills from your tools…")
                let imported = try engine.importExternalSkills(git: git)
                log("  imported \(imported.count) skills")
                for tool in engine.conversionOrder {
                    let report = try engine.convertTool(tool, backupStamp: stamp)
                    let issues = engine.verifyTool(tool)
                    log(issues.isEmpty
                        ? "✓ \(tool.displayName): \(report.linked.count) linked"
                        : "⚠ \(tool.displayName): \(issues.count) issues")
                }
                let manifest = try engine.buildManifest(existing: (try? ManifestIO.load()) ?? .empty())
                try ManifestIO.save(manifest)
                try? git.commit(paths: ["."], message: "\(Brand.commitPrefix): onboarding adopt")
                log("✓ Done — \(manifest.skills.count) skills in your store")
                await MainActor.run { adoptDone = true; busy = false }
            } catch {
                log("✗ \(error.localizedDescription)")
                await MainActor.run { busy = false }
            }
        }
    }
}
