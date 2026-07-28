import SwiftUI

struct SkillRowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let skill: Skill

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(skill.name)
                    .font(AppText.bodySemibold)
                    .lineLimit(1)
                if skill.updateAvailable {
                    Badge(text: "Update", systemImage: "arrow.down.circle.fill", color: .brand)
                        .help("A newer version is available upstream — open the skill to update")
                        .transition(Motion.popIn(reduceMotion: reduceMotion))
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

            HStack(spacing: 4) {
                sourceBadge
                if !skill.liveTools.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(Array(skill.liveTools).sorted()) { tool in
                            Text(tool.shortName)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.tool(tool))
                                .help("\(tool.displayName) has this skill")
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.5), in: Capsule())
                }
                ForEach(skill.tags.prefix(3), id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.brand.opacity(0.85))
                        .lineLimit(1)
                }
                if skill.tags.count > 3 {
                    Text("+\(skill.tags.count - 3)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .hoverHighlight()
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
