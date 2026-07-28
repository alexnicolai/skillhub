import SwiftUI
import MarkdownUI

/// Agent-submitted skills awaiting review. Nothing here is active until approved.
struct InboxListView: View {
    @Environment(AppState.self) private var appState
    @State private var expanded: Set<String> = []

    var body: some View {
        Group {
            if appState.inbox.isEmpty {
                ContentUnavailableView(
                    "Inbox is empty", systemImage: "tray",
                    description: Text("Agents can propose skills via POST /skills on the local API — they land here for your review before becoming active."))
            } else {
                List(appState.inbox) { submission in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(submission.name)
                                .font(AppText.bodySemibold)
                            Badge(text: "from \(submission.tool)", systemImage: "sparkles", color: .brand)
                            Spacer()
                            Text(submission.submittedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(AppText.small)
                                .foregroundStyle(.tertiary)
                        }

                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expanded.contains(submission.name) },
                                set: { on in
                                    if on { expanded.insert(submission.name) } else { expanded.remove(submission.name) }
                                }
                            )
                        ) {
                            ScrollView {
                                Markdown(FrontmatterParser.body(of: content(of: submission)))
                                    .markdownTheme(.docC)
                                    .textSelection(.enabled)
                                    .padding(10)
                            }
                            .frame(maxHeight: 260)
                            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                        } label: {
                            Text(FrontmatterParser.parse(content(of: submission)).description ?? "No description")
                                .font(AppText.secondary)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        HStack(spacing: 8) {
                            Button("Approve — Add to Store") {
                                appState.approveSubmission(submission)
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Reject", role: .destructive) {
                                appState.rejectSubmission(submission)
                            }
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("Inbox")
    }

    private func content(of submission: InboxService.Submission) -> String {
        (try? String(contentsOf: submission.folderURL.appendingPathComponent("SKILL.md"),
                     encoding: .utf8)) ?? ""
    }
}
