import SwiftUI

/// Per-tool enable/disable pills for one skill (creates/removes symlinks).
/// Pills over checkboxes: state reads at a glance via the tool's accent color.
struct ToolTogglesView: View {
    @Environment(AppState.self) private var appState
    let skill: Skill

    var body: some View {
        FlowLayout(spacing: 6, rowSpacing: 6) {
            ForEach(Tool.active) { tool in
                TogglePill(
                    tool: tool,
                    isOn: skill.liveTools.contains(tool),
                    skillName: skill.name
                ) { enabled in
                    appState.setSkill(skill.name, enabled: enabled, for: tool)
                }
            }
        }
    }

    private struct TogglePill: View {
        let tool: Tool
        let isOn: Bool
        let skillName: String
        let action: (Bool) -> Void
        @State private var hovering = false

        var body: some View {
            Button {
                action(!isOn)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 10, weight: .semibold))
                    Text(tool.displayName)
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(
                    isOn
                        ? Color.tool(tool).opacity(hovering ? 0.22 : 0.14)
                        : Color.primary.opacity(hovering ? 0.1 : 0.05),
                    in: Capsule()
                )
                .foregroundStyle(isOn ? Color.tool(tool) : .secondary)
                .contentShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .onHover { h in
                withAnimation(.easeOut(duration: 0.12)) { hovering = h }
            }
            .help(isOn
                  ? "Remove \(skillName) from \(tool.displayName)"
                  : "Symlink \(skillName) into \(tool.displayName)")
        }
    }
}
