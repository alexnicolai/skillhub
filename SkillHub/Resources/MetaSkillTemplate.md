---
name: skillhub
description: Query the local SkillHub catalog for the user's full, current set of installed AI skills. Use when you need to know what skills exist, find a skill for a task, check which tools have a skill installed, or read a skill's latest content — the SkillHub catalog is more current than any static listing.
---

# SkillHub

SkillHub is the authoritative local catalog of all the user's skills across Claude Code, Cursor, Codex, OpenCode, Gemini CLI, and Kiro. It runs a local API at `http://127.0.0.1:{{PORT}}`.

If that port doesn't respond, read the current port from `~/Library/Application Support/SkillHub/server.json` (`{"port": N}`).

## Queries

- List all skills: `curl -s http://127.0.0.1:{{PORT}}/skills`
- Get one skill (full SKILL.md + file list): `curl -s http://127.0.0.1:{{PORT}}/skills/<name>`
- Read a skill resource file: `curl -s http://127.0.0.1:{{PORT}}/skills/<name>/files/<path>`
- Usage stats: `curl -s http://127.0.0.1:{{PORT}}/usage`

## Fallback

If the SkillHub server is not running, the canonical skill folders are on disk at `{{SKILLS_DIR}}/<name>/SKILL.md` — read them directly.
