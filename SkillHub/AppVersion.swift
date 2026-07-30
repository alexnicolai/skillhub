import Foundation

/// Single source of truth for the app version.
/// make-app.sh greps this constant into Info.plist; /health reports it;
/// AppUpdateChecker compares it against the latest GitHub release tag.
enum AppVersion {
    static let current = "1.4.0"

    /// True when `other` (e.g. "v1.2.0") is newer than the running version.
    static func isNewer(_ other: String) -> Bool {
        isNewer(other, than: current)
    }

    static func isNewer(_ other: String, than base: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                .split(separator: ".")
                .map { Int($0) ?? 0 }
        }
        let a = parts(other), b = parts(base)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
