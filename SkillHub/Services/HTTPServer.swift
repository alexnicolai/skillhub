import Foundation
import Network

/// Minimal localhost JSON API for agents. GET-only plus one POST, HTTP/1.1,
/// loopback-bound. Not a general web server — just enough for `curl`.
final class HTTPServer: @unchecked Sendable {
    static let defaultPort: UInt16 = 4477
    static let portRange: ClosedRange<UInt16> = 4477...4487

    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private let queue = DispatchQueue(label: "skillhub.http")

    /// Data providers, injected so the server has no direct AppState dependency.
    struct Providers {
        var manifest: () -> Manifest
        var usage: () -> [String: UsageCache.SkillHit]
        var skillsDir: () -> URL
        var recordUsage: (String, String) -> Void   // (skill, tool)
    }
    private let providers: Providers

    init(providers: Providers) {
        self.providers = providers
    }

    // MARK: - Lifecycle

    func start(preferredPort: UInt16 = HTTPServer.defaultPort) throws {
        var lastError: Error?
        var candidates = [preferredPort]
        candidates += HTTPServer.portRange.filter { $0 != preferredPort }
        for candidate in candidates {
            do {
                let params = NWParameters.tcp
                params.requiredInterfaceType = .loopback
                params.allowLocalEndpointReuse = true
                let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: candidate)!)
                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }
                listener.start(queue: queue)
                self.listener = listener
                self.port = candidate
                writeDiscoveryFile()
                return
            } catch {
                lastError = error
            }
        }
        throw lastError ?? NSError(domain: "SkillHub", code: 6,
                                   userInfo: [NSLocalizedDescriptionKey: "No free port in \(HTTPServer.portRange)"])
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    /// server.json lets the meta-skill discover a non-default port.
    private func writeDiscoveryFile() {
        let url = AppPaths.appSupport.appendingPathComponent("server.json")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let payload = ["port": Int(port)]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Connection handling

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(connection, buffer: Data())
    }

    private func receiveRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if error != nil { connection.cancel(); return }

            // We only accept header-only requests or small POST bodies.
            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let response = self.route(rawRequest: buffer, headerEnd: headerEnd)
                self.send(response, on: connection)
            } else if isComplete || buffer.count > 256 * 1024 {
                connection.cancel()
            } else {
                self.receiveRequest(connection, buffer: buffer)
            }
        }
    }

    private func send(_ response: Data, on connection: NWConnection) {
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Routing

    private func route(rawRequest: Data, headerEnd: Range<Data.Index>) -> Data {
        let head = String(data: rawRequest[..<headerEnd.lowerBound], encoding: .utf8) ?? ""
        let requestLine = head.components(separatedBy: "\r\n").first ?? ""
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return httpResponse(400, json: ["error": "bad request"]) }
        let method = String(parts[0])
        let fullPath = String(parts[1])
        let path = fullPath.split(separator: "?").first.map(String.init) ?? fullPath
        let segments = path.split(separator: "/").map(String.init)

        switch (method, segments.first, segments.count) {
        case ("GET", nil, _), ("GET", .some("health"), 1):
            let manifest = providers.manifest()
            return httpResponse(200, json: [
                "status": "ok",
                "version": "1.0",
                "skillCount": manifest.skills.count,
            ])

        case ("GET", .some("skills"), 1):
            return listSkills()

        case ("GET", .some("skills"), 2):
            return skillDetail(name: segments[1])

        case ("GET", .some("skills"), _) where segments.count >= 4 && segments[2] == "files":
            return skillFile(name: segments[1], relPath: segments[3...].joined(separator: "/"))

        case ("GET", .some("usage"), 1):
            let usage = providers.usage()
            let payload = usage.mapValues { hit -> [String: Any] in
                var out: [String: Any] = ["count": hit.count]
                if let last = hit.lastUsed { out["lastUsed"] = ISO8601DateFormatter().string(from: last) }
                return out
            }
            return httpResponse(200, json: payload)

        case ("POST", .some("events"), 2) where segments[1] == "skill-used":
            let body = rawRequest[headerEnd.upperBound...]
            if let parsed = try? JSONSerialization.jsonObject(with: Data(body)) as? [String: Any],
               let skill = parsed["skill"] as? String {
                providers.recordUsage(skill, parsed["tool"] as? String ?? "unknown")
                return httpResponse(204, json: nil)
            }
            return httpResponse(400, json: ["error": "expected {\"skill\": ..., \"tool\": ...}"])

        default:
            return httpResponse(404, json: ["error": "not found"])
        }
    }

    private func listSkills() -> Data {
        let manifest = providers.manifest()
        let usage = providers.usage()
        let skills = manifest.skills.sorted { $0.key < $1.key }.map { name, entry -> [String: Any] in
            var out: [String: Any] = [
                "name": name,
                "description": entry.description,
                "tools": Tool.allCases.filter { entry.isEnabled(for: $0) }.map(\.rawValue),
                "source": ["type": entry.source.sourceType.rawValue,
                           "repo": entry.source.source as Any],
                "usageCount": usage[name]?.count ?? 0,
            ]
            if let short = entry.shortDescription { out["shortDescription"] = short }
            if let updated = entry.source.updatedAt {
                out["updatedAt"] = ISO8601DateFormatter().string(from: updated)
            }
            return out
        }
        return httpResponse(200, json: ["skills": skills])
    }

    private func skillDetail(name: String) -> Data {
        guard isSafeName(name) else { return httpResponse(400, json: ["error": "bad name"]) }
        let manifest = providers.manifest()
        guard let entry = manifest.skills[name] else {
            return httpResponse(404, json: ["error": "unknown skill \(name)"])
        }
        let folder = providers.skillsDir().appendingPathComponent(name)
        let skillMd = (try? String(contentsOf: folder.appendingPathComponent("SKILL.md"), encoding: .utf8)) ?? ""
        let files = (try? HashService.fileHashes(folder).keys.sorted()) ?? []
        return httpResponse(200, json: [
            "name": name,
            "description": entry.description,
            "shortDescription": entry.shortDescription as Any,
            "tools": Tool.allCases.filter { entry.isEnabled(for: $0) }.map(\.rawValue),
            "source": [
                "type": entry.source.sourceType.rawValue,
                "repo": entry.source.source as Any,
                "url": entry.source.sourceUrl as Any,
            ],
            "files": files,
            "skillMd": skillMd,
        ])
    }

    private func skillFile(name: String, relPath: String) -> Data {
        guard isSafeName(name) else { return httpResponse(400, json: ["error": "bad name"]) }
        let folder = providers.skillsDir().appendingPathComponent(name).resolvingSymlinksInPath()
        let target = folder.appendingPathComponent(relPath).resolvingSymlinksInPath()
        // Path traversal guard: resolved target must stay inside the skill folder.
        guard target.path.hasPrefix(folder.path + "/") || target.path == folder.path,
              let data = try? Data(contentsOf: target) else {
            return httpResponse(404, json: ["error": "no such file"])
        }
        var response = Data("HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(data)
        return response
    }

    private func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.contains("..") && !name.hasPrefix(".")
    }

    private func httpResponse(_ status: Int, json: Any?) -> Data {
        let statusText: [Int: String] = [200: "OK", 204: "No Content", 400: "Bad Request", 404: "Not Found"]
        var body = Data()
        if let json, let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) {
            body = data
        }
        var response = "HTTP/1.1 \(status) \(statusText[status] ?? "")\r\n"
        response += "Content-Type: application/json\r\n"
        response += "Content-Length: \(body.count)\r\n"
        response += "Access-Control-Allow-Origin: *\r\n"
        response += "Connection: close\r\n\r\n"
        var out = Data(response.utf8)
        out.append(body)
        return out
    }
}
