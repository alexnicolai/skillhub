import Foundation

/// Loads the canonical skill catalog from disk + manifest.
/// Pre-migration (no skills/ dir yet) it reads the legacy claude-skills/ and
/// cursor-skills/ folders read-only so the app is useful before Adopt runs.
struct CatalogService {

    /// True once the unified store exists.
    static var isMigrated: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: AppPaths.skillsDir.path, isDirectory: &isDir)
            && isDir.boolValue
    }

    /// All skill folders the catalog should present, deduped by name.
    /// Post-migration: skills/ only. Pre-migration: legacy dirs (claude first wins).
    static func skillFolders() -> [String: URL] {
        var out: [String: URL] = [:]
        let dirs = isMigrated ? [AppPaths.skillsDir] : AppPaths.legacyDirs
        for dir in dirs {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries {
                let name = entry.lastPathComponent
                if name.hasPrefix(".") || out[name] != nil { continue }
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDir),
                      isDir.boolValue else { continue }
                // Only folders that actually contain a SKILL.md are skills.
                let skillMd = entry.appendingPathComponent("SKILL.md")
                guard FileManager.default.fileExists(atPath: skillMd.path) else { continue }
                out[name] = entry
            }
        }
        return out
    }

    /// Hydrate the full runtime catalog.
    /// - manifest: intent + provenance (may be empty pre-migration)
    /// - toolScans: live per-tool state from SyncEngine (may be empty for read-only loads)
    /// - usage: aggregated usage hits by skill name
    static func loadCatalog(
        manifest: Manifest,
        toolScans: [Tool: ToolScanResult] = [:],
        usage: [String: UsageCache.SkillHit] = [:],
        updateAvailable: Set<String> = []
    ) -> [Skill] {
        let folders = skillFolders()
        var skills: [Skill] = []
        skills.reserveCapacity(folders.count)

        for (name, folder) in folders {
            let fm = FrontmatterParser.parse(fileURL: folder.appendingPathComponent("SKILL.md"))
            let entry = manifest.skills[name]

            var intended: Set<Tool> = []
            if let entry {
                for tool in Tool.allCases where entry.isEnabled(for: tool) { intended.insert(tool) }
            }

            var live: Set<Tool> = []
            for (tool, scan) in toolScans {
                if scan.linkedSkills.values.contains(name) || scan.realDirs.contains(name) {
                    live.insert(tool)
                }
            }

            let hit = usage[name]
            skills.append(Skill(
                name: name,
                description: fm.description ?? entry?.description ?? "",
                shortDescription: fm.shortDescription ?? entry?.shortDescription,
                folderURL: folder,
                contentHash: entry?.contentHash ?? "",
                provenance: entry?.source ?? .local,
                intendedTools: intended,
                liveTools: live,
                updateAvailable: updateAvailable.contains(name),
                usageCount: hit?.count ?? 0,
                lastUsed: hit?.lastUsed,
                tags: entry?.tags?.sorted() ?? [],
                issues: SkillDoctor.check(folder: folder, expectedName: name)
            ))
        }
        return skills.sorted { $0.name < $1.name }
    }

    /// Non-hidden files of a skill folder, relative paths sorted, for the Files tab.
    static func fileList(for skill: Skill) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: skill.folderURL.resolvingSymlinksInPath(),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var out: [String] = []
        let basePath = skill.folderURL.resolvingSymlinksInPath().path + "/"
        for case let url as URL in enumerator {
            if HashService.ignoredNames.contains(url.lastPathComponent) { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            out.append(url.path.replacingOccurrences(of: basePath, with: ""))
        }
        return out.sorted()
    }
}
