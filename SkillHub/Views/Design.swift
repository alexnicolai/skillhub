import SwiftUI

/// Motion + visual tokens for SkillHub.
///
/// Grounded in animations.dev principles:
/// - ease-out for anything entering; exits shorter and simpler
/// - springs default to bounce 0 (no overshoot in serious UI)
/// - entrances start at ~scale 0.96 + opacity 0, never scale 0
/// - press feedback is felt, not seen (0.97)
/// - high-frequency interactions (list selection) get NO animation
/// - reduced motion = gentler (opacity only), not zero
enum Motion {
    /// Small state changes: badges, buttons appearing. ~200ms, no bounce.
    static let small: Animation = .spring(duration: 0.2, bounce: 0)
    /// Content swaps: tab panes. ~250ms, no bounce.
    static let content: Animation = .spring(duration: 0.25, bounce: 0)
    /// Press feedback.
    static let press: Animation = .easeOut(duration: 0.15)

    /// Entrance for badges/pills: near-full scale + fade (never from 0).
    /// Exit is a plain, faster fade — the user already moved on.
    static func popIn(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .scale(scale: 0.96).combined(with: .opacity),
                removal: .opacity
            )
    }

    /// Crossfade with a subtle directional hint for structurally-similar panes.
    /// direction: +1 = navigating right/forward, -1 = left/back.
    static func paneSwap(direction: CGFloat, reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .offset(x: 10 * direction).combined(with: .opacity),
                removal: .opacity
            )
    }
}

/// Press feedback: scale 0.97, ~150ms ease-out. Felt, not seen.
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// Small capsule badge used for sources, tools, and counts.
struct Badge: View {
    let text: String
    var systemImage: String?
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 8, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(color.opacity(0.12), in: Capsule())
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
    }
}

extension Color {
    /// Stable accent per tool so chips are scannable at a glance.
    static func tool(_ tool: Tool) -> Color {
        switch tool {
        case .claude: return .orange
        case .cursor: return .blue
        case .codex: return .green
        case .opencode: return .cyan
        case .gemini: return .indigo
        case .kiro: return .pink
        }
    }
}
