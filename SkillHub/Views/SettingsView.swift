import SwiftUI
import ServiceManagement

/// Tabbed settings: General (identity + store), Tools (detection, linking,
/// GitHub, API), Shortcuts. Grouped forms with room to breathe.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            ToolsSettingsTab()
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
            ShortcutsSettingsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 600, height: 560)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @Environment(AppState.self) private var appState
    @AppStorage("onboarded") private var onboarded = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Brand.displayName)
                            .font(.title2.bold())
                        Text("Version \(AppVersion.current)")
                            .font(AppText.secondary)
                            .foregroundStyle(.secondary)
                        Link("alexnicolai.github.io/skillhub",
                             destination: URL(string: "https://alexnicolai.github.io/skillhub/")!)
                            .font(AppText.small)
                    }
                    Spacer()
                    Button("Check for Updates…") {
                        AppUpdater.controller.checkForUpdates(nil)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 8)
            }

            Section {
                LabeledContent("Location") {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.repoRoot])
                    } label: {
                        Text(AppPaths.repoRoot.path)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .buttonStyle(.link)
                    .help("Reveal the store in Finder")
                }
                Button("Run Setup Again…") { onboarded = false }
                    .help("Reopens onboarding to move the store or re-connect tools")
            } header: {
                Text("Skill store")
            } footer: {
                Text("The one folder where every skill actually lives — a normal git repository. Your AI tools don't get their own copies; they all read from here. Because it's git, you can push it to GitHub and pull it on your other Macs.")
            }

            Section {
                Toggle("Launch \(Brand.displayName) at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(AppText.secondary).foregroundStyle(.red)
                }
            } header: {
                Text("Startup")
            } footer: {
                Text("Keeps the catalog API available for your agents whenever the Mac is on.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Tools

private struct ToolsSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var githubToken: String = TokenStore.get() ?? ""
    /// Bumped after an override changes so rows re-read Tool state.
    @State private var generation = 0

    var body: some View {
        Form {
            Section {
                ForEach(Tool.allCases) { tool in
                    ToolSettingRow(tool: tool, generation: generation) {
                        generation += 1
                        appState.reload()
                    }
                }
            } header: {
                Text("Tools")
            } footer: {
                Text("Detected tools are on by default. Turn one on manually if it lives somewhere unusual, or off if you don't want it linked. Every tool reads the same skill folders through symlinks.")
            }

            Section {
                SecureField("Personal access token (optional)", text: $githubToken)
                    .onChange(of: githubToken) { TokenStore.set(githubToken) }
            } header: {
                Text("GitHub")
            } footer: {
                Text("Used only to check skills' source repositories for new versions. Without a token, GitHub allows 60 anonymous checks per hour — a token removes the limit and enables private repos. Stored in your login Keychain, never in plain text.")
            }

            Section {
                if appState.serverPort > 0 {
                    LabeledContent("Address", value: "http://127.0.0.1:\(String(appState.serverPort))")
                } else {
                    Text(appState.serverError ?? "Server not running")
                        .foregroundStyle(.red)
                }
            } header: {
                Text("API server")
            } footer: {
                Text("A tiny web server, visible only to this Mac, that lets your AI assistants query your live skill catalog — and propose new skills into the review Inbox.")
            }
        }
        .formStyle(.grouped)
    }
}

/// One tool: on/off switch, what it covers, detection state, coverage.
private struct ToolSettingRow: View {
    @Environment(AppState.self) private var appState
    let tool: Tool
    let generation: Int
    var onChange: () -> Void

    private var isOn: Binding<Bool> {
        Binding(
            get: { _ = generation; return tool.isActive },
            set: { wanted in
                // Back to "follow detection" whenever the choice matches it.
                tool.override = wanted == tool.isDetected ? nil : wanted
                onChange()
            }
        )
    }

    private var detection: String {
        _ = generation
        switch (tool.isDetected, tool.override) {
        case (true, nil): return "Detected"
        case (false, nil): return "Not detected"
        case (_, .some(true)): return tool.isDetected ? "Detected · forced on" : "Not detected · forced on"
        case (_, .some(false)): return tool.isDetected ? "Detected · turned off" : "Not detected"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ToolLogo(tool: tool, size: 16)
                .foregroundStyle(tool.isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            VStack(alignment: .leading, spacing: 1) {
                Text(tool.displayName)
                Text("\(tool.subtitle) · \(detection)")
                    .font(AppText.small)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if tool.isActive {
                let linked = appState.linkedCount(for: tool)
                Text("\(linked) of \(appState.skills.count)")
                    .font(AppText.secondary)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .help("Skills currently linked into \(tool.displayName)")
                if linked < appState.skills.count {
                    Button("Link All") { appState.enableAll(for: tool) }
                        .controlSize(.small)
                        .help("Symlink every skill in the library into \(tool.displayName)")
                }
            }
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Shortcuts

private struct ShortcutsSettingsTab: View {
    var body: some View {
        Form {
            Section("Keyboard shortcuts") {
                shortcutRow("⌘K", "Go to skill (fuzzy search)")
                shortcutRow("⌘N", "New skill")
                shortcutRow("⌘O", "Import skill folder")
                shortcutRow("⇧⌘I", "Install from GitHub")
                shortcutRow("⇧⌘L", "Link every skill to every tool")
                shortcutRow("⇧⌘G", "Git sync panel")
                shortcutRow("⌘R", "Refresh catalog + check updates")
                shortcutRow("⌘S", "Save now (the editor also autosaves)")
                shortcutRow("⌘,", "Settings")
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutRow(_ keys: String, _ what: String) -> some View {
        LabeledContent {
            Text(what)
                .font(AppText.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(keys)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
        }
    }
}
