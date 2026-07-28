import Foundation

/// Generates the `skillhub` meta-skill in the canonical store and enables it for
/// every tool. The meta-skill tells models to query the local API for the
/// current catalog instead of relying on stale static listings.
enum MetaSkillInstaller {
    static let skillName = "skillhub"

    @discardableResult
    static func install(engine: SyncEngine, port: UInt16) throws -> Bool {
        guard let templateURL = Bundle.module.url(forResource: "MetaSkillTemplate", withExtension: "md"),
              let template = try? String(contentsOf: templateURL, encoding: .utf8) else {
            throw NSError(domain: "SkillHub", code: 7,
                          userInfo: [NSLocalizedDescriptionKey: "MetaSkillTemplate.md missing from bundle"])
        }
        let rendered = template
            .replacingOccurrences(of: "{{PORT}}", with: String(port))
            .replacingOccurrences(of: "{{SKILLS_DIR}}", with: engine.skillsDir.path)

        let folder = engine.canonicalFolder(skillName)
        let file = folder.appendingPathComponent("SKILL.md")
        let existing = try? String(contentsOf: file, encoding: .utf8)
        guard existing != rendered else { return false }  // already current

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try rendered.write(to: file, atomically: true, encoding: .utf8)

        for tool in engine.toolDirs.keys {
            try? engine.enable(skill: skillName, for: tool)
        }
        return true
    }
}
