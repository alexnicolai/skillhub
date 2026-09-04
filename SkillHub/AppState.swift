import Foundation
import Observation

/// Sidebar scopes: library views, smart groups, review queues, one tool, or one tag.
enum SidebarItem: Hashable {
    case all
    case updates
    case issues
    case gaps        // skills missing from at least one active tool
    case unused
    case conflicts
    case inbox
    case tool(Tool)  // skills a given tool currently has
    case tag(String)
}

/// Transient user-facing message shown as a banner in the main window.
struct Notice: Equatable, Identifiable {
    enum Kind { case info, success, error }
    let id = UUID()
    let kind: Kind
    let text: String
}

/// Thrown by applyUpdate when the local folder was edited after install.
struct LocallyModifiedError: LocalizedError {
    let name: String
    var errorDescription: String? {
        "\(name) has local modifications — updating would overwrite them."
    }
}

/// Root observable state for the app.
@Observable
@MainActor
final class AppState {
    var skills: [Skill] = []
    var manifest: Manifest = .empty()
    var drift: [DriftItem] = []
    var isMigrated: Bool = false
    var loadError: String?
    var notice: Notice?
    var searchText: String = ""
    var selectedSkillNames: Set<String> = []
    var sidebarSelection: SidebarItem = .all
    var usage: [String: UsageCache.SkillHit] = [:]
    var updateAvailable: Set<String> = []
    /// Detected (or force-enabled) tools, refreshed on every reload so views
    /// never hit the filesystem to answer "which tools exist?".
    var activeTools: [Tool] = Tool.active

    // Sheet triggers, kept here so menu commands and toolbar share them.
    var showNewSkill = false
    var showInstall = false
    var showImport = false
    var showQuickOpen = false
    var showGitPanel = false

    // MARK: - Notices

    func notify(_ kind: Notice.Kind, _ text: String) {
        notice = Notice(kind: kind, text: text)
        if kind != .error {
            let id = notice?.id
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                if notice?.id == id { notice = nil }
            }
        }
    }

    // MARK: - Tags

    /// All tags across the library with usage counts, alphabetical.
    var allTags: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for skill in skills {
            for tag in skill.tags { counts[tag, default: 0] += 1 }
        }
        return counts.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { ($0.key, $0.value) }
    }

    func addTag(_ raw: String, to skillName: String) {
        guard let tag = Tags.normalize(raw), manifest.skills[skillName] != nil else { return }
        var tags = Set(manifest.skills[skillName]?.tags ?? [])
        tags.insert(tag)
        setTags(tags.sorted(), for: skillName)
    }

    func removeTag(_ tag: String, from skillName: String) {
        guard let existing = manifest.skills[skillName]?.tags else { return }
        setTags(existing.filter { $0 != tag }, for: skillName)
    }

    /// Remove a tag from every skill (sidebar context menu).
    func deleteTagEverywhere(_ tag: String) {
        for (name, entry) in manifest.skills where entry.tags?.contains(tag) == true {
            manifest.skills[name]?.tags = entry.tags?.filter { $0 != tag }
        }
        if sidebarSelection == .tag(tag) { sidebarSelection = .all }
        persistManifest()
    }

    private func setTags(_ tags: [String], for skillName: String) {
        manifest.skills[skillName]?.tags = tags.isEmpty ? nil : tags
        persistManifest()
    }

    // MARK: - Coverage (which tools have which skills)

    /// Skills missing from at least one active tool.
    var gapSkills: [Skill] {
        let wanted = Set(activeTools)
        return skills.filter { !wanted.isSubset(of: $0.liveTools) }
    }

    func linkedCount(for tool: Tool) -> Int {
        skills.filter { $0.liveTools.contains(tool) }.count
    }

    /// Link every skill in the library into one tool (sidebar / Settings).
    func enableAll(for tool: Tool) {
        link(skills.map(\.name), to: [tool], label: "\(tool.displayName) now has every skill")
    }

    /// Link the given skills into every active tool.
    func enableEverywhere(_ names: some Collection<String>) {
        let label = names.count == 1
            ? "\(names.first ?? "") is now available in every tool"
            : "\(names.count) skills are now available in every tool"
        link(Array(names), to: activeTools, label: label)
    }

    /// One click to close every gap: every skill into every active tool.
    func linkEverythingEverywhere() {
        link(gapSkills.map(\.name), to: activeTools, label: "Every skill is now available in every tool")
    }

    private func link(_ names: [String], to tools: [Tool], label: String) {
        var linked = 0
        var failures: [String] = []
        do {
            try withSuppressedWatcher {
                for name in names {
                    guard let skill = skills.first(where: { $0.name == name }) else { continue }
                    for tool in tools where !skill.liveTools.contains(tool) {
                        do {
                            try engine.enable(skill: name, for: tool)
                            manifest.skills[name]?.tools[tool.rawValue] = true
                            linked += 1
                        } catch {
                            failures.append("\(name) → \(tool.displayName)")
                        }
                    }
                }
                try ManifestIO.save(manifest)
            }
            if !failures.isEmpty {
                notify(.error, "Couldn't link: \(failures.prefix(4).joined(separator: ", "))"
                       + (failures.count > 4 ? " and \(failures.count - 4) more" : ""))
            } else if linked > 0 {
                notify(.success, label)
            }
        } catch {
            notify(.error, "Linking failed: \(error.localizedDescription)")
        }
        reload()
    }

    // MARK: - Bulk operations

    /// Tag several skills at once (bulk pane, drag-onto-tag).
    func addTag(_ raw: String, toAll names: some Collection<String>) {
        guard let tag = Tags.normalize(raw) else { return }
        for name in names where manifest.skills[name] != nil {
            var tags = Set(manifest.skills[name]?.tags ?? [])
            tags.insert(tag)
            manifest.skills[name]?.tags = tags.sorted()
        }
        persistManifest()
    }

    /// Remove one or more skills in one pass (single git commit).
    func deleteSkills(_ names: some Collection<String>) {
        var kept: [String] = []
        let list = Array(names)
        do {
            try withSuppressedWatcher {
                for name in list {
                    let report = try engine.removeSkill(name)
                    manifest.skills[name] = nil
                    kept.append(contentsOf: report.divergentLeft.map { "\(name) (\($0.displayName))" })
                }
                try ManifestIO.save(manifest)
                try? GitService().commit(
                    paths: list.map { "skills/\($0)" } + ["skillhub.json"],
                    message: list.count == 1
                        ? "\(Brand.commitPrefix): remove \(list[0])"
                        : "\(Brand.commitPrefix): remove \(list.count) skills")
            }
            if kept.isEmpty {
                notify(.success, list.count == 1 ? "Removed \(list[0])" : "Removed \(list.count) skills")
            } else {
                notify(.info, "Removed. Kept locally-modified copies: \(kept.joined(separator: ", "))")
            }
        } catch {
            notify(.error, "Remove failed: \(error.localizedDescription)")
        }
        selectedSkillNames.subtract(names)
        reload()
    }

    func deleteSkill(_ name: String) { deleteSkills([name]) }

    private func persistManifest() {
        do {
            try withSuppressedWatcher { try ManifestIO.save(manifest) }
        } catch {
            notify(.error, "Saving skillhub.json failed: \(error.localizedDescription)")
        }
        reload()
    }

    /// Computed so a store-location change during onboarding takes effect.
    var engine: SyncEngine { SyncEngine() }
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var usageTimer: Timer?

    /// Kick off a background usage scan now and every 5 minutes.
    func startUsageScanning() {
        guard usageTimer == nil else { return }
        refreshUsage()
        usageTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshUsage() }
        }
    }

    func refreshUsage() {
        Task.detached(priority: .utility) {
            let cache = TranscriptScanner().scan()
            let aggregated = cache.aggregated()
            await MainActor.run {
                self.usage = aggregated
                self.reload()
            }
        }
    }

    /// Start watching the store + tool dirs; safe to call once after launch.
    func startWatching() {
        guard watcher == nil else { return }
        var paths = [AppPaths.skillsDir]
        paths.append(contentsOf: Tool.allCases.map(\.skillsDir))
        watcher = FileWatcher(paths: paths) { [weak self] in
            self?.reload()
        }
    }

    /// Wrap engine mutations so our own writes don't trigger watcher reloads.
    func withSuppressedWatcher<T>(_ work: () throws -> T) rethrows -> T {
        watcher?.suppress()
        return try work()
    }

    /// Long-running background writes (clones) need a longer quiet window.
    func suppressWatcher(for seconds: TimeInterval) {
        watcher?.suppress(for: seconds)
    }

    /// Skills within the selected sidebar scope, then narrowed by search.
    var filteredSkills: [Skill] {
        var scoped: [Skill]
        switch sidebarSelection {
        case .all: scoped = skills
        case .updates: scoped = skills.filter(\.updateAvailable)
        case .issues: scoped = skills.filter { !$0.issues.isEmpty }
        case .gaps: scoped = gapSkills
        case .unused: scoped = skills.filter { $0.usageCount == 0 }
        case .conflicts, .inbox: scoped = []   // these scopes show their own lists
        case .tool(let tool): scoped = skills.filter { $0.liveTools.contains(tool) }
        case .tag(let tag): scoped = skills.filter { $0.tags.contains(tag) }
        }
        guard !searchText.isEmpty else { return scoped }
        let q = searchText.lowercased()
        return scoped.filter {
            $0.name.lowercased().contains(q)
                || $0.description.lowercased().contains(q)
                || ($0.shortDescription?.lowercased().contains(q) ?? false)
                || $0.tags.contains { $0.lowercased().contains(q) }
        }
    }

    var selectedSkill: Skill? {
        guard selectedSkillNames.count == 1, let name = selectedSkillNames.first else { return nil }
        return skills.first { $0.name == name }
    }

    func reload() {
        isMigrated = CatalogService.isMigrated
        activeTools = Tool.active
        do {
            manifest = try ManifestIO.load()
            loadError = nil
        } catch {
            manifest = .empty()
            loadError = "Failed to read skillhub.json: \(error.localizedDescription)"
        }
        let scans = Dictionary(uniqueKeysWithValues: Tool.allCases.map { ($0, engine.scanTool($0)) })
        skills = CatalogService.loadCatalog(
            manifest: manifest,
            toolScans: scans,
            usage: usage,
            updateAvailable: updateAvailable
        )
        // Drift is only actionable for tools in use; the CLI still reports all.
        let active = Set(activeTools)
        drift = isMigrated
            ? engine.detectDrift(manifest: manifest).filter { active.contains($0.tool) }
            : []
        conflicts = ConflictsService.list(store: AppPaths.skillsDir)
        inbox = InboxService.list()
        // Never leave the sidebar on a scope that no longer exists.
        switch sidebarSelection {
        case .tool(let tool) where !active.contains(tool): sidebarSelection = .all
        case .tag(let tag) where !allTags.contains(where: { $0.tag == tag }): sidebarSelection = .all
        case .updates where updateAvailable.isEmpty: sidebarSelection = .all
        case .conflicts where conflicts.isEmpty: sidebarSelection = .all
        case .inbox where inbox.isEmpty: sidebarSelection = .all
        default: break
        }
    }

    // MARK: - HTTP server

    @ObservationIgnored private var server: HTTPServer?
    var serverPort: UInt16 = 0
    var serverError: String?

    func startServer() {
        guard server == nil else { return }
        let server = HTTPServer(providers: HTTPServer.Providers(
            manifest: { [weak self] in
                DispatchQueue.main.sync { self?.manifest ?? .empty() }
            },
            usage: { [weak self] in
                DispatchQueue.main.sync { self?.usage ?? [:] }
            },
            skillsDir: { AppPaths.skillsDir },
            skills: { [weak self] in
                DispatchQueue.main.sync { self?.skills ?? [] }
            },
            recordUsage: { [weak self] skill, tool in
                DispatchQueue.main.async { self?.recordExternalUsage(skill: skill, tool: tool) }
            },
            inboxChanged: { [weak self] in
                DispatchQueue.main.async {
                    self?.reload()
                    self?.notify(.info, "An agent proposed a new skill — review it in the Inbox")
                }
            }
        ))
        do {
            try server.start()
            self.server = server
            serverPort = server.port
            serverError = nil
            // Install/refresh the meta-skill with the actual port.
            try? withSuppressedWatcher {
                if try MetaSkillInstaller.install(engine: engine, port: server.port) {
                    var m = try ManifestIO.load()
                    m = try engine.buildManifest(existing: m)
                    try ManifestIO.save(m)
                }
            }
        } catch {
            serverError = "API server failed: \(error.localizedDescription)"
        }
    }

    /// Usage reported by non-Claude tools via POST /events/skill-used, persisted
    /// in the same cache under a synthetic per-tool "file" key.
    private func recordExternalUsage(skill: String, tool: String) {
        let scanner = TranscriptScanner()
        var cache = scanner.loadCache()
        let key = "external://\(tool)"
        var perFile = cache.counts[key] ?? [:]
        var hit = perFile[skill] ?? UsageCache.SkillHit(count: 0, lastUsed: nil)
        hit.count += 1
        hit.lastUsed = Date()
        perFile[skill] = hit
        cache.counts[key] = perFile
        scanner.saveCache(cache)
        usage = cache.aggregated()
        reload()
    }

    // MARK: - Review queues

    var conflicts: [ConflictsService.Conflict] = []
    var inbox: [InboxService.Submission] = []
    var issueCount: Int { skills.filter { !$0.issues.isEmpty }.count }
    var unusedCount: Int { skills.filter { $0.usageCount == 0 }.count }

    func resolveConflict(_ conflict: ConflictsService.Conflict, takeTheirs: Bool) {
        do {
            try withSuppressedWatcher {
                if takeTheirs {
                    try ConflictsService.takeTheirs(conflict, store: AppPaths.skillsDir)
                    if var entry = manifest.skills[conflict.skillName] {
                        entry.contentHash = (try? HashService.hashFolder(
                            engine.canonicalFolder(conflict.skillName))) ?? entry.contentHash
                        manifest.skills[conflict.skillName] = entry
                        try ManifestIO.save(manifest)
                    }
                    try? GitService().commit(
                        paths: ["skills"],
                        message: "\(Brand.commitPrefix): resolve conflict \(conflict.entryName) (take theirs)")
                } else {
                    try ConflictsService.keepMine(conflict)
                    try? GitService().commit(
                        paths: ["skills/.conflicts"],
                        message: "\(Brand.commitPrefix): resolve conflict \(conflict.entryName) (keep mine)")
                }
            }
            notify(.success, "Resolved \(conflict.skillName)")
        } catch {
            notify(.error, "Conflict resolution failed: \(error.localizedDescription)")
        }
        reload()
    }

    func approveSubmission(_ submission: InboxService.Submission) {
        do {
            try withSuppressedWatcher {
                try InboxService.approve(submission, store: AppPaths.skillsDir)
                let folder = engine.canonicalFolder(submission.name)
                let fm = FrontmatterParser.parse(fileURL: folder.appendingPathComponent("SKILL.md"))
                manifest.skills[submission.name] = ManifestSkill(
                    description: fm.description ?? "",
                    shortDescription: fm.shortDescription,
                    contentHash: (try? HashService.hashFolder(folder)) ?? "",
                    source: Provenance(sourceType: .local, source: "agent:\(submission.tool)",
                                       installedAt: Date()),
                    tools: [:],
                    addedAt: Date()
                )
                for tool in activeTools {
                    try? engine.enable(skill: submission.name, for: tool)
                    manifest.skills[submission.name]?.tools[tool.rawValue] = true
                }
                try ManifestIO.save(manifest)
                try? GitService().commit(
                    paths: ["skills/\(submission.name)", "skillhub.json"],
                    message: "\(Brand.commitPrefix): approve agent-submitted skill \(submission.name)")
            }
            notify(.success, "Approved \(submission.name) — now available in every tool")
        } catch {
            notify(.error, "Approve failed: \(error.localizedDescription)")
        }
        reload()
    }

    func rejectSubmission(_ submission: InboxService.Submission) {
        InboxService.reject(submission)
        reload()
    }

    // MARK: - Create / install / import / restore

    func createSkill(name: String, description: String, tags: [String], tools: Set<Tool>) throws {
        try withSuppressedWatcher {
            let folder = try SkillScaffold.create(
                name: name, description: description, store: AppPaths.skillsDir)
            manifest.skills[name] = ManifestSkill(
                description: description,
                shortDescription: nil,
                contentHash: (try? HashService.hashFolder(folder)) ?? "",
                source: Provenance(sourceType: .local, installedAt: Date()),
                tools: Dictionary(uniqueKeysWithValues: tools.map { ($0.rawValue, true) }),
                tags: tags.isEmpty ? nil : tags.sorted(),
                addedAt: Date()
            )
            for tool in tools { try? engine.enable(skill: name, for: tool) }
            try ManifestIO.save(manifest)
            try? GitService().commit(
                paths: ["skills/\(name)", "skillhub.json"],
                message: "\(Brand.commitPrefix): create \(name)")
        }
        reload()
        sidebarSelection = .all
        selectedSkillNames = [name]
    }

    /// Clone happens off the main thread; manifest bookkeeping happens here.
    func installRemoteSkills(repo: String, skills selection: [RepoBrowser.RemoteSkill]) async throws -> RepoBrowser.InstallResult {
        suppressWatcher(for: 120)
        let store = AppPaths.skillsDir
        let result = try await Task.detached(priority: .userInitiated) {
            try RepoBrowser().install(repo: repo, skills: selection, into: store)
        }.value
        try withSuppressedWatcher {
            for skill in selection where result.installed.contains(skill.name) {
                let folder = engine.canonicalFolder(skill.name)
                let fm = FrontmatterParser.parse(fileURL: folder.appendingPathComponent("SKILL.md"))
                manifest.skills[skill.name] = ManifestSkill(
                    description: fm.description ?? skill.description,
                    shortDescription: fm.shortDescription,
                    contentHash: (try? HashService.hashFolder(folder)) ?? "",
                    source: RepoBrowser.provenance(repo: repo, skill: skill),
                    tools: [:],
                    addedAt: Date()
                )
                for tool in activeTools {
                    try? engine.enable(skill: skill.name, for: tool)
                    manifest.skills[skill.name]?.tools[tool.rawValue] = true
                }
            }
            if !result.installed.isEmpty {
                try ManifestIO.save(manifest)
                try? GitService().commit(
                    paths: result.installed.map { "skills/\($0)" } + ["skillhub.json"],
                    message: "\(Brand.commitPrefix): install \(result.installed.count) skills from \(repo)")
            }
        }
        reload()
        if !result.installed.isEmpty {
            notify(.success, result.installed.count == 1
                ? "Installed \(result.installed[0]) into every tool"
                : "Installed \(result.installed.count) skills into every tool")
        }
        return result
    }

    struct ImportResult {
        var imported: [String] = []
        var replaced: [String] = []
        var skipped: [(name: String, reason: String)] = []
    }

    /// Bring local skill folders (or SKILL.md files) into the store. Each
    /// becomes a canonical skill linked into every active tool. Existing
    /// names are replaced only when `replaceExisting` — the old version stays
    /// in git history either way.
    func importLocalSkills(_ urls: [URL], replaceExisting: Bool) -> ImportResult {
        var result = ImportResult()
        let fm = FileManager.default
        let store = AppPaths.skillsDir.resolvingSymlinksInPath()
        do {
            try withSuppressedWatcher {
                for raw in urls {
                    var source = raw.resolvingSymlinksInPath()
                    if source.lastPathComponent == "SKILL.md" { source = source.deletingLastPathComponent() }
                    guard fm.fileExists(atPath: source.appendingPathComponent("SKILL.md").path) else {
                        result.skipped.append((raw.lastPathComponent, "no SKILL.md inside"))
                        continue
                    }
                    if source.path.hasPrefix(store.path + "/") {
                        result.skipped.append((source.lastPathComponent, "already in the store"))
                        continue
                    }
                    let fmData = FrontmatterParser.parse(fileURL: source.appendingPathComponent("SKILL.md"))
                    let name = source.lastPathComponent
                    if let problem = SkillScaffold.validateName(name) {
                        result.skipped.append((name, problem))
                        continue
                    }
                    let dest = engine.canonicalFolder(name)
                    let exists = fm.fileExists(atPath: dest.path)
                    if exists && !replaceExisting {
                        result.skipped.append((name, "already exists"))
                        continue
                    }
                    if exists { try fm.removeItem(at: dest) }
                    try fm.copyItem(at: source, to: dest)
                    try? fm.removeItem(at: dest.appendingPathComponent(".DS_Store"))
                    let previous = manifest.skills[name]
                    manifest.skills[name] = ManifestSkill(
                        description: fmData.description ?? previous?.description ?? "",
                        shortDescription: fmData.shortDescription,
                        contentHash: (try? HashService.hashFolder(dest)) ?? "",
                        source: previous?.source ?? Provenance(
                            sourceType: .local, source: "import:\(raw.path)", installedAt: Date()),
                        tools: previous?.tools ?? [:],
                        tags: previous?.tags,
                        addedAt: previous?.addedAt ?? Date()
                    )
                    for tool in activeTools {
                        try? engine.enable(skill: name, for: tool)
                        manifest.skills[name]?.tools[tool.rawValue] = true
                    }
                    if exists { result.replaced.append(name) } else { result.imported.append(name) }
                }
                let touched = result.imported + result.replaced
                if !touched.isEmpty {
                    try ManifestIO.save(manifest)
                    try? GitService().commit(
                        paths: touched.map { "skills/\($0)" } + ["skillhub.json"],
                        message: "\(Brand.commitPrefix): import \(touched.count) skills from local folders")
                }
            }
        } catch {
            notify(.error, "Import failed: \(error.localizedDescription)")
        }
        reload()
        let touched = result.imported + result.replaced
        if let last = touched.last {
            sidebarSelection = .all
            selectedSkillNames = [last]
            notify(.success, touched.count == 1
                ? "Imported \(last) into every tool"
                : "Imported \(touched.count) skills into every tool")
        }
        return result
    }

    /// The raw editor saved a SKILL.md: keep the watcher quiet and refresh the
    /// catalog so descriptions, doctor findings, and the API stay current.
    func skillFileWasEdited(_ name: String) {
        watcher?.suppress()
        reload()
    }

    func restoreSkill(_ name: String, to sha: String) {
        do {
            try withSuppressedWatcher {
                try GitService().restore(path: "skills/\(name)", to: sha)
                if var entry = manifest.skills[name] {
                    entry.contentHash = (try? HashService.hashFolder(engine.canonicalFolder(name))) ?? entry.contentHash
                    manifest.skills[name] = entry
                    try ManifestIO.save(manifest)
                }
            }
            notify(.success, "Restored \(name) to \(String(sha.prefix(7)))")
        } catch {
            notify(.error, "Restore failed: \(error.localizedDescription)")
        }
        reload()
    }

    // MARK: - Updates

    /// skill name -> latest upstream tree sha, filled by checkForUpdates.
    var pendingUpdateShas: [String: String] = [:]
    var updateErrors: [String] = []
    var checkingUpdates = false

    func checkForUpdates(force: Bool = false) {
        let manifest = self.manifest
        checkingUpdates = true
        Task.detached(priority: .utility) {
            let result = await UpdateChecker().check(manifest: manifest, force: force)
            await MainActor.run {
                self.pendingUpdateShas = result.updatesAvailable
                self.updateAvailable = Set(result.updatesAvailable.keys)
                self.updateErrors = result.errors
                self.checkingUpdates = false
                self.reload()
            }
        }
    }

    /// Apply one upstream update. Refuses if the local folder was edited since
    /// the manifest last recorded its hash, unless `overrideLocalChanges`.
    /// The sparse clone runs off the main thread.
    func applyUpdate(_ name: String, overrideLocalChanges: Bool = false) async throws {
        guard let sha = pendingUpdateShas[name],
              let entry = manifest.skills[name] else { return }
        let folder = engine.canonicalFolder(name)
        let currentHash = (try? HashService.hashFolder(folder)) ?? ""
        if !overrideLocalChanges && currentHash != entry.contentHash {
            throw LocallyModifiedError(name: name)
        }
        suppressWatcher(for: 120)
        let updated = try await Task.detached(priority: .userInitiated) {
            try UpdateChecker().update(
                skillName: name, skill: entry, canonicalFolder: folder, newUpstreamSha: sha)
        }.value
        try withSuppressedWatcher {
            manifest.skills[name] = updated
            try ManifestIO.save(manifest)
            try? GitService().commit(paths: ["skills/\(name)", "skillhub.json"],
                                     message: "\(Brand.commitPrefix): update \(name) from upstream")
        }
        pendingUpdateShas[name] = nil
        updateAvailable.remove(name)
        reload()
        notify(.success, "Updated \(name) from \(entry.source.source ?? "upstream")")
    }

    // MARK: - Per-tool toggles

    func setSkill(_ name: String, enabled: Bool, for tool: Tool) {
        do {
            try withSuppressedWatcher {
                if enabled {
                    try engine.enable(skill: name, for: tool)
                } else {
                    try engine.disable(skill: name, for: tool)
                }
                manifest.skills[name]?.tools[tool.rawValue] = enabled
                try ManifestIO.save(manifest)
            }
        } catch {
            notify(.error, error.localizedDescription)
        }
        reload()
    }

    /// One-click drift repair: absorb skills that only exist outside the store
    /// (real dirs, links into other stores), then re-convert the affected
    /// tools with a fresh backup and recreate any links the manifest wants.
    func repairDrift() {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let tools = Set(drift.map(\.tool))
        var imported: [String] = []
        var leftover: [String] = []
        do {
            try withSuppressedWatcher {
                let git = GitService()
                imported = try engine.importExternalSkills(git: git)
                for tool in tools.sorted() {
                    let report = try engine.convertTool(tool, backupStamp: stamp)
                    leftover.append(contentsOf: report.issues)
                }
                for item in drift where item.kind == .missingLink {
                    try? engine.enable(skill: item.entryName, for: item.tool)
                }
                let refreshed = try engine.buildManifest(existing: (try? ManifestIO.load()) ?? manifest)
                try ManifestIO.save(refreshed)
                try? git.commit(paths: ["skills", "skillhub.json"],
                                message: "\(Brand.commitPrefix): repair drift"
                                    + (imported.isEmpty ? "" : ", import \(imported.count) skills"))
            }
            if leftover.isEmpty {
                notify(.success, imported.isEmpty
                    ? "Drift repaired"
                    : "Drift repaired — imported \(imported.count) skills into the store")
            } else {
                notify(.info, "Repaired what was possible. Left alone: "
                       + leftover.prefix(3).joined(separator: "; ")
                       + (leftover.count > 3 ? " (+\(leftover.count - 3) more)" : ""))
            }
        } catch {
            notify(.error, "Repair failed: \(error.localizedDescription)")
        }
        reload()
    }
}
