import SwiftUI

/// Sync panel: repo status, commit+push, pull. Conflicts are surfaced, not solved.
struct GitPanelView: View {
    @Environment(AppState.self) private var appState

    @State private var status: GitService.RepoStatus?
    @State private var recentCommits: [String] = []
    @State private var commitMessage: String = ""
    @State private var busy = false
    @State private var errorText: String?

    private let git = GitService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(status?.branch ?? "…", systemImage: "arrow.triangle.branch")
                    .font(.headline)
                if let s = status {
                    if s.ahead > 0 { Text("↑\(s.ahead)").foregroundStyle(.orange) }
                    if s.behind > 0 { Text("↓\(s.behind)").foregroundStyle(.blue) }
                }
                Spacer()
                Button {
                    refresh(fetchFirst: true)
                } label: {
                    Label("Fetch", systemImage: "arrow.clockwise")
                }
                .disabled(busy)
            }

            if let s = status {
                if s.isClean {
                    Label("Working tree clean", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } else {
                    List(s.entries) { entry in
                        HStack(spacing: 8) {
                            Text(entry.code.trimmingCharacters(in: .whitespaces))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(entry.code == "??" ? Color.green : .orange)
                                .frame(width: 20, alignment: .center)
                                .padding(.vertical, 1)
                                .background(
                                    (entry.code == "??" ? Color.green : .orange).opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 4)
                                )
                            Text(entry.path)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120, maxHeight: 220)

                    HStack {
                        TextField("Commit message", text: $commitMessage)
                            .textFieldStyle(.roundedBorder)
                        Button("Commit + Push") { commitPush() }
                            .buttonStyle(.borderedProminent)
                            .disabled(busy || commitMessage.isEmpty)
                    }
                }

                if s.behind > 0 {
                    Button("Pull (rebase)") { pull() }
                        .disabled(busy)
                }
            }

            if !recentCommits.isEmpty {
                GroupBox("Recent commits") {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(recentCommits, id: \.self) { line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let errorText {
                ScrollView {
                    Text(errorText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 100)
                HStack {
                    Button("Open in Terminal") {
                        NSWorkspace.shared.open(
                            URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
                        )
                    }
                    Button("Reveal repo in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.repoRoot])
                    }
                }
                .font(.caption)
            }

            Spacer()
        }
        .padding()
        .overlay(alignment: .center) {
            if busy { ProgressView() }
        }
        .onAppear { refresh(fetchFirst: false) }
        .navigationTitle("Git Sync")
    }

    private func withGit(_ label: String, _ work: @escaping @Sendable () throws -> Void) {
        busy = true
        errorText = nil
        Task.detached {
            let failure: String?
            do { try work(); failure = nil } catch { failure = "\(label): \(error.localizedDescription)" }
            await MainActor.run {
                errorText = failure
                busy = false
                refreshLocal()
            }
        }
    }

    private func refresh(fetchFirst: Bool) {
        withGit("fetch") {
            if fetchFirst { try git.fetch() }
        }
    }

    private func refreshLocal() {
        status = try? git.status()
        recentCommits = (try? git.lastCommits()) ?? []
    }

    private func commitPush() {
        let message = commitMessage
        withGit("commit/push") {
            try git.commitAll(message: message)
            try git.push()
        }
        commitMessage = ""
    }

    private func pull() {
        withGit("pull") {
            try git.pull()
        }
    }
}
