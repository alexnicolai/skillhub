import SwiftUI

/// Per-tool enable/disable pills for one skill (creates/removes symlinks).
/// Monochrome: a filled pill with the tool's logo means linked, a dashed
/// outline means "click to add" — no per-tool colors competing for attention.
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
                HStack(spacing: 5) {
                    ToolLogo(tool: tool, size: 11)
                    Text(tool.displayName)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: isOn ? "checkmark" : "plus")
                        .font(.system(size: 8, weight: .bold))
                        .opacity(isOn ? 0.7 : 0.5)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(
                    isOn
                        ? Color.primary.opacity(hovering ? 0.16 : 0.1)
                        : Color.primary.opacity(hovering ? 0.05 : 0),
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(
                        isOn ? Color.clear : Color.primary.opacity(0.18),
                        style: StrokeStyle(lineWidth: 1, dash: isOn ? [] : [3, 2.5]))
                )
                .foregroundStyle(isOn ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
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
