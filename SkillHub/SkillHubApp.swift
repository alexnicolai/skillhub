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
                        .frame(minWidth: 860, minHeight: 520)
                        .onAppear {
                            appState.reload()
                            appState.startWatching()
                            appState.startUsageScanning()
                            appState.startServer()
                            appState.checkForUpdates()
                            _ = AppUpdater.controller   // start update checks
                        }
                } else {
                    OnboardingView()
                }
            }
            .environment(appState)
            .tint(.indigo)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton()
            }
        }

        MenuBarExtra("SkillHub", systemImage: "wand.and.stars") {
            MenuBarView()
                .environment(appState)
        }

        Settings {
            SettingsView()
                .environment(appState)
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
