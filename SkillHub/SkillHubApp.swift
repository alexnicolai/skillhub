import SwiftUI

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
                            appState.checkForAppUpdate()
                        }
                } else {
                    OnboardingView()
                }
            }
            .environment(appState)
            .tint(.indigo)
        }
        .windowResizability(.contentSize)

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
