import Foundation

/// Agent-submitted skills waiting for human review.
/// POST /skills writes here — never directly into the store. The user approves
/// (moves into the store) or rejects (deletes) from the Inbox view.
enum InboxService {
    struct Submission: Identifiable, Equatable {
        let name: String
        let folderURL: URL
        let tool: String
        let submittedAt: Date
        var id: String { name }
    }

    static var inboxDir: URL {
        AppPaths.appSupport.appendingPathComponent("inbox")
    }

    static func list() -> [Submission] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: inboxDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.compactMap { folder in
            guard fm.fileExists(atPath: folder.appendingPathComponent("SKILL.md").path) else { return nil }
            var tool = "unknown"
            var date = Date.distantPast
            if let data = try? Data(contentsOf: folder.appendingPathComponent(".meta.json")),
               let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                tool = meta["tool"] as? String ?? tool
                if let ts = meta["submittedAt"] as? String {
                    date = ISO8601DateFormatter().date(from: ts) ?? date
                }
            }
            return Submission(name: folder.lastPathComponent, folderURL: folder,
                              tool: tool, submittedAt: date)
        }
        .sorted { $0.submittedAt > $1.submittedAt }
    }

    enum SubmitError: Error, Equatable {
        case badName, alreadyExists, ioFailure(String)
    }

    /// Called by the HTTP server. Safe against traversal; refuses collisions
    /// with the store or pending submissions.
    static func submit(name: String, skillMd: String, tool: String, store: URL) -> SubmitError? {
        guard !name.isEmpty, !name.contains("/"), !name.contains(".."), !name.hasPrefix("."),
              name.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil
        else { return .badName }
        let fm = FileManager.default
        if fm.fileExists(atPath: store.appendingPathComponent(name).path) { return .alreadyExists }
        let folder = inboxDir.appendingPathComponent(name)
        if fm.fileExists(atPath: folder.path) { return .alreadyExists }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(skillMd.utf8).write(to: folder.appendingPathComponent("SKILL.md"), options: .atomic)
            let meta: [String: Any] = [
                "tool": tool,
                "submittedAt": ISO8601DateFormatter().string(from: Date()),
            ]
            let data = try JSONSerialization.data(withJSONObject: meta)
            try data.write(to: folder.appendingPathComponent(".meta.json"), options: .atomic)
            return nil
        } catch {
            try? fm.removeItem(at: folder)
            return .ioFailure(error.localizedDescription)
        }
    }

    /// Move an approved submission into the store. Caller updates manifest + commits.
    static func approve(_ submission: Submission, store: URL) throws {
        let dest = store.appendingPathComponent(submission.name)
        guard !FileManager.default.fileExists(atPath: dest.path) else {
            throw NSError(domain: "SkillHub", code: 12,
                          userInfo: [NSLocalizedDescriptionKey: "\(submission.name) now exists in the store"])
        }
        try? FileManager.default.removeItem(
            at: submission.folderURL.appendingPathComponent(".meta.json"))
        try FileManager.default.moveItem(at: submission.folderURL, to: dest)
    }

    static func reject(_ submission: Submission) {
        try? FileManager.default.removeItem(at: submission.folderURL)
    }
}
