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
            Section("Skill store") {
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
            }

            Section("GitHub") {
                SecureField("Personal access token (optional)", text: $githubToken)
                Text("Raises the unauthenticated rate limit for update checks. Read-only public access is enough.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("API server") {
                if appState.serverPort > 0 {
                    LabeledContent("Address", value: "http://127.0.0.1:\(String(appState.serverPort))")
                } else {
                    Text(appState.serverError ?? "Server not running")
                        .foregroundStyle(.red)
                }
            }

            Section("Per-tool link mode") {
                Text("Symlink is the default. Switch a tool to Copy only if it fails to read skills through symlinks (SkillHub then hash-syncs real copies).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Tool.allCases) { tool in
                    Picker(tool.displayName, selection: linkModeBinding(for: tool)) {
                        Text("Symlink").tag(LinkMode.symlink)
                        Text("Copy").tag(LinkMode.copy)
                    }
                    .pickerStyle(.segmented)
                }
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
