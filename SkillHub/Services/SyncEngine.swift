import Foundation

/// The core of SkillHub: migrates the repo to the unified layout, converts tool
/// directories into symlink farms pointing at the canonical store, verifies the
/// result, and detects drift afterwards.
///
/// All paths are injected so every operation is testable against scratch fixtures.
struct SyncEngine {
    let repoRoot: URL
    let skillsDir: URL
    let backupsDir: URL
    /// Tool -> its skills directory (injectable for tests).
    let toolDirs: [Tool: URL]
    /// The vercel-labs shared store to absorb (injectable for tests).
    let agentsDir: URL
    let fm = FileManager.default

    init(
        repoRoot: URL = AppPaths.repoRoot,
        toolDirs: [Tool: URL]? = nil,
        agentsDir: URL = AppPaths.agentsSkillsDir
    ) {
        self.repoRoot = repoRoot
        self.skillsDir = repoRoot.appendingPathComponent("skills")
        self.backupsDir = repoRoot.appendingPathComponent(".backups")
        self.toolDirs = toolDirs ?? Dictionary(uniqueKeysWithValues: Tool.allCases.map { ($0, $0.skillsDir) })
        self.agentsDir = agentsDir
    }

    // MARK: - Scanning

    func scanTool(_ tool: Tool) -> ToolScanResult {
        guard let dir = toolDirs[tool] else {
            return ToolScanResult(tool: tool, exists: false, linkedSkills: [:], realDirs: [], foreignLinks: [:])
        }
        var result = ToolScanResult(tool: tool, exists: false, linkedSkills: [:], realDirs: [], foreignLinks: [:])
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { return result }
        result.exists = true

        let entries = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        let canonicalPrefix = skillsDir.resolvingSymlinksInPath().path + "/"

        for name in entries {
            if name.hasPrefix(".") || tool.protectedEntries.contains(name) { continue }
            let entryURL = dir.appendingPathComponent(name)
            let attrs = try? fm.attributesOfItem(atPath: entryURL.path)
            let type = attrs?[.type] as? FileAttributeType

            if type == .typeSymbolicLink {
                // Read the destination directly: resolvingSymlinksInPath() returns
                // the path unchanged for broken links, which would misclassify
                // orphaned canonical links as foreign.
                let destRaw = (try? fm.destinationOfSymbolicLink(atPath: entryURL.path)) ?? ""
                let destAbs = destRaw.hasPrefix("/")
                    ? destRaw
                    : dir.appendingPathComponent(destRaw).path
                let destResolved = URL(fileURLWithPath: destAbs).resolvingSymlinksInPath().path
                if destResolved.hasPrefix(canonicalPrefix) {
                    result.linkedSkills[name] = URL(fileURLWithPath: destResolved).lastPathComponent
                } else {
                    result.foreignLinks[name] = destRaw
                }
            } else if type == .typeDirectory {
                result.realDirs.append(name)
            }
        }
        return result
    }

    // MARK: - Adopt plan (dry run)

    struct AdoptStep: Identifiable {
        let id = UUID()
        let phase: String
        let detail: String
    }

    /// Human-readable preview of everything adopt would do. Read-only.
    func planAdopt() -> [AdoptStep] {
        var steps: [AdoptStep] = []
        let legacyClaude = repoRoot.appendingPathComponent("claude-skills")
        let legacyCursor = repoRoot.appendingPathComponent("cursor-skills")

        if !fm.fileExists(atPath: skillsDir.path) {
            steps.append(.init(phase: "Migrate", detail: "git mv claude-skills → skills/"))
            let cursorSkills = (try? fm.contentsOfDirectory(atPath: legacyCursor.path))?
                .filter { !$0.hasPrefix(".") } ?? []
            for name in cursorSkills.sorted() {
                let inClaude = fm.fileExists(atPath: legacyClaude.appendingPathComponent(name).path)
                if !inClaude {
                    steps.append(.init(phase: "Migrate", detail: "move cursor-skills/\(name) → skills/"))
                } else if HashService.foldersIdentical(
                    legacyClaude.appendingPathComponent(name),
                    legacyCursor.appendingPathComponent(name)
                ) {
                    steps.append(.init(phase: "Migrate", detail: "drop duplicate cursor-skills/\(name) (identical)"))
                } else {
                    steps.append(.init(phase: "Migrate", detail: "CONFLICT: park cursor-skills/\(name) in skills/.conflicts/"))
                }
            }
            steps.append(.init(phase: "Migrate", detail: "remove empty cursor-skills/"))
        }

        // Imports from ~/.agents and tool dirs.
        for (name, folder) in externalSkillFolders() {
            let target = canonicalFolder(name)
            if !fm.fileExists(atPath: target.path) {
                steps.append(.init(phase: "Import", detail: "import \(name) from \(folder.path)"))
            } else if !HashService.foldersIdentical(folder, target) {
                steps.append(.init(phase: "Import", detail: "CONFLICT: \(name) differs from \(folder.path) — park in .conflicts/"))
            }
        }

        steps.append(.init(phase: "Manifest", detail: "write skillhub.json with provenance + tool intent"))

        for tool in conversionOrder {
            let scan = scanTool(tool)
            guard scan.exists else { continue }
            let toConvert = scan.realDirs.count + scan.foreignLinks.count
            steps.append(.init(
                phase: "Convert",
                detail: "\(tool.displayName): backup dir, convert \(toConvert) entries to symlinks (\(scan.linkedSkills.count) already linked)"
            ))
        }
        return steps
    }

    /// Claude and kiro first (already symlink farms), codex last (flagged risk).
    var conversionOrder: [Tool] {
        [.claude, .kiro, .opencode, .gemini, .cursor, .codex].filter { toolDirs[$0] != nil }
    }

    // MARK: - Migration (repo layout)

    /// Step 1-3 of adopt: unify repo layout. One commit. No tool dirs touched.
    func migrateRepoLayout(git: GitService) throws {
        guard !fm.fileExists(atPath: skillsDir.path) else { return }
        let legacyCursor = repoRoot.appendingPathComponent("cursor-skills")

        try git.run(["mv", "claude-skills", "skills"])

        if fm.fileExists(atPath: legacyCursor.path) {
            let entries = (try? fm.contentsOfDirectory(atPath: legacyCursor.path))?
                .filter { !$0.hasPrefix(".") } ?? []
            for name in entries.sorted() {
                let src = "cursor-skills/\(name)"
                let dstURL = skillsDir.appendingPathComponent(name)
                if !fm.fileExists(atPath: dstURL.path) {
                    try git.run(["mv", src, "skills/\(name)"])
                } else if HashService.foldersIdentical(legacyCursor.appendingPathComponent(name), dstURL) {
                    try git.run(["rm", "-r", "-q", src])
                } else {
                    let conflictDir = skillsDir.appendingPathComponent(".conflicts")
                    try fm.createDirectory(at: conflictDir, withIntermediateDirectories: true)
                    try git.run(["mv", src, "skills/.conflicts/\(name)-cursor"])
                }
            }
            // Remove the now-empty legacy dir (git already dropped tracked files;
            // .DS_Store or empty dir may remain).
            if fm.fileExists(atPath: legacyCursor.path) {
                try? fm.removeItem(at: legacyCursor)
            }
        }
        try git.commit(paths: ["."], message: "SkillHub: migrate to unified skills/ layout")
    }

    /// Step 4-5: import ~/.agents skills + tool-dir-only skills into the store.
    /// Returns names imported. Conflicting versions are parked, never overwrite.
    @discardableResult
    func importExternalSkills(git: GitService) throws -> [String] {
        var imported: [String] = []
        var merged: [String] = []
        for (name, folder) in externalSkillFolders().sorted(by: { $0.key < $1.key }) {
            let target = canonicalFolder(name)
            if !fm.fileExists(atPath: target.path) {
                try copyFolder(folder, to: target)
                imported.append(name)
                continue
            }
            switch HashService.relate(folder, to: target) {
            case .identical, .subset:
                break // canonical already covers it
            case .superset(let extras):
                // e.g. the Codex agents/openai.yaml sidecar: absorb extras into
                // the canonical folder so every tool shares one folder.
                try mergeFiles(extras, from: folder, into: target)
                merged.append(name)
            case .divergent:
                let park = skillsDir.appendingPathComponent(".conflicts/\(name)-imported")
                try? fm.removeItem(at: park)
                try copyFolder(folder, to: park)
            }
        }
        if !imported.isEmpty || !merged.isEmpty {
            try git.commit(paths: ["skills"],
                           message: "SkillHub: import \(imported.count) external skills"
                               + (merged.isEmpty ? "" : ", merge sidecars into \(merged.count)"))
        }
        return imported
    }

    /// Copy specific relative-path files from src into dst, creating subdirs.
    private func mergeFiles(_ relPaths: [String], from src: URL, into dst: URL) throws {
        for rel in relPaths {
            let from = src.appendingPathComponent(rel)
            let to = dst.appendingPathComponent(rel)
            try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: to.path) { try fm.removeItem(at: to) }
            try fm.copyItem(at: from, to: to)
        }
    }

    /// Step 6: build/refresh the manifest from the store + live tool state.
    func buildManifest(existing: Manifest = .empty()) throws -> Manifest {
        var manifest = existing
        manifest.version = Manifest.currentVersion
        let lockProvenance = AgentsLockReader.read(
            from: agentsDir.deletingLastPathComponent().appendingPathComponent(".skill-lock.json"))
        let scans = Dictionary(uniqueKeysWithValues: toolDirs.keys.map { ($0, scanTool($0)) })

        let folders = (try? fm.contentsOfDirectory(
            at: skillsDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []

        for folder in folders {
            let name = folder.lastPathComponent
            guard fm.fileExists(atPath: folder.appendingPathComponent("SKILL.md").path) else { continue }
            let fm_ = FrontmatterParser.parse(fileURL: folder.appendingPathComponent("SKILL.md"))
            let hash = (try? HashService.hashFolder(folder)) ?? ""

            var tools: [String: Bool] = [:]
            for (tool, scan) in scans {
                // A skill counts as present via canonical link, real dir, or a
                // foreign link of the same name (pre-conversion ~/.agents links).
                let present = scan.linkedSkills.values.contains(name)
                    || scan.realDirs.contains(name)
                    || scan.foreignLinks.keys.contains(name)
                tools[tool.rawValue] = present || (existing.skills[name]?.isEnabled(for: tool) ?? false)
            }

            let provenance = existing.skills[name]?.source
                ?? lockProvenance[name]
                ?? Provenance.local

            manifest.skills[name] = ManifestSkill(
                description: fm_.description ?? existing.skills[name]?.description ?? "",
                shortDescription: fm_.shortDescription ?? existing.skills[name]?.shortDescription,
                contentHash: hash,
                source: provenance,
                tools: tools,
                tags: existing.skills[name]?.tags,   // user data — always carried forward
                addedAt: existing.skills[name]?.addedAt ?? Date()
            )
        }

        // Drop manifest entries whose folders no longer exist.
        let liveNames = Set(folders.map(\.lastPathComponent))
        manifest.skills = manifest.skills.filter { liveNames.contains($0.key) }
        return manifest
    }

    // MARK: - Tool conversion

    struct ConversionReport {
        var tool: Tool
        var linked: [String] = []
        var conflictsParked: [String] = []
        var issues: [String] = []
    }

    /// Convert one tool's dir into a symlink farm. Backup first. Idempotent.
    func convertTool(_ tool: Tool, backupStamp: String) throws -> ConversionReport {
        guard let dir = toolDirs[tool] else {
            return ConversionReport(tool: tool, issues: ["no directory configured"])
        }
        var report = ConversionReport(tool: tool)
        guard fm.fileExists(atPath: dir.path) else {
            report.issues.append("directory missing: \(dir.path)")
            return report
        }

        // 1. Backup.
        let backupDir = backupsDir.appendingPathComponent("\(backupStamp)/\(tool.rawValue)")
        try fm.createDirectory(at: backupDir.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: backupDir.path) {
            try ditto(dir, to: backupDir)
        }

        // 2. Convert entries.
        let entries = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in entries.sorted() {
            if name.hasPrefix(".") || tool.protectedEntries.contains(name) { continue }
            let entryURL = dir.appendingPathComponent(name)
            let attrs = try? fm.attributesOfItem(atPath: entryURL.path)
            let type = attrs?[.type] as? FileAttributeType
            let canonical = canonicalFolder(name)

            switch type {
            case .typeSymbolicLink:
                if fm.fileExists(atPath: canonical.path) {
                    try fm.removeItem(at: entryURL)
                    try fm.createSymbolicLink(at: entryURL, withDestinationURL: canonical)
                    report.linked.append(name)
                } else {
                    report.issues.append("\(name): symlink but no canonical skill; left untouched")
                }
            case .typeDirectory:
                guard fm.fileExists(atPath: canonical.path) else {
                    report.issues.append("\(name): not in canonical store; left untouched (import first)")
                    continue
                }
                switch HashService.relate(entryURL, to: canonical) {
                case .identical, .subset:
                    break // canonical covers this copy (subset = canonical gained sidecars)
                case .superset(let extras):
                    // Defensive: import phase normally absorbs extras already.
                    try mergeFiles(extras, from: entryURL, into: canonical)
                case .divergent:
                    // Divergent local copy: park a copy next to canonical, then link.
                    let park = skillsDir.appendingPathComponent(".conflicts/\(name)-\(tool.rawValue)")
                    try? fm.removeItem(at: park)
                    try copyFolder(entryURL, to: park)
                    report.conflictsParked.append(name)
                }
                try fm.removeItem(at: entryURL)
                try fm.createSymbolicLink(at: entryURL, withDestinationURL: canonical)
                report.linked.append(name)
            default:
                break
            }
        }
        return report
    }

    /// Post-conversion check: every entry resolves and parses through the link.
    func verifyTool(_ tool: Tool) -> [String] {
        var issues: [String] = []
        let scan = scanTool(tool)
        guard scan.exists else { return ["directory missing"] }

        for (entryName, skillName) in scan.linkedSkills {
            let skillMd = canonicalFolder(skillName).appendingPathComponent("SKILL.md")
            guard fm.isReadableFile(atPath: skillMd.path) else {
                issues.append("\(entryName): SKILL.md unreadable through link")
                continue
            }
            let parsed = FrontmatterParser.parse(fileURL: skillMd)
            if parsed.name == nil {
                issues.append("\(entryName): frontmatter has no name")
            }
        }
        for name in scan.realDirs {
            issues.append("\(name): still a real directory")
        }
        for (name, dest) in scan.foreignLinks {
            issues.append("\(name): links outside store → \(dest)")
        }
        return issues
    }

    // MARK: - Drift detection

    func detectDrift(manifest: Manifest) -> [DriftItem] {
        var drift: [DriftItem] = []
        for tool in toolDirs.keys.sorted() {
            let scan = scanTool(tool)
            guard scan.exists else { continue }
            let mode = manifest.linkMode(for: tool)

            for name in scan.realDirs {
                if mode == .copy {
                    let canonical = canonicalFolder(name)
                    if fm.fileExists(atPath: canonical.path),
                       !HashService.foldersIdentical(toolDirs[tool]!.appendingPathComponent(name), canonical) {
                        drift.append(DriftItem(tool: tool, entryName: name, kind: .staleCopy,
                                               detail: "copy differs from canonical"))
                    }
                } else {
                    drift.append(DriftItem(tool: tool, entryName: name, kind: .notSymlink,
                                           detail: "real directory where symlink expected"))
                }
            }
            for (name, dest) in scan.foreignLinks {
                drift.append(DriftItem(tool: tool, entryName: name, kind: .wrongTarget,
                                       detail: "links to \(dest)"))
            }
            for (entryName, skillName) in scan.linkedSkills
            where !fm.fileExists(atPath: canonicalFolder(skillName).path) {
                drift.append(DriftItem(tool: tool, entryName: entryName, kind: .orphanLink,
                                       detail: "canonical skill missing"))
            }
            // Manifest intent vs live.
            let liveNames = Set(scan.linkedSkills.values).union(scan.realDirs)
            for (name, entry) in manifest.skills
            where entry.isEnabled(for: tool) && !liveNames.contains(name) {
                drift.append(DriftItem(tool: tool, entryName: name, kind: .missingLink,
                                       detail: "enabled in manifest but absent"))
            }
        }
        return drift.sorted { ($0.tool.rawValue, $0.entryName) < ($1.tool.rawValue, $1.entryName) }
    }

    // MARK: - Per-skill toggles

    func enable(skill name: String, for tool: Tool) throws {
        guard let dir = toolDirs[tool] else { return }
        let canonical = canonicalFolder(name)
        guard fm.fileExists(atPath: canonical.path) else {
            throw NSError(domain: "SkillHub", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No canonical skill named \(name)"])
        }
        let entry = dir.appendingPathComponent(name)
        if fm.fileExists(atPath: entry.path) { try fm.removeItem(at: entry) }
        try fm.createSymbolicLink(at: entry, withDestinationURL: canonical)
    }

    func disable(skill name: String, for tool: Tool) throws {
        guard let dir = toolDirs[tool] else { return }
        let entry = dir.appendingPathComponent(name)
        let attrs = try? fm.attributesOfItem(atPath: entry.path)
        // Only remove links (or identical copies) — never delete unique data.
        if attrs?[.type] as? FileAttributeType == .typeSymbolicLink {
            try fm.removeItem(at: entry)
        } else if attrs != nil, HashService.foldersIdentical(entry, canonicalFolder(name)) {
            try fm.removeItem(at: entry)
        } else if attrs != nil {
            throw NSError(domain: "SkillHub", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "\(name) in \(tool.displayName) has local changes; resolve drift first"])
        }
    }

    // MARK: - Removal

    struct RemovalReport {
        var removedFrom: [Tool] = []
        /// Tools whose entry was a divergent real copy — left in place, never deleted.
        var divergentLeft: [Tool] = []
    }

    /// Remove a skill from the hub: unlink it from every tool, then delete the
    /// canonical folder. Divergent tool-local copies are preserved (they hold
    /// data the store doesn't); git history keeps the canonical content.
    @discardableResult
    func removeSkill(_ name: String) throws -> RemovalReport {
        let canonical = canonicalFolder(name)
        guard fm.fileExists(atPath: canonical.path) else {
            throw NSError(domain: "SkillHub", code: 8,
                          userInfo: [NSLocalizedDescriptionKey: "No skill named \(name) in the store"])
        }
        var report = RemovalReport()
        for tool in toolDirs.keys.sorted() {
            let entry = toolDirs[tool]!.appendingPathComponent(name)
            guard let attrs = try? fm.attributesOfItem(atPath: entry.path) else { continue }
            if attrs[.type] as? FileAttributeType == .typeSymbolicLink {
                try fm.removeItem(at: entry)
                report.removedFrom.append(tool)
            } else if HashService.foldersIdentical(entry, canonical) {
                try fm.removeItem(at: entry)
                report.removedFrom.append(tool)
            } else {
                report.divergentLeft.append(tool)
            }
        }
        try fm.removeItem(at: canonical)
        return report
    }

    // MARK: - Helpers

    func canonicalFolder(_ name: String) -> URL {
        skillsDir.appendingPathComponent(name)
    }

    /// Skills that exist outside the canonical store and should be absorbed:
    /// ~/.agents/skills plus real dirs in tool skill dirs. name -> folder URL.
    /// When several copies of a name exist, a copy that DIFFERS from canonical
    /// wins the candidate slot — identical copies need no action, but divergent
    /// ones must be surfaced (imported or parked), never shadowed.
    func externalSkillFolders() -> [String: URL] {
        var out: [String: URL] = [:]

        func consider(_ name: String, _ url: URL) {
            guard fm.fileExists(atPath: url.appendingPathComponent("SKILL.md").path) else { return }
            let canonical = canonicalFolder(name)
            if let existing = out[name] {
                // Prefer a divergent candidate over an identical-to-canonical one.
                if fm.fileExists(atPath: canonical.path),
                   HashService.foldersIdentical(existing, canonical),
                   !HashService.foldersIdentical(url, canonical) {
                    out[name] = url
                }
            } else {
                out[name] = url
            }
        }

        if let entries = try? fm.contentsOfDirectory(atPath: agentsDir.path) {
            for name in entries where !name.hasPrefix(".") {
                consider(name, agentsDir.appendingPathComponent(name))
            }
        }
        for tool in toolDirs.keys {
            for name in scanTool(tool).realDirs {
                consider(name, toolDirs[tool]!.appendingPathComponent(name))
            }
        }
        // Anything already canonical with identical content isn't "external".
        return out.filter { name, folder in
            let canonical = canonicalFolder(name)
            if !fm.fileExists(atPath: canonical.path) { return true }
            return !HashService.foldersIdentical(folder, canonical)
        }
    }

    private func copyFolder(_ src: URL, to dst: URL) throws {
        try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ditto(src, to: dst)
        // Strip filesystem noise from the store.
        let ds = dst.appendingPathComponent(".DS_Store")
        try? fm.removeItem(at: ds)
    }

    /// `ditto` preserves structure + symlinks faithfully; used for backups and imports.
    private func ditto(_ src: URL, to dst: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = [src.path, dst.path]
        let err = Pipe()
        p.standardError = err
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "SkillHub", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "ditto failed: \(msg)"])
        }
    }
}
