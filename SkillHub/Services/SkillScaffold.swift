import Foundation

/// Creates new skills in the canonical store.
enum SkillScaffold {
    /// Name rules every tool agrees on: lowercase kebab, no leading hyphen.
    static func validateName(_ name: String) -> String? {
        guard !name.isEmpty else { return "Name is required" }
        guard name.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil else {
            return "Use lowercase letters, digits, and hyphens (e.g. my-skill)"
        }
        return nil
    }

    static func validate(name: String, store: URL) -> String? {
        if let problem = validateName(name) { return problem }
        if FileManager.default.fileExists(atPath: store.appendingPathComponent(name).path) {
            return "A skill named \(name) already exists"
        }
        return nil
    }

    /// Writes the folder + SKILL.md scaffold. Returns the folder URL.
    @discardableResult
    static func create(name: String, description: String, store: URL) throws -> URL {
        if let problem = validate(name: name, store: store) {
            throw NSError(domain: "SkillHub", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: problem])
        }
        let folder = store.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let desc = description.isEmpty
            ? "Describe when a model should reach for this skill — models choose skills by this text."
            : description
        let content = """
        ---
        name: \(name)
        description: \(desc)
        ---

        # \(name)

        Explain what this skill does and how to use it. Structure that works well:

        ## When to use

        ## Steps

        ## Notes
        """
        try SkillFileWriter.write(content, to: folder.appendingPathComponent("SKILL.md"))
        return folder
    }
}
