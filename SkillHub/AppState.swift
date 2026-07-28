import Foundation
import Observation

/// Sidebar scopes: whole library, updates only, or one tag.
enum SidebarItem: Hashable {
    case all
    case updates
    case tag(String)
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
    var searchText: String = ""
    var selectedSkillNames: Set<String> = []
    var sidebarSelection: SidebarItem = .all
    var usage: [String: UsageCache.SkillHit] = [:]
    var updateAvailable: Set<String> = []

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

    /// Remove several skills in one pass (single git commit).
    func deleteSkills(_ names: some Collection<String>) {
        var kept: [String] = []
        do {
            try withSuppressedWatcher {
                for name in names {
                    let report = try engine.removeSkill(name)
                    manifest.skills[name] = nil
                    kept.append(contentsOf: report.divergentLeft.map { "\(name) (\($0.displayName))" })
                }
                try ManifestIO.save(manifest)
                try? GitService().commit(
                    paths: ["skills", "skillhub.json"],
                    message: "SkillHub: remove \(names.count) skills")
            }
            loadError = kept.isEmpty ? nil
                : "Kept locally-modified copies: \(kept.joined(separator: ", "))"
        } catch {
            loadError = "Remove failed: \(error.localizedDescription)"
        }
        selectedSkillNames.subtract(names)
        reload()
    }

    private func persistManifest() {
        do {
            try withSuppressedWatcher { try ManifestIO.save(manifest) }
            loadError = nil
        } catch {
            loadError = "Saving tags failed: \(error.localizedDescription)"
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

    /// Skills within the selected sidebar scope, then narrowed by search.
    var filteredSkills: [Skill] {
        var scoped: [Skill]
        switch sidebarSelection {
        case .all: scoped = skills
        case .updates: scoped = skills.filter(\.updateAvailable)
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
        drift = isMigrated ? engine.detectDrift(manifest: manifest) : []
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
            recordUsage: { [weak self] skill, tool in
                DispatchQueue.main.async { self?.recordExternalUsage(skill: skill, tool: tool) }
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

    // MARK: - Skill removal

    /// Remove a skill from the hub and from every tool using it.
    /// Divergent tool-local copies survive; the canonical version stays in git history.
    func deleteSkill(_ name: String) {
        do {
            try withSuppressedWatcher {
                let report = try engine.removeSkill(name)
                manifest.skills[name] = nil
                try ManifestIO.save(manifest)
                try? GitService().commit(
                    paths: ["skills/\(name)", "skillhub.json"],
                    message: "SkillHub: remove \(name)")
                if !report.divergentLeft.isEmpty {
                    loadError = "\(name) removed. Kept locally-modified copies in: "
                        + report.divergentLeft.map(\.displayName).joined(separator: ", ")
                } else {
                    loadError = nil
                }
            }
            selectedSkillNames.remove(name)
        } catch {
            loadError = "Remove failed: \(error.localizedDescription)"
        }
        reload()
    }

    // MARK: - Updates

    /// skill name -> latest upstream tree sha, filled by checkForUpdates.
    var pendingUpdateShas: [String: String] = [:]
    var updateErrors: [String] = []

    func checkForUpdates(force: Bool = false) {
        let manifest = self.manifest
        Task.detached(priority: .utility) {
            let result = await UpdateChecker().check(manifest: manifest, force: force)
            await MainActor.run {
                self.pendingUpdateShas = result.updatesAvailable
                self.updateAvailable = Set(result.updatesAvailable.keys)
                self.updateErrors = result.errors
                self.reload()
            }
        }
    }

    /// Apply one upstream update. Refuses if the local folder was edited since
    /// the manifest last recorded its hash, unless `overrideLocalChanges`.
    func applyUpdate(_ name: String, overrideLocalChanges: Bool = false) throws {
        guard let sha = pendingUpdateShas[name],
              let entry = manifest.skills[name] else { return }
        let folder = engine.canonicalFolder(name)
        let currentHash = (try? HashService.hashFolder(folder)) ?? ""
        if !overrideLocalChanges && currentHash != entry.contentHash {
            throw NSError(domain: "SkillHub", code: 5, userInfo: [
                NSLocalizedDescriptionKey:
                    "\(name) has local modifications — updating would overwrite them."
            ])
        }
        try withSuppressedWatcher {
            let updated = try UpdateChecker().update(
                skillName: name, skill: entry, canonicalFolder: folder, newUpstreamSha: sha)
            manifest.skills[name] = updated
            try ManifestIO.save(manifest)
            let git = GitService()
            try? git.commit(paths: ["skills/\(name)", "skillhub.json"],
                            message: "SkillHub: update \(name) from upstream")
        }
        pendingUpdateShas[name] = nil
        updateAvailable.remove(name)
        reload()
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
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        reload()
    }

    /// One-click drift repair: re-convert the affected tools (fresh backup taken).
    func repairDrift() {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let tools = Set(drift.map(\.tool))
        do {
            try withSuppressedWatcher {
                for tool in tools.sorted() {
                    _ = try engine.convertTool(tool, backupStamp: stamp)
                }
                // Recreate links the manifest wants but the dir lacks.
                for item in drift where item.kind == .missingLink {
                    try? engine.enable(skill: item.entryName, for: item.tool)
                }
            }
            loadError = nil
        } catch {
            loadError = "Repair failed: \(error.localizedDescription)"
        }
        reload()
    }
}
