import Foundation

/// Minimal YAML frontmatter reader for SKILL.md files.
/// Handles what skills use in practice: flat `key: value` pairs, plain multiline
/// scalars (continuation lines indented deeper than the key), folded/literal
/// block scalars (`>-`, `|`), quoted strings, and one level of nested maps
/// (e.g. `metadata:`). Not a general YAML parser.
struct Frontmatter {
    var name: String?
    var description: String?
    var shortDescription: String?
    /// Every field in document order, nested keys flattened as "metadata.author".
    var fields: [(key: String, value: String)] = []
}

enum FrontmatterParser {
    static func parse(fileURL: URL) -> Frontmatter {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return Frontmatter()
        }
        return parse(text)
    }

    static func parse(_ text: String) -> Frontmatter {
        var fm = Frontmatter()
        let lines = text.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return fm }

        var i = 1
        var parentKey: String? = nil   // set while inside a nested map like `metadata:`
        var parentIndent = 0

        while i < lines.count {
            let raw = lines[i]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { break }
            if trimmed.isEmpty { i += 1; continue }

            let indent = raw.prefix(while: { $0 == " " }).count
            if let _ = parentKey, indent <= parentIndent { parentKey = nil }

            guard let colon = trimmed.firstIndex(of: ":") else { i += 1; continue }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)

            // A key with no value opens a nested map (one level deep).
            if value.isEmpty {
                parentKey = key
                parentIndent = indent
                i += 1
                continue
            }

            if value == ">-" || value == ">" || value == "|" || value == "|-" {
                // Block scalar: consume all more-indented lines.
                let fold = value.hasPrefix(">")
                var parts: [String] = []
                var j = i + 1
                while j < lines.count {
                    let next = lines[j]
                    let nextTrim = next.trimmingCharacters(in: .whitespaces)
                    if nextTrim == "---" { break }
                    let nextIndent = next.prefix(while: { $0 == " " }).count
                    if nextTrim.isEmpty { parts.append(""); j += 1; continue }
                    if nextIndent <= indent { break }
                    parts.append(nextTrim)
                    j += 1
                }
                while parts.last?.isEmpty == true { parts.removeLast() }
                value = parts.joined(separator: fold ? " " : "\n")
                i = j - 1
            } else {
                // Plain scalar: more-indented follow-up lines that aren't the
                // closing delimiter are continuations (YAML folds them with a
                // space). This is the `description: line one\n  line two` case.
                var j = i + 1
                while j < lines.count {
                    let next = lines[j]
                    let nextTrim = next.trimmingCharacters(in: .whitespaces)
                    if nextTrim == "---" || nextTrim.isEmpty { break }
                    let nextIndent = next.prefix(while: { $0 == " " }).count
                    if nextIndent <= indent { break }
                    value += " " + nextTrim
                    j += 1
                }
                i = j - 1
            }

            value = unquote(value)
            let fullKey = parentKey.map { "\($0).\(key)" } ?? key
            fm.fields.append((fullKey, value))

            switch fullKey {
            case "name": fm.name = value
            case "description": fm.description = value
            case "metadata.short-description", "metadata.shortDescription", "short-description":
                fm.shortDescription = value
            default: break
            }
            i += 1
        }
        return fm
    }

    /// The markdown after the frontmatter block (whole text if there is none).
    static func body(of text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return text }
        for (index, line) in lines.enumerated().dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                return lines[(index + 1)...]
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }

    private static func unquote(_ s: String) -> String {
        if s.count >= 2,
           (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            return String(s.dropFirst().dropLast())
        }
        return s
    }
}
