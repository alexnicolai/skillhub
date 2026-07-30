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

    var body: some View {
        Form {
            Section {
                ForEach(Tool.allCases) { tool in
                    HStack {
                        Label {
                            Text(tool.displayName)
                        } icon: {
                            Circle()
                                .fill(tool.isInstalled ? Color.tool(tool) : Color.secondary.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                        Spacer()
                        if tool.isInstalled {
                            let linked = appState.skills.filter { $0.liveTools.contains(tool) }.count
                            Text("\(linked) of \(appState.skills.count) linked")
                                .font(AppText.secondary)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            if linked < appState.skills.count {
                                Button("Link All") { appState.enableAll(for: tool) }
                                    .controlSize(.small)
                                    .help("Symlink every skill in the library into \(tool.displayName)")
                            }
                        } else {
                            Text("Not detected")
                                .font(AppText.secondary)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } header: {
                Text("Detected tools")
            } footer: {
                Text("Tools appear automatically when their app or command-line binary is found. Undetected tools stay hidden throughout the app; install one and it shows up on the next launch.")
            }

            Section {
                ForEach(Tool.active) { tool in
                    Picker(tool.displayName, selection: linkModeBinding(for: tool)) {
                        Text("Symlink").tag(LinkMode.symlink)
                        Text("Copy").tag(LinkMode.copy)
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Link mode")
            } footer: {
                Text("A symlink is a shortcut: the tool's skill folder points at the store, so edits appear everywhere instantly and nothing can drift. Copy places a real duplicate that gets re-synced by checksum. Keep Symlink unless a tool can't read through them.")
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

    private func linkModeBinding(for tool: Tool) -> Binding<LinkMode> {
        Binding(
            get: { appState.manifest.linkMode(for: tool) },
            set: { mode in
                var settings = appState.manifest.toolSettings ?? [:]
                settings[tool.rawValue] = ToolSettings(linkMode: mode)
                appState.manifest.toolSettings = settings
                try? ManifestIO.save(appState.manifest)
                appState.reload()
            }
        )
    }
}

// MARK: - Shortcuts

private struct ShortcutsSettingsTab: View {
    var body: some View {
        Form {
            Section("Keyboard shortcuts") {
                shortcutRow("⌘K", "Go to skill (fuzzy search)")
                shortcutRow("⌘N", "New skill")
                shortcutRow("⇧⌘I", "Install from GitHub")
                shortcutRow("⇧⌘G", "Git sync panel")
                shortcutRow("⌘R", "Refresh catalog + check updates")
                shortcutRow("⌘S", "Save (in the skill editor)")
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
