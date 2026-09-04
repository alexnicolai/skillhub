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

/// Wraps children onto new rows when the width runs out — pills and chips
/// stay readable at any window size instead of squishing.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var rowSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let positions = arrange(proposal: proposal, subviews: subviews).positions
        for (subview, position) in zip(subviews, positions) {
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return (CGSize(width: width, height: y + rowHeight), positions)
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
}

// MARK: - Tool logos

/// Monochrome brand mark for a tool, drawn from the bundled SVGs as a
/// template image so it takes whatever foreground style the context sets.
/// Logos instead of colored dots: recognizable at 12pt and no extra color.
struct ToolLogo: View {
    let tool: Tool
    var size: CGFloat = 12

    private static var cache: [Tool: NSImage] = [:]

    static func image(for tool: Tool) -> NSImage? {
        if let cached = cache[tool] { return cached }
        guard let url = ResourceBundle.url(forResource: "logo-\(tool.rawValue)", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        cache[tool] = image
        return image
    }

    var body: some View {
        if let image = ToolLogo.image(for: tool) {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .accessibilityLabel(tool.displayName)
        } else {
            Text(tool.shortName)
                .font(.system(size: size * 0.6, weight: .bold, design: .rounded))
                .frame(width: size, height: size)
                .accessibilityLabel(tool.displayName)
        }
    }
}

// MARK: - Coverage

/// One logo per active tool: solid when the skill is linked there, ghosted
/// when it's missing. The whole point of the library is "every skill in
/// every tool", so gaps should be visible from the list.
struct CoverageLogos: View {
    let tools: [Tool]
    let live: Set<Tool>
    var size: CGFloat = 12

    private var missing: [Tool] { tools.filter { !live.contains($0) } }

    var body: some View {
        HStack(spacing: 7) {
            ForEach(tools) { tool in
                ToolLogo(tool: tool, size: size)
                    .foregroundStyle(live.contains(tool) ? AnyShapeStyle(.primary) : AnyShapeStyle(.primary.opacity(0.3)))
                    .help(live.contains(tool)
                          ? "\(tool.displayName) has this skill"
                          : "Not linked into \(tool.displayName)")
            }
        }
        .accessibilityLabel(missing.isEmpty
              ? "Available in every tool"
              : "Missing from \(missing.count) tools")
    }
}

/// Banner for transient notices (success/info/error), shown at the bottom of
/// the main window. Errors stay until dismissed; others fade on their own.
struct NoticeBanner: View {
    let notice: Notice
    var onDismiss: () -> Void

    private var tint: Color {
        switch notice.kind {
        case .info: return .brand
        case .success: return .green
        case .error: return .red
        }
    }

    private var icon: String {
        switch notice.kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(notice.text)
                .font(AppText.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .frame(maxWidth: 520)
    }
}
