import SwiftUI
import Sparkle

/// Sparkle self-update machinery. Lazily created so CLI subcommands never
/// start an updater; only GUI scenes touch this.
enum AppUpdater {
    static let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
}

struct SkillHubApp: App {
    @State private var appState = AppState()
    @AppStorage("onboarded") private var onboarded = false

    var body: some Scene {
        WindowGroup {
            Group {
                if onboarded {
                    DashboardView()
                        .frame(minWidth: 900, minHeight: 540)
                        .onAppear {
                            appState.reload()
                            appState.startWatching()
                            appState.startUsageScanning()
                            appState.startServer()
                            appState.checkForUpdates()
                            _ = AppUpdater.controller   // start update checks
                            // Never open onto an empty pane.
                            if appState.selectedSkillNames.isEmpty,
                               let first = appState.filteredSkills.first {
                                appState.selectedSkillNames = [first.name]
                            }
                        }
                } else {
                    OnboardingView()
                }
            }
            .environment(appState)
            .tint(Color.brand)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton()
            }
            // Real menu items (not hidden buttons) so shortcuts show up in the
            // menu bar and work regardless of which pane has focus.
            CommandGroup(replacing: .newItem) {
                Button("New Skill…") { appState.showNewSkill = true }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Import Skill Folder…") { appState.showImport = true }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Install from GitHub…") { appState.showInstall = true }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            CommandMenu("Library") {
                Button("Go to Skill…") { appState.showQuickOpen = true }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Refresh & Check for Skill Updates") {
                    appState.reload()
                    appState.checkForUpdates(force: true)
                }
                .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("Link Every Skill to Every Tool") { appState.linkEverythingEverywhere() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Git Sync…") { appState.showGitPanel = true }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Divider()
                Button("Reveal Skill Store in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppPaths.repoRoot])
                }
            }
        }

        MenuBarExtra(Brand.displayName, systemImage: "wand.and.stars") {
            MenuBarView()
                .environment(appState)
        }

        Settings {
            SettingsView()
                .environment(appState)
                .tint(Color.brand)
        }
    }
}

/// "Check for Updates…" menu item, enabled state driven by Sparkle.
struct CheckForUpdatesButton: View {
    @State private var canCheck = false

    var body: some View {
        Button("Check for Updates…") {
            AppUpdater.controller.checkForUpdates(nil)
        }
        .disabled(!canCheck)
        .onReceive(
            AppUpdater.controller.updater.publisher(for: \.canCheckForUpdates)
        ) { canCheck = $0 }
    }
}
