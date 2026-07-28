import SwiftUI

/// Drift issues with one-click repair.
struct DriftListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Drift").font(.headline)
            Text("Tool directories that diverge from the manifest.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(appState.drift) { item in
                HStack(alignment: .top, spacing: 8) {
                    Badge(text: item.tool.shortName, color: .tool(item.tool))
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
                    .help("Backs up divergent entries, then relinks everything to the canonical store")
            }
        }
        .padding()
    }
}
