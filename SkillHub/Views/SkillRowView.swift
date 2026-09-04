import SwiftUI

/// One list row: name, one-line summary, and — because the library's job is
/// putting every skill in every tool — a strip of tool logos (solid = linked). Provenance
/// only gets a badge when it says something (GitHub repo, plugin); "local" is
/// the default and stays quiet.
struct SkillRowView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let skill: Skill

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(skill.name)
                        .font(AppText.bodySemibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if skill.updateAvailable {
                        Badge(text: "Update", systemImage: "arrow.down.circle.fill", color: .brand)
                            .help("A newer version is available upstream — open the skill to update")
                            .transition(Motion.popIn(reduceMotion: reduceMotion))
                    }
                    if !skill.issues.isEmpty {
                        Image(systemName: skill.hasErrors ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(skill.hasErrors ? .red : .orange)
                            .help(skill.issues.map(\.message).joined(separator: "\n"))
                    }
                    Spacer(minLength: 4)
                    if skill.usageCount > 0 {
                        Text("\(skill.usageCount)×")
                            .font(AppText.small.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .help("Used \(skill.usageCount) times")
                    }
                }

                Text(skill.summary)
                    .font(AppText.secondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    CoverageLogos(tools: appState.activeTools, live: skill.liveTools)
                    if skill.provenance.sourceType != .local {
                        Badge(text: skill.provenance.badgeText, systemImage: badgeIcon, color: badgeColor)
                    }
                    ForEach(skill.tags.prefix(3), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Color.brand.opacity(0.85))
                            .lineLimit(1)
                    }
                    if skill.tags.count > 3 {
                        Text("+\(skill.tags.count - 3)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 1)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .animation(Motion.small, value: skill.updateAvailable)
    }

    private var badgeIcon: String {
        switch skill.provenance.sourceType {
        case .github: return "arrow.triangle.branch"
        case .local: return "internaldrive"
        case .plugin: return "puzzlepiece.extension"
        }
    }

    private var badgeColor: Color {
        switch skill.provenance.sourceType {
        case .github: return .purple
        case .local: return .gray
        case .plugin: return .teal
        }
    }
}
