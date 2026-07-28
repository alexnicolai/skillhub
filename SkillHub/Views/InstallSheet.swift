import SwiftUI

/// Install skills from any GitHub repo: discover → pick → install with provenance.
struct InstallSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var repoText = ""
    @State private var repo: String?
    @State private var found: [RepoBrowser.RemoteSkill] = []
    @State private var picked: Set<String> = []
    @State private var busy = false
    @State private var statusText: String?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Install from GitHub")
                .font(.title2.bold())
            Text("Any repo with SKILL.md folders works. Installed skills keep their source, so updates stay one click away.")
                .font(AppText.secondary)
                .foregroundStyle(.secondary)

            HStack {
                TextField("owner/repo or GitHub URL", text: $repoText)
                    .textFieldStyle(.roundedBorder)
                    .font(AppText.mono)
                    .onSubmit { discover() }
                Button("Browse") { discover() }
                    .disabled(RepoBrowser.parseRepo(repoText) == nil || busy)
            }

            if found.isEmpty && !busy {
                VStack(alignment: .leading, spacing: 6) {
                    Text("KNOWN SOURCES")
                        .font(.system(size: 10, weight: .semibold))
                        .kerning(0.8)
                        .foregroundStyle(.tertiary)
                    ForEach(RepoBrowser.knownSources, id: \.self) { source in
                        Button(source) {
                            repoText = source
                            discover()
                        }
                        .buttonStyle(.link)
                        .font(AppText.mono)
                    }
                }
            }

            if !found.isEmpty {
                HStack {
                    Text("\(found.count) skills · \(picked.count) selected")
                        .font(AppText.secondary)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(picked.count == found.count ? "Deselect All" : "Select All") {
                        picked = picked.count == found.count ? [] : Set(found.map(\.name))
                    }
                    .controlSize(.small)
                }
                List(found) { skill in
                    let installed = appState.skills.contains { $0.name == skill.name }
                    HStack(alignment: .top, spacing: 8) {
                        Toggle("", isOn: Binding(
                            get: { picked.contains(skill.name) },
                            set: { on in
                                if on { picked.insert(skill.name) } else { picked.remove(skill.name) }
                            }
                        ))
                        .labelsHidden()
                        .disabled(installed)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(skill.name).font(AppText.bodySemibold)
                                if installed {
                                    Badge(text: "installed", color: .green)
                                }
                            }
                            if !skill.description.isEmpty {
                                Text(skill.description)
                                    .font(AppText.secondary)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 220, maxHeight: 320)
            }

            if let statusText {
                Text(statusText)
                    .font(AppText.secondary)
                    .foregroundStyle(failed ? .red : .secondary)
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                Button(picked.count > 1 ? "Install \(picked.count) Skills" : "Install") { install() }
                    .buttonStyle(.borderedProminent)
                    .disabled(picked.isEmpty || busy)
            }
        }
        .padding(20)
        .frame(width: 540)
        .overlay { if busy { ProgressView() } }
    }

    private func discover() {
        guard let parsed = RepoBrowser.parseRepo(repoText) else { return }
        repo = parsed
        busy = true
        failed = false
        statusText = nil
        found = []
        picked = []
        Task {
            do {
                let skills = try await RepoBrowser().discover(repo: parsed)
                await MainActor.run {
                    found = skills
                    statusText = skills.isEmpty ? "No SKILL.md folders found in \(parsed)." : nil
                    busy = false
                }
            } catch {
                await MainActor.run {
                    statusText = error.localizedDescription
                    failed = true
                    busy = false
                }
            }
        }
    }

    private func install() {
        guard let repo else { return }
        let selection = found.filter { picked.contains($0.name) }
        busy = true
        Task.detached {
            do {
                let result = try await MainActor.run {
                    try appState.installRemoteSkills(repo: repo, skills: selection)
                }
                await MainActor.run {
                    busy = false
                    failed = false
                    statusText = "Installed \(result.installed.count)"
                        + (result.skipped.isEmpty ? "." : " — skipped existing: \(result.skipped.joined(separator: ", "))")
                    picked = []
                }
            } catch {
                await MainActor.run {
                    busy = false
                    failed = true
                    statusText = error.localizedDescription
                }
            }
        }
    }
}
