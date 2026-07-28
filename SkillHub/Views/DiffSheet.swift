import SwiftUI

/// Unified diff viewer: local version vs upstream, before applying an update.
struct DiffSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let diff: String
    var confirmLabel: String? = nil
    var onConfirm: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold())
            if diff.isEmpty {
                ContentUnavailableView(
                    "No differences", systemImage: "checkmark.circle",
                    description: Text("The two versions have identical content."))
                    .frame(height: 180)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated()),
                                id: \.offset) { _, line in
                            Text(String(line))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(color(for: line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(background(for: line))
                        }
                    }
                    .padding(10)
                    .textSelection(.enabled)
                }
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                if let confirmLabel, let onConfirm {
                    Button(confirmLabel) {
                        onConfirm()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 420)
    }

    private func color(for line: Substring) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .green }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .red }
        if line.hasPrefix("@@") { return Color.brand }
        if line.hasPrefix("diff ") || line.hasPrefix("index ") { return .secondary }
        return .primary
    }

    private func background(for line: Substring) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .green.opacity(0.08) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .red.opacity(0.08) }
        return .clear
    }
}
