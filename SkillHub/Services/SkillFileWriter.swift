import Foundation

/// All skill file writes go through here: resolve symlinks first so writes always
/// land in the canonical store, then write atomically.
enum SkillFileWriter {
    @discardableResult
    static func write(_ content: String, to fileURL: URL) throws -> URL {
        let canonical = fileURL.resolvingSymlinksInPath()
        try Data(content.utf8).write(to: canonical, options: .atomic)
        return canonical
    }
}
