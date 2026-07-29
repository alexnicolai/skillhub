import Foundation

/// Thin wrapper over the system git binary, always run in the repo root with the
/// user's environment (so osxkeychain / gh credential helpers keep working).
/// Never implements auth; surfaces stderr verbatim on failure.
struct GitService {
    struct GitError: LocalizedError {
        let command: String
        let exitCode: Int32
        let stderr: String
        var errorDescription: String? { "git \(command) failed (\(exitCode)):\n\(stderr)" }
    }

    struct StatusEntry: Identifiable, Equatable {
        let code: String   // porcelain XY code, e.g. " M", "??", "A "
        let path: String
        var id: String { path }
    }

    struct RepoStatus: Equatable {
        var branch: String
        var ahead: Int
        var behind: Int
        var entries: [StatusEntry]
        var isClean: Bool { entries.isEmpty }
    }

    let repoRoot: URL

    init(repoRoot: URL = AppPaths.repoRoot) {
        self.repoRoot = repoRoot
    }

    // MARK: - Core runner

    @discardableResult
    func run(_ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = repoRoot

        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin"
        env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        // Never let git block waiting for an interactive prompt.
        env["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = env

        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw GitError(
                command: args.joined(separator: " "),
                exitCode: process.terminationStatus,
                stderr: String(data: errData, encoding: .utf8) ?? ""
            )
        }
        return String(data: outData, encoding: .utf8) ?? ""
    }

    // MARK: - High-level operations

    func status() throws -> RepoStatus {
        let branchLine = try run(["status", "--porcelain=v1", "--branch"])
        var branch = "?"
        var ahead = 0, behind = 0
        var entries: [StatusEntry] = []

        for line in branchLine.components(separatedBy: "\n") where !line.isEmpty {
            if line.hasPrefix("## ") {
                // "## main...origin/main [ahead 1, behind 2]"
                let info = String(line.dropFirst(3))
                branch = String(info.split(separator: ".").first ?? "?")
                if let range = info.range(of: #"ahead (\d+)"#, options: .regularExpression) {
                    ahead = Int(info[range].split(separator: " ")[1]) ?? 0
                }
                if let range = info.range(of: #"behind (\d+)"#, options: .regularExpression) {
                    behind = Int(info[range].split(separator: " ")[1]) ?? 0
                }
            } else if line.count > 3 {
                let code = String(line.prefix(2))
                let path = String(line.dropFirst(3))
                entries.append(StatusEntry(code: code, path: path))
            }
        }
        return RepoStatus(branch: branch, ahead: ahead, behind: behind, entries: entries)
    }

    func fetch() throws { try run(["fetch", "origin"]) }

    func commitAll(message: String) throws {
        try run(["add", "-A"])
        try run(["commit", "-m", message])
    }

    /// Stage and commit only specific paths (used by SyncEngine migration steps).
    func commit(paths: [String], message: String) throws {
        try run(["add", "-A", "--"] + paths)
        try run(["commit", "-m", message])
    }

    func push() throws { try run(["push", "-u", "origin", "HEAD"]) }

    func pull() throws { try run(["pull", "--rebase", "origin"]) }

    func lastCommits(_ n: Int = 5) throws -> [String] {
        try run(["log", "--oneline", "-\(n)"])
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
    }

    func hasMergeConflicts() throws -> Bool {
        try !run(["diff", "--name-only", "--diff-filter=U"]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Per-path history

    struct HistoryEntry: Identifiable, Equatable {
        let sha: String
        let subject: String
        let date: Date
        var id: String { sha }
    }

    /// Recent commits touching a path (newest first).
    func history(path: String, limit: Int = 10) -> [HistoryEntry] {
        guard let out = try? run(["log", "-\(limit)", "--format=%H%x09%ct%x09%s", "--", path]) else {
            return []
        }
        return out.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 2)
            guard parts.count == 3, let epoch = TimeInterval(parts[1]) else { return nil }
            return HistoryEntry(sha: String(parts[0]), subject: String(parts[2]),
                                date: Date(timeIntervalSince1970: epoch))
        }
    }

    /// Restore a path to its content at a commit, then commit the restore.
    func restore(path: String, to sha: String) throws {
        try run(["checkout", sha, "--", path])
        try commit(paths: [path], message: "\(Brand.commitPrefix): restore \(path) to \(String(sha.prefix(8)))")
    }

    /// Unified diff between two paths outside the index. git exits 1 when the
    /// trees differ, which is success for our purposes.
    func diffNoIndex(_ a: String, _ b: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["diff", "--no-index", "--no-color", "--", a, b]
        process.currentDirectoryURL = repoRoot
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return "" }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
