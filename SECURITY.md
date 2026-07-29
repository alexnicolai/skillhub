# Security

## Model

- The local API binds to `127.0.0.1` only, validates the `Host` header on every
  request (DNS-rebinding protection), and sends no CORS headers — web pages
  cannot read it. It is intentionally unauthenticated beyond that: it serves a
  single-user Mac, and any process that could reach it already runs as you.
- Agent-submitted skills (`POST /skills`) land in a review inbox; nothing
  becomes active without explicit approval in the app.
- Your GitHub token is stored in the login Keychain, never on disk in plain text.
- App updates are EdDSA-signed (Sparkle) and releases are Developer ID-signed
  and notarized by Apple.
- Destructive operations back up first; the skill store is a git repo, so
  history preserves everything.

## A note on skills themselves

Skills are instructions your AI tools follow. Installing a skill from a repo
you don't trust is equivalent to pasting its text into your agent's context —
review what you install, the same way you'd review a shell script before
running it.

## Reporting a vulnerability

Please open a [GitHub security advisory](https://github.com/alexnicolai/skillhub/security/advisories/new)
or a private report rather than a public issue. Reports are appreciated and
will be credited in release notes unless you prefer otherwise.
