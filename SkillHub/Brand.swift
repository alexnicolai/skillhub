import Foundation

/// Public product name vs stable technical identifiers.
///
/// **Display:** "Skill Library" — Dock, menu bar, window chrome, landing page.
/// **Technical:** SkillHub / skillhub — binary, bundle id, repo slug, App Support,
/// CLI invocation. Keep those stable so Sparkle updates and muscle memory survive
/// the brand surface.
enum Brand {
    static let displayName = "Skill Library"

    /// CLI binary, `.app` basename, SPM module — do not change lightly.
    static let technicalName = "SkillHub"

    /// Prefix for auto-generated git commits in the skill store.
    static let commitPrefix = "Skill Library"
}
