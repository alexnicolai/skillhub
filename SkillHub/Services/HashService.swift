import Foundation
import CryptoKit

/// Deterministic content hash of a skill folder:
/// SHA-256 over each file's repo-relative path + contents, in sorted path order.
/// Ignores .DS_Store and other filesystem noise so hashes are portable.
enum HashService {
    static let ignoredNames: Set<String> = [".DS_Store", ".git"]

    static func hashFolder(_ folder: URL) throws -> String {
        var hasher = SHA256()
        let files = try enumerateFiles(folder)
        for relPath in files.keys.sorted() {
            hasher.update(data: Data(relPath.utf8))
            hasher.update(data: Data([0]))
            let data = try Data(contentsOf: files[relPath]!)
            hasher.update(data: data)
            hasher.update(data: Data([0]))
        }
        let digest = hasher.finalize()
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    /// relative path -> absolute file URL, regular files only.
    /// Uses the path-based enumerator (yields relative paths directly) to avoid
    /// /var vs /private/var prefix mismatches from symlink standardization.
    private static func enumerateFiles(_ folder: URL) throws -> [String: URL] {
        var out: [String: URL] = [:]
        let fm = FileManager.default
        let basePath = folder.resolvingSymlinksInPath().path
        guard let enumerator = fm.enumerator(atPath: basePath) else { return out }

        while let rel = enumerator.nextObject() as? String {
            let name = (rel as NSString).lastPathComponent
            if name.hasPrefix(".") || ignoredNames.contains(name) { continue }
            // Skip anything under a hidden directory (e.g. .git/, .conflicts/).
            if rel.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { continue }
            let abs = (basePath as NSString).appendingPathComponent(rel)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: abs, isDirectory: &isDir), !isDir.boolValue else { continue }
            out[rel] = URL(fileURLWithPath: abs)
        }
        return out
    }

    /// Whether two folders have identical content.
    static func foldersIdentical(_ a: URL, _ b: URL) -> Bool {
        guard let ha = try? hashFolder(a), let hb = try? hashFolder(b) else { return false }
        return ha == hb
    }

    /// How folder `a`'s content relates to folder `b`'s.
    enum FolderRelation: Equatable {
        case identical
        /// Every file in `a` matches `b`; `b` has more files.
        case subset
        /// Every file in `b` matches `a`; `a` adds `extras` (relative paths).
        /// The Codex sidecar case: skill + agents/openai.yaml vs skill.
        case superset(extras: [String])
        case divergent
    }

    static func relate(_ a: URL, to b: URL) -> FolderRelation {
        guard let aFiles = try? fileHashes(a), let bFiles = try? fileHashes(b) else {
            return .divergent
        }
        for (path, hash) in aFiles {
            if let other = bFiles[path], other != hash { return .divergent }
        }
        let aOnly = Set(aFiles.keys).subtracting(bFiles.keys)
        let bOnly = Set(bFiles.keys).subtracting(aFiles.keys)
        switch (aOnly.isEmpty, bOnly.isEmpty) {
        case (true, true): return .identical
        case (true, false): return .subset
        case (false, true): return .superset(extras: aOnly.sorted())
        case (false, false): return .divergent
        }
    }

    /// relative path -> file content hash.
    static func fileHashes(_ folder: URL) throws -> [String: String] {
        var out: [String: String] = [:]
        for (rel, url) in try enumerateFiles(folder) {
            let digest = SHA256.hash(data: try Data(contentsOf: url))
            out[rel] = digest.map { String(format: "%02x", $0) }.joined()
        }
        return out
    }
}
