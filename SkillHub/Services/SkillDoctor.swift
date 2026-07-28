import Foundation

/// Static health checks for a skill. Cheap enough to run on every catalog load.
enum SkillDoctor {
    struct Issue: Equatable {
        enum Severity: Equatable { case warning, error }
        let severity: Severity
        let message: String
    }

    /// Tools commonly truncate descriptions around this length.
    static let maxDescriptionLength = 1024
    /// ~7.5k tokens at 4 chars/token — a skill this big taxes every context load.
    static let maxSkillMdBytes = 30_000

    static func check(folder: URL, expectedName: String) -> [Issue] {
        var issues: [Issue] = []
        let skillMdURL = folder.appendingPathComponent("SKILL.md")
        guard let text = try? String(contentsOf: skillMdURL, encoding: .utf8) else {
            return [Issue(severity: .error, message: "SKILL.md is missing or unreadable")]
        }
        let fm = FrontmatterParser.parse(text)

        if let name = fm.name {
            if name != expectedName {
                issues.append(Issue(severity: .error,
                    message: "Frontmatter name “\(name)” ≠ folder name “\(expectedName)” — tools may not load it"))
            }
        } else {
            issues.append(Issue(severity: .error, message: "Frontmatter has no name field"))
        }

        if let description = fm.description {
            if description.count < 20 {
                issues.append(Issue(severity: .warning,
                    message: "Description is very short — models pick skills by description"))
            }
            if description.count > maxDescriptionLength {
                issues.append(Issue(severity: .warning,
                    message: "Description is \(description.count) chars — many tools truncate around \(maxDescriptionLength)"))
            }
        } else {
            issues.append(Issue(severity: .error, message: "Frontmatter has no description field"))
        }

        let bytes = text.utf8.count
        if bytes > maxSkillMdBytes {
            let tokens = bytes / 4
            issues.append(Issue(severity: .warning,
                message: "SKILL.md is ~\(tokens / 1000)k tokens — it costs this much context every load"))
        }

        issues.append(contentsOf: brokenRelativeLinks(in: text, folder: folder))
        return issues
    }

    /// Markdown links to relative paths that don't exist in the skill folder.
    static func brokenRelativeLinks(in text: String, folder: URL) -> [Issue] {
        var issues: [Issue] = []
        let body = FrontmatterParser.body(of: text)
        guard let regex = try? NSRegularExpression(pattern: #"\[[^\]]*\]\(([^)\s]+)\)"#) else { return [] }
        let range = NSRange(body.startIndex..., in: body)
        var seen = Set<String>()
        for match in regex.matches(in: body, range: range) {
            guard let r = Range(match.range(at: 1), in: body) else { continue }
            let target = String(body[r])
            if target.hasPrefix("http") || target.hasPrefix("#") || target.hasPrefix("mailto:")
                || target.hasPrefix("/") || seen.contains(target) { continue }
            seen.insert(target)
            let path = target.removingPercentEncoding ?? target
            let resolved = folder.appendingPathComponent(
                path.split(separator: "#").first.map(String.init) ?? path)
            if !FileManager.default.fileExists(atPath: resolved.path) {
                issues.append(Issue(severity: .warning, message: "Broken link: \(target)"))
            }
        }
        return issues
    }
}
