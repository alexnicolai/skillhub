import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Label("\(appState.skills.count) skills in catalog", systemImage: "wand.and.stars")
        if let release = appState.appUpdate {
            Button {
                NSWorkspace.shared.open(release.dmgURL ?? release.url)
            } label: {
                Label("SkillHub \(release.version) available — download", systemImage: "sparkles")
            }
        }
        if appState.serverPort > 0 {
            Label("API · 127.0.0.1:\(String(appState.serverPort))", systemImage: "antenna.radiowaves.left.and.right")
        }
        if !appState.updateAvailable.isEmpty {
            Label("\(appState.updateAvailable.count) updates available", systemImage: "arrow.down.circle")
        }
        if !appState.drift.isEmpty {
            Label("\(appState.drift.count) drift issues", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
        }
        Divider()
        Button {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        } label: {
            Label("Open SkillHub", systemImage: "macwindow")
        }
        Button {
            appState.reload()
            appState.checkForUpdates()
        } label: {
            Label("Refresh Catalog", systemImage: "arrow.clockwise")
        }
        Divider()
        Button("Quit SkillHub") { NSApp.terminate(nil) }
    }
}
