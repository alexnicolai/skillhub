import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showGitPanel = false
    @State private var showDriftPopover = false

    var body: some View {
        @Bindable var state = appState
        NavigationSplitView {
            // Selection highlight is high-frequency: List stays un-animated.
            List(state.filteredSkills, selection: $state.selectedSkillName) { skill in
                SkillRowView(skill: skill)
                    .tag(skill.name)
            }
            .searchable(text: $state.searchText, placement: .sidebar, prompt: "Search \(state.skills.count) skills")
            .navigationSplitViewColumnWidth(min: 300, ideal: 360)
            .navigationTitle("Skills")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                sidebarFooter
            }
            .overlay {
                if state.skills.isEmpty {
                    ContentUnavailableView(
                        "No skills found",
                        systemImage: "wand.and.stars",
                        description: Text(state.loadError ?? "Nothing in \(CatalogService.isMigrated ? "skills/" : "claude-skills/ or cursor-skills/") yet.")
                    )
                } else if state.filteredSkills.isEmpty {
                    ContentUnavailableView.search(text: state.searchText)
                }
            }
        } detail: {
            if let skill = state.selectedSkill {
                SkillDetailView(skill: skill)
            } else {
                ContentUnavailableView {
                    Label("Select a skill", systemImage: "wand.and.stars")
                } description: {
                    Text("\(state.skills.count) skills across \(activeToolCount) tools — one source of truth.")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .status) {
                statusItem
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showGitPanel = true
                } label: {
                    Label("Git Sync", systemImage: "arrow.triangle.branch")
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .help("Repo status, commit, push, pull")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.reload()
                    appState.checkForUpdates()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Reload catalog and check for upstream updates")
            }
        }
        .sheet(isPresented: $showGitPanel) {
            NavigationStack {
                GitPanelView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showGitPanel = false }
                        }
                    }
            }
            .frame(minWidth: 520, minHeight: 420)
        }
    }

    private var activeToolCount: Int {
        Tool.allCases.filter { FileManager.default.fileExists(atPath: $0.skillsDir.path) }.count
    }

    // MARK: - Status / drift

    @ViewBuilder
    private var statusItem: some View {
        if !appState.isMigrated {
            Label("Legacy layout — run Adopt to unify", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.caption)
        } else if !appState.drift.isEmpty {
            Button {
                showDriftPopover = true
            } label: {
                Label("\(appState.drift.count) drift", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.orange.opacity(0.14), in: Capsule())
            .transition(Motion.popIn(reduceMotion: reduceMotion))
            .popover(isPresented: $showDriftPopover) {
                DriftListView()
                    .frame(minWidth: 440, minHeight: 220)
            }
            .animation(Motion.small, value: appState.drift.count)
        } else if !appState.updateAvailable.isEmpty {
            Label("\(appState.updateAvailable.count) updates", systemImage: "arrow.down.circle")
                .font(.caption.weight(.medium))
                .foregroundStyle(.blue)
                .transition(Motion.popIn(reduceMotion: reduceMotion))
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.serverPort > 0 ? .green : .red)
                .frame(width: 6, height: 6)
            Text(appState.serverPort > 0
                 ? "API · 127.0.0.1:\(String(appState.serverPort))"
                 : "API offline")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(appState.skills.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
