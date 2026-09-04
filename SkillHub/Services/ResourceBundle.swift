import Foundation

/// Locates bundled resources whether we run as an .app, a CLI, or in tests.
/// Swift 6.3's generated Bundle.module accessor looks for the resource bundle
/// beside the executable, while make-app.sh embeds it in Contents/Resources.
enum ResourceBundle {
    static let bundle: Bundle = {
        let embedded = Bundle.main.resourceURL
            .flatMap { Bundle(url: $0.appendingPathComponent("SkillHub_SkillHub.bundle")) }
        return embedded ?? Bundle.module
    }()

    static func url(forResource name: String, withExtension ext: String) -> URL? {
        bundle.url(forResource: name, withExtension: ext)
    }
}
