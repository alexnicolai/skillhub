import SwiftUI

/// One list row: name and a one-line summary. Everything else stays quiet
/// unless it needs you — an update badge, a health mark, or a dotted circle
/// when some tool can't see the skill. Source, tags, and per-tool detail live
/// in the detail pane.
struct SkillRowView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let skill: Skill

    private var missing: [Tool] {
        appState.activeTools.filter { !skill.liveTools.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(skill.name)
                    .font(AppText.bodySemibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
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
                MissingToolsMark(missing: missing)
            }

            Text(skill.summary)
                .font(AppText.secondary)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .animation(Motion.small, value: skill.updateAvailable)
    }
}
