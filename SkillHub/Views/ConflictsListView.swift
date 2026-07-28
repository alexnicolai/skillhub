import SwiftUI

/// Review parked divergent copies: keep the store's version or take the parked one.
struct ConflictsListView: View {
    @Environment(AppState.self) private var appState
    @State private var diffShown: ConflictsService.Conflict?

    var body: some View {
        Group {
            if appState.conflicts.isEmpty {
                ContentUnavailableView(
                    "No conflicts", systemImage: "checkmark.seal",
                    description: Text("Divergent copies parked during adopt or drift repair show up here."))
            } else {
                List(appState.conflicts) { conflict in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(conflict.skillName)
                                .font(AppText.bodySemibold)
                            Badge(text: "from \(conflict.origin)", color: .orange)
                            Spacer()
                        }
                        Text("A different version of this skill was found in \(conflict.origin) and set aside. Compare, then pick a side.")
                            .font(AppText.secondary)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button("Compare…") { diffShown = conflict }
                            Button("Keep Store Version") {
                                appState.resolveConflict(conflict, takeTheirs: false)
                            }
                            Button("Take \(conflict.origin) Version") {
                                appState.resolveConflict(conflict, takeTheirs: true)
                            }
                            .tint(.orange)
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([conflict.folderURL])
                            } label: {
                                Image(systemName: "folder")
                            }
                            .help("Reveal the parked copy in Finder")
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("Conflicts")
        .sheet(item: $diffShown) { conflict in
            DiffSheet(
                title: "\(conflict.skillName): store vs \(conflict.origin)",
                diff: ConflictsService.diff(conflict, store: AppPaths.skillsDir),
                confirmLabel: "Take \(conflict.origin) Version"
            ) {
                appState.resolveConflict(conflict, takeTheirs: true)
            }
        }
    }
}
