import Foundation

/// Checks GitHub Releases for a newer version of SkillHub itself.
/// No auto-download — surfaces a prompt; the user gets the DMG from the
/// release page. Checked on launch and at most once per day.
struct AppUpdateChecker {
    struct Release {
        let version: String     // tag, e.g. "v1.1.0"
        let url: URL            // html release page
        let dmgURL: URL?        // direct DMG asset if present
    }

    static let releasesAPI = URL(string: "https://api.github.com/repos/alexnicolai/skillhub/releases/latest")!
    private static let lastCheckKey = "appUpdateLastCheck"

    /// Returns a newer release, or nil. `force` bypasses the daily throttle.
    func check(force: Bool = false) async -> Release? {
        let defaults = UserDefaults.standard
        if !force,
           let last = defaults.object(forKey: Self.lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < 24 * 3600 {
            return nil
        }
        defaults.set(Date(), forKey: Self.lastCheckKey)

        var request = URLRequest(url: Self.releasesAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        struct LatestRelease: Decodable {
            let tag_name: String
            let html_url: String
            let assets: [Asset]
            struct Asset: Decodable { let name: String; let browser_download_url: String }
        }
        guard let release = try? JSONDecoder().decode(LatestRelease.self, from: data),
              AppVersion.isNewer(release.tag_name),
              let url = URL(string: release.html_url) else { return nil }

        let dmg = release.assets
            .first { $0.name.hasSuffix(".dmg") }
            .flatMap { URL(string: $0.browser_download_url) }
        return Release(version: release.tag_name, url: url, dmgURL: dmg)
    }
}
