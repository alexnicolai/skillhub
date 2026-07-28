<p align="center">
  <img src="docs/icon.png" width="128" alt="SkillHub icon" />
</p>

<h1 align="center">SkillHub</h1>

<p align="center">
  One source of truth for your AI agent skills.<br/>
  A native macOS app that manages <code>SKILL.md</code> folders across
  <b>Claude Code, Cursor, Codex, OpenCode, Gemini CLI, and Kiro</b>.
</p>

---

## The problem

If you use more than one AI coding tool, your skills scatter: copies drift apart, you forget what's installed where, upstream updates pass you by, and nothing syncs between machines.

## What SkillHub does

- **One store.** All skills live in a single git repo (`~/ai-skills` by default). Every tool reads them through per-skill **symlinks** — edit once, every tool sees it instantly.
- **Dashboard.** Every skill with its summary, source, per-tool install state, and usage count.
- **Edit in place.** Rendered markdown preview + raw editor. Frontmatter parsed and shown as metadata.
- **Provenance & updates.** Skills installed from GitHub keep their source; SkillHub checks upstream tree hashes and updates with one click (local-edit guard included).
- **Drift detection.** If a tool dir diverges from the store, you get a badge and a one-click repair — originals are always backed up first.
- **Usage metrics.** Counts skill invocations from Claude Code transcripts.
- **Cross-machine sync.** The store is a git repo: commit/push/pull from the toolbar, clone + adopt on your other Macs.
- **An API agents can query.** `http://127.0.0.1:4477` serves the live catalog, and a generated `skillhub` meta-skill teaches your models to use it:

```sh
curl -s http://127.0.0.1:4477/skills
```

## Install

**[Download SkillHub.dmg](https://github.com/alexnicolai/skillhub/releases/latest)** → open it → drag SkillHub to Applications.

> First launch: the app is not notarized, so **right-click → Open → Open** (once). Or: `xattr -dr com.apple.quarantine /Applications/SkillHub.app`

Onboarding walks you through picking (or creating/cloning) your skill store and connecting your tools. Nothing is touched without a timestamped backup.

### Build from source

```sh
git clone https://github.com/alexnicolai/skillhub.git
cd skillhub
./make-app.sh --install   # builds and installs /Applications/SkillHub.app
```

Requires Xcode 15+ command line tools (macOS 14+).

## CLI

The same binary is a CLI:

```sh
SkillHub status           # per-tool link summary
SkillHub adopt --dry-run  # preview what adopt would do
SkillHub adopt            # import + convert all tools to symlinks
SkillHub verify           # per-tool health check
SkillHub drift            # list divergences
SkillHub updates          # check upstream repos
SkillHub update <name>    # apply one update
SkillHub usage            # per-skill usage counts
SkillHub serve            # headless API server
```

## How it works

```
your-skills-repo/
├── skills/<name>/SKILL.md   ← canonical store
├── skillhub.json            ← manifest: provenance, hashes, per-tool intent
└── .backups/                ← timestamped safety nets (gitignored)

~/.claude/skills/<name>  →  symlink into skills/<name>
~/.cursor/skills/<name>  →  symlink into skills/<name>
…and so on for every tool
```

- `SKILL.md` frontmatter (`name`, `description`) is the same across all tools, so one folder serves everyone. Codex's `agents/openai.yaml` sidecars ride along inside the skill folder — other tools ignore them.
- Tool dirs the app never touches: `~/.cursor/skills-cursor` (Cursor's managed skills) and `~/.codex/skills/.system` (Codex builtins).
- On a machine without SkillHub, the store is just plain folders in git — everything degrades gracefully.

## License

[MIT](LICENSE) — fork it, ship it, make it yours.
