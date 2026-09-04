import SwiftUI

/// Detail pane when several skills are selected: bulk tagging and removal.
struct BulkActionsView: View {
    @Environment(AppState.self) private var appState
    let names: Set<String>
    var onRemove: () -> Void

    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private var selected: [Skill] {
        appState.skills.filter { names.contains($0.name) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.brand)
                Text("\(names.count) skills selected")
                    .font(.title3.bold())
                Text(selected.map(\.name).prefix(8).joined(separator: " · ")
                     + (names.count > 8 ? " · …" : ""))
                    .font(AppText.secondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tag all \(names.count)")
                        .font(AppText.bodySemibold)
                    HStack {
                        TextField("New or existing tag", text: $draft)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                            .focused($fieldFocused)
                            .onSubmit { commitTag() }
                        Button("Add") { commitTag() }
                            .disabled(Tags.normalize(draft) == nil)
                        if !appState.allTags.isEmpty {
                            Menu("Existing…") {
                                ForEach(appState.allTags, id: \.tag) { entry in
                                    Button("#\(entry.tag)") {
                                        appState.addTag(entry.tag, toAll: names)
                                    }
                                }
                            }
                            .frame(maxWidth: 110)
                        }
                    }
                    Text("Tip: you can also drag selected skills onto a tag in the sidebar.")
                        .font(AppText.small)
                        .foregroundStyle(.tertiary)
                }
                .padding(6)
            }
            .frame(maxWidth: 480)

            HStack(spacing: 10) {
                let gaps = selected.filter { !Set(appState.activeTools).isSubset(of: $0.liveTools) }.count
                if gaps > 0 {
                    Button {
                        appState.enableEverywhere(names)
                    } label: {
                        Label("Make Available in Every Tool", systemImage: "link")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("\(gaps) of these are missing from at least one tool")
                }
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove \(names.count) Skills…", systemImage: "trash")
                }
                .help("Unlinks them from every tool and deletes them from the store (git history keeps copies)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func commitTag() {
        appState.addTag(draft, toAll: names)
        draft = ""
    }
}
