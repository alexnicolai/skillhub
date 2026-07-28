import Foundation
import Observation

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
    var selectedSkillName: String?
    var usage: [String: UsageCache.SkillHit] = [:]
    var updateAvailable: Set<String> = []

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

    var filteredSkills: [Skill] {
        guard !searchText.isEmpty else { return skills }
        let q = searchText.lowercased()
        return skills.filter {
            $0.name.lowercased().contains(q)
                || $0.description.lowercased().contains(q)
                || ($0.shortDescription?.lowercased().contains(q) ?? false)
        }
    }

    var selectedSkill: Skill? {
        selectedSkillName.flatMap { name in skills.first { $0.name == name } }
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
