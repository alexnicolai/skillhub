import SwiftUI

/// Drift issues with one-click repair.
struct DriftListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Drift").font(.headline)
            Text("Tool folders that diverge from the store. Repair backs up each folder, imports skills that only exist elsewhere, and relinks everything.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(appState.drift) { item in
                HStack(alignment: .top, spacing: 8) {
                    ToolLogo(tool: item.tool, size: 14)
                        .foregroundStyle(.secondary)
                        .help(item.tool.displayName)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(item.entryName)
                                .font(.callout.weight(.medium))
                            Badge(text: item.kind.rawValue, color: .orange)
                        }
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollContentBackground(.hidden)

            HStack {
                Spacer()
                Button("Repair All") { appState.repairDrift() }
                    .buttonStyle(.borderedProminent)
                    .help("Backs up each tool folder, imports outside skills into the store, then relinks")
            }
        }
        .padding()
    }
}
