import SwiftUI

/// ⌘K — fuzzy jump to any skill. With hundreds of skills this is the fastest
/// navigation there is.
struct QuickOpenView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    private var matches: [Skill] {
        QuickOpenView.rank(appState.skills, query: query)
    }

    /// Subsequence fuzzy match; prefix + name hits rank first.
    static func rank(_ skills: [Skill], query: String) -> [Skill] {
        guard !query.isEmpty else {
            return Array(skills.sorted { $0.usageCount > $1.usageCount }.prefix(12))
        }
        let q = query.lowercased()
        func score(_ skill: Skill) -> Int? {
            let name = skill.name.lowercased()
            if name.hasPrefix(q) { return 1000 - name.count }
            if name.contains(q) { return 500 - name.count }
            // subsequence on name
            var it = q.startIndex
            for ch in name where it < q.endIndex && ch == q[it] {
                it = q.index(after: it)
            }
            if it == q.endIndex { return 100 - name.count }
            if skill.tags.contains(where: { $0.lowercased().contains(q) }) { return 80 }
            if skill.summary.lowercased().contains(q) { return 50 }
            return nil
        }
        return skills.compactMap { skill in score(skill).map { (skill, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(12)
            .map(\.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Go to skill…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($focused)
                    .onSubmit { open(at: highlighted) }
                    .onKeyPress(.downArrow) {
                        highlighted = min(highlighted + 1, matches.count - 1); return .handled
                    }
                    .onKeyPress(.upArrow) {
                        highlighted = max(highlighted - 1, 0); return .handled
                    }
            }
            .padding(12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(matches.enumerated()), id: \.element.name) { index, skill in
                            Button {
                                open(at: index)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(skill.name).font(AppText.bodySemibold)
                                    Text(skill.summary)
                                        .font(AppText.secondary)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Spacer()
                                    ForEach(skill.tags.prefix(2), id: \.self) { tag in
                                        Text("#\(tag)")
                                            .font(AppText.small)
                                            .foregroundStyle(Color.brand)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    index == highlighted ? Color.brand.opacity(0.15) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 320)
                .onChange(of: highlighted) { proxy.scrollTo(highlighted) }
            }
        }
        .frame(width: 560)
        .onAppear { focused = true }
        .onChange(of: query) { highlighted = 0 }
    }

    private func open(at index: Int) {
        guard matches.indices.contains(index) else { return }
        appState.sidebarSelection = .all
        appState.selectedSkillNames = [matches[index].name]
        dismiss()
    }
}
