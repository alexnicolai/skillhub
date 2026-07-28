import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("githubToken") private var githubToken: String = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    @AppStorage("onboarded") private var onboarded = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SkillHub")
                            .font(.title3.bold())
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
                    .controlSize(.small)
                }
                .padding(.vertical, 4)
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
                SecureField("Personal access token (optional)", text: $githubToken)
            } header: {
                Text("GitHub")
            } footer: {
                Text("Used only to check skills' source repositories for new versions (the \"Update\" badges). Without a token, GitHub allows 60 anonymous checks per hour — plenty for most people, but a token removes the limit. Create one at github.com → Settings → Developer settings; read-only public access is enough. It never leaves this Mac.")
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
                Text("A tiny web server, visible only to this Mac, that lets your AI assistants ask SkillHub what skills you have. The \"skillhub\" skill installed in each tool teaches models to query it — so they always see your current catalog instead of a stale list.")
            }

            Section {
                ForEach(Tool.allCases) { tool in
                    Picker(tool.displayName, selection: linkModeBinding(for: tool)) {
                        Text("Symlink").tag(LinkMode.symlink)
                        Text("Copy").tag(LinkMode.copy)
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Per-tool link mode")
            } footer: {
                Text("A symlink is a shortcut: the tool's skill folder just points at the store, so edits appear everywhere instantly and nothing can drift. Copy places a real duplicate instead, which SkillHub re-syncs by comparing checksums. Keep Symlink unless a tool proves unable to read skills through them.")
            }

            Section {
                Toggle("Launch SkillHub at login", isOn: $launchAtLogin)
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
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
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
