import Foundation

/// Headless commands: adopt (with --dry-run), verify, drift, status.
enum CLI {
    static let commands: Set<String> = ["adopt", "verify", "drift", "status", "usage", "updates", "update", "serve", "help"]

    static func run(command: String, args: [String]) -> Int32 {
        let engine = SyncEngine()
        switch command {
        case "help":
            print("""
            \(Brand.displayName) CLI (binary: \(Brand.technicalName))
              status            catalog + per-tool summary
              adopt --dry-run   preview migration + conversion steps
              adopt             migrate repo, import external skills, convert tools
              adopt --tool=X    convert only tool X (claude|cursor|codex|opencode|gemini|kiro)
              verify            post-conversion checks for every tool
              drift             list drift between manifest intent and disk
            """)
            return 0

        case "status":
            let manifest = (try? ManifestIO.load()) ?? .empty()
            let skills = CatalogService.loadCatalog(manifest: manifest)
            print("Catalog: \(skills.count) skills (migrated: \(CatalogService.isMigrated))")
            for tool in Tool.allCases {
                let scan = engine.scanTool(tool)
                guard scan.exists else { print("  \(tool.rawValue): no directory"); continue }
                print("  \(tool.rawValue): \(scan.linkedSkills.count) linked, \(scan.realDirs.count) real dirs, \(scan.foreignLinks.count) foreign links")
            }
            return 0

        case "adopt":
            let dryRun = args.contains("--dry-run")
            let onlyTool = args.compactMap { arg -> Tool? in
                guard arg.hasPrefix("--tool=") else { return nil }
                return Tool(rawValue: String(arg.dropFirst("--tool=".count)))
            }.first
            return AdoptRunner.run(engine: engine, dryRun: dryRun, onlyTool: onlyTool)

        case "verify":
            var failed = false
            for tool in engine.conversionOrder {
                let issues = engine.verifyTool(tool)
                if issues.isEmpty {
                    print("✓ \(tool.rawValue)")
                } else {
                    failed = true
                    print("✗ \(tool.rawValue):")
                    issues.forEach { print("    \($0)") }
                }
            }
            return failed ? 1 : 0

        case "usage":
            let cache = TranscriptScanner().scan()
            let aggregated = cache.aggregated().sorted { $0.value.count > $1.value.count }
            if aggregated.isEmpty { print("No Skill invocations found in Claude transcripts."); return 0 }
            for (skill, hit) in aggregated {
                let last = hit.lastUsed.map { " (last: \($0.formatted()))" } ?? ""
                print("  \(skill): \(hit.count)\(last)")
            }
            return 0

        case "updates":
            let manifest = (try? ManifestIO.load()) ?? .empty()
            let semaphore = DispatchSemaphore(value: 0)
            var result = UpdateChecker.CheckResult()
            Task {
                result = await UpdateChecker().check(manifest: manifest, force: args.contains("--force"))
                semaphore.signal()
            }
            semaphore.wait()
            result.errors.forEach { print("⚠ \($0)") }
            if result.updatesAvailable.isEmpty {
                print("All \(manifest.skills.values.filter { $0.source.sourceType == .github }.count) GitHub-sourced skills up to date.")
            } else {
                for (name, sha) in result.updatesAvailable.sorted(by: { $0.key < $1.key }) {
                    print("  \(name): update available (upstream \(sha.prefix(10)))")
                }
            }
            return 0

        case "update":
            guard let name = args.first else { print("usage: \(Brand.technicalName) update <skill-name>"); return 64 }
            let manifest0 = (try? ManifestIO.load()) ?? .empty()
            guard var entry = manifest0.skills[name] else { print("unknown skill \(name)"); return 1 }
            let semaphore = DispatchSemaphore(value: 0)
            var sha: String?
            Task {
                let result = await UpdateChecker().check(manifest: manifest0, force: true)
                sha = result.updatesAvailable[name]
                semaphore.signal()
            }
            semaphore.wait()
            guard let sha else { print("\(name) is already up to date."); return 0 }
            do {
                var manifest = manifest0
                entry = try UpdateChecker().update(
                    skillName: name, skill: entry,
                    canonicalFolder: engine.canonicalFolder(name), newUpstreamSha: sha)
                manifest.skills[name] = entry
                try ManifestIO.save(manifest)
                try? GitService(repoRoot: engine.repoRoot).commit(
                    paths: ["skills/\(name)", "skillhub.json"],
                    message: "\(Brand.commitPrefix): update \(name) from upstream")
                print("Updated \(name) to \(sha.prefix(10)).")
                return 0
            } catch {
                print("UPDATE FAILED: \(error.localizedDescription)")
                return 1
            }

        case "serve":
            // Headless API server (e.g. on machines that only need agent access).
            let scanner = TranscriptScanner()
            let server = HTTPServer(providers: HTTPServer.Providers(
                manifest: { (try? ManifestIO.load()) ?? .empty() },
                usage: { scanner.loadCache().aggregated() },
                skillsDir: { AppPaths.skillsDir },
                recordUsage: { skill, tool in
                    var cache = scanner.loadCache()
                    let key = "external://\(tool)"
                    var perFile = cache.counts[key] ?? [:]
                    var hit = perFile[skill] ?? UsageCache.SkillHit(count: 0, lastUsed: nil)
                    hit.count += 1
                    hit.lastUsed = Date()
                    perFile[skill] = hit
                    cache.counts[key] = perFile
                    scanner.saveCache(cache)
                }
            ))
            do {
                try server.start()
                _ = try? MetaSkillInstaller.install(engine: engine, port: server.port)
                print("\(Brand.displayName) API on http://127.0.0.1:\(server.port) — Ctrl-C to stop")
                RunLoop.main.run()
                return 0
            } catch {
                print("SERVE FAILED: \(error.localizedDescription)")
                return 1
            }

        case "drift":
            let manifest = (try? ManifestIO.load()) ?? .empty()
            let drift = engine.detectDrift(manifest: manifest)
            if drift.isEmpty { print("No drift."); return 0 }
            for item in drift {
                print("\(item.tool.rawValue)/\(item.entryName): \(item.kind.rawValue) — \(item.detail)")
            }
            return 1

        default:
            return 64
        }
    }
}

/// Orchestrates the full adopt sequence; shared by CLI and the AdoptWizard UI.
enum AdoptRunner {
    static func run(engine: SyncEngine, dryRun: Bool, onlyTool: Tool? = nil) -> Int32 {
        if dryRun {
            let steps = engine.planAdopt()
            print("Adopt plan (\(steps.count) steps):")
            for step in steps { print("  [\(step.phase)] \(step.detail)") }
            return 0
        }

        let git = GitService(repoRoot: engine.repoRoot)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")

        do {
            if onlyTool == nil {
                print("→ Migrating repo layout…")
                try engine.migrateRepoLayout(git: git)

                print("→ Importing external skills…")
                let imported = try engine.importExternalSkills(git: git)
                print("  imported: \(imported.isEmpty ? "none" : imported.joined(separator: ", "))")
            }

            let tools = onlyTool.map { [$0] } ?? engine.conversionOrder
            for tool in tools {
                print("→ Converting \(tool.displayName)…")
                let report = try engine.convertTool(tool, backupStamp: stamp)
                print("  linked \(report.linked.count)"
                      + (report.conflictsParked.isEmpty ? "" : ", conflicts parked: \(report.conflictsParked.joined(separator: ", "))"))
                report.issues.forEach { print("  ⚠ \($0)") }

                let issues = engine.verifyTool(tool)
                if issues.isEmpty {
                    print("  ✓ verified")
                } else {
                    print("  ✗ verification issues:")
                    issues.forEach { print("      \($0)") }
                }
            }

            print("→ Writing manifest…")
            let manifest = try engine.buildManifest(existing: (try? ManifestIO.load()) ?? .empty())
            try ManifestIO.save(manifest)
            try? git.commit(paths: ["skillhub.json", "skills"], message: "\(Brand.commitPrefix): adopt — manifest + tool conversion")
            print("Done. \(manifest.skills.count) skills in manifest. Backup: .backups/\(stamp)/")
            return 0
        } catch {
            print("ADOPT FAILED: \(error.localizedDescription)")
            print("Backups (if any) are in \(engine.backupsDir.path)/\(stamp)/")
            return 1
        }
    }
}
