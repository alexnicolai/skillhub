import SwiftUI

struct SkillRowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let skill: Skill

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(skill.name)
                    .font(.system(.body, weight: .semibold))
                    .lineLimit(1)
                if skill.updateAvailable {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .help("Update available")
                        .transition(Motion.popIn(reduceMotion: reduceMotion))
                }
                Spacer(minLength: 4)
                if skill.usageCount > 0 {
                    Text("\(skill.usageCount)×")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .help("Used \(skill.usageCount) times")
                }
            }

            Text(skill.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 4) {
                sourceBadge
                if !skill.liveTools.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(Array(skill.liveTools).sorted()) { tool in
                            Text(tool.shortName)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.tool(tool))
                                .help("\(tool.displayName) has this skill")
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.5), in: Capsule())
                }
            }
        }
        .padding(.vertical, 3)
        .animation(Motion.small, value: skill.updateAvailable)
    }

    private var sourceBadge: some View {
        Badge(
            text: skill.provenance.badgeText,
            systemImage: badgeIcon,
            color: badgeColor
        )
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
