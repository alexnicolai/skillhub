---
name: skillhub
description: Query the local Skill Library (SkillHub) catalog for the user's full, current set of installed AI skills. Use when you need to know what skills exist, find a skill for a task, check which tools have a skill installed, or read a skill's latest content — the Skill Library catalog is more current than any static listing.
---

# Skill Library (skillhub)

Skill Library is the authoritative local catalog of all the user's skills across Claude Code, Cursor, Codex, OpenCode, Gemini CLI, and Kiro. It runs a local API at `http://127.0.0.1:{{PORT}}`. The meta-skill id and App Support folder remain `skillhub` / `SkillHub` for stability.

If that port doesn't respond, read the current port from `~/Library/Application Support/SkillHub/server.json` (`{"port": N}`).

## Queries

- List all skills (with tags): `curl -s http://127.0.0.1:{{PORT}}/skills`
- Get one skill (full SKILL.md + file list): `curl -s http://127.0.0.1:{{PORT}}/skills/<name>`
- Read a skill resource file: `curl -s http://127.0.0.1:{{PORT}}/skills/<name>/files/<path>`
- Usage stats: `curl -s http://127.0.0.1:{{PORT}}/usage`

## Proposing a new skill

If you develop a reusable technique worth keeping, you may propose it as a skill. It goes to the user's review inbox — it does NOT become active until they approve it. Only propose genuinely reusable, self-contained skills, and tell the user you did so.

```sh
curl -s -X POST http://127.0.0.1:{{PORT}}/skills \
  -d '{"name": "my-skill-name", "tool": "<your-tool-name>", "skillMd": "---\nname: my-skill-name\ndescription: When to use this.\n---\n\n# Content"}'
```

`name` must be lowercase-kebab. `skillMd` is the complete SKILL.md including frontmatter.

## Fallback

If the Skill Library server is not running, the canonical skill folders are on disk at `{{SKILLS_DIR}}/<name>/SKILL.md` — read them directly.
