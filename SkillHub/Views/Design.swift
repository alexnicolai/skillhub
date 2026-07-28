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

/// Minimal text-tab switcher: no boxes, active tab gets weight + a sliding
/// underline (matchedGeometryEffect). Cleaner than a segmented control for
/// document-style views.
struct UnderlineTabs<T: Hashable>: View {
    let tabs: [(T, String)]
    @Binding var selection: T
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 22) {
            ForEach(tabs, id: \.0) { (value, title) in
                TabItem(
                    title: title,
                    selected: value == selection,
                    namespace: ns
                ) {
                    withAnimation(reduceMotion ? nil : Motion.content) { selection = value }
                }
            }
        }
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

/// One text tab: hover previews the active color; active gets weight + underline.
private struct TabItem: View {
    let title: String
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Text(title)
                    .font(AppText.body)
                    .fontWeight(selected ? .semibold : .regular)
                    .foregroundStyle(
                        selected || hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                ZStack {
                    Color.clear.frame(height: 2)
                    if selected {
                        Capsule()
                            .fill(.tint)
                            .frame(height: 2)
                            .matchedGeometryEffect(id: "underline", in: namespace)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) { hovering = h }
        }
    }
}

/// Type scale. Base reading size is 14 — smaller sizes are for metadata only.
enum AppText {
    static let body = Font.system(size: 14)
    static let bodySemibold = Font.system(size: 14, weight: .semibold)
    static let secondary = Font.system(size: 12)
    static let small = Font.system(size: 11)
    static let mono = Font.system(size: 13, design: .monospaced)
}

/// Subtle hover affordance for rows and interactive containers.
/// ~120ms ease, background only — hover feedback should whisper, not shout.
struct HoverHighlight: ViewModifier {
    @State private var hovering = false
    var cornerRadius: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .background(
                Color.primary.opacity(hovering ? 0.06 : 0),
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
            .onHover { h in
                withAnimation(.easeOut(duration: 0.12)) { hovering = h }
            }
    }
}

/// Reveals content on hover (e.g. row action buttons) without layout shift.
struct ShowOnHover: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .opacity(hovering ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverHighlight(cornerRadius: CGFloat = 6) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius))
    }
}

/// Small capsule badge used for sources, tools, tags, and counts.
struct Badge: View {
    let text: String
    var systemImage: String?
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 11, weight: .medium))
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
    /// Brand accent — #8070FF.
    static let brand = Color(red: 0x80 / 255.0, green: 0x70 / 255.0, blue: 0xFF / 255.0)

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
