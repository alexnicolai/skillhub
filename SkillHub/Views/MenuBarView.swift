import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Label("\(plural(appState.skills.count, "skill")) in catalog", systemImage: "wand.and.stars")
        if appState.serverPort > 0 {
            Label("API · 127.0.0.1:\(String(appState.serverPort))", systemImage: "antenna.radiowaves.left.and.right")
        }
        if !appState.updateAvailable.isEmpty {
            Label("\(plural(appState.updateAvailable.count, "update")) available", systemImage: "arrow.down.circle")
        }
        if !appState.drift.isEmpty {
            Label(plural(appState.drift.count, "broken link"), systemImage: "exclamationmark.arrow.triangle.2.circlepath")
        }
        if !appState.gapSkills.isEmpty {
            Button {
                appState.linkEverythingEverywhere()
            } label: {
                Label("Add \(plural(appState.gapSkills.count, "skill")) to all tools", systemImage: "link")
            }
        }
        Divider()
        Button {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        } label: {
            Label("Open \(Brand.displayName)", systemImage: "macwindow")
        }
        Button {
            appState.reload()
            appState.checkForUpdates()
        } label: {
            Label("Refresh Catalog", systemImage: "arrow.clockwise")
        }
        Button {
            AppUpdater.controller.checkForUpdates(nil)
        } label: {
            Label("Check for App Updates…", systemImage: "sparkles")
        }
        Divider()
        Button("Quit \(Brand.displayName)") { NSApp.terminate(nil) }
    }
}
