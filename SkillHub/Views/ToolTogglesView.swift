import SwiftUI

/// Per-tool enable/disable pills for one skill (creates/removes symlinks).
/// Pills over checkboxes: state reads at a glance via the tool's accent color.
struct ToolTogglesView: View {
    @Environment(AppState.self) private var appState
    let skill: Skill

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Tool.allCases) { tool in
                let isOn = skill.liveTools.contains(tool)
                Button {
                    appState.setSkill(skill.name, enabled: !isOn, for: tool)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 9, weight: .semibold))
                        Text(tool.displayName)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        isOn ? Color.tool(tool).opacity(0.14) : Color.primary.opacity(0.05),
                        in: Capsule()
                    )
                    .foregroundStyle(isOn ? Color.tool(tool) : .secondary)
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .help(isOn
                      ? "Remove \(skill.name) from \(tool.displayName)"
                      : "Symlink \(skill.name) into \(tool.displayName)")
            }
        }
    }
}
