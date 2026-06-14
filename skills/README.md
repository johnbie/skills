# skills/

Each subdirectory here is a CLI-agent skill — invoked from an agent session to help move manual work onto the agentic loop.

Skills:

- `repo-doctor/` — detect a repo's toolchain from its own manifests and check it (plus the `git`/`gh` dev-flow tools) is installed and authenticated, so an agent can build, test, commit, and open PRs without stalling. Read-only; reports gaps with fix commands.
- `agent-doctor/` — check the agent is equipped for a repo's work: read the skills and MCP servers the repo declares in `AGENTS.md` `## Requirements`, then verify each is present/configured across the installed CLI agents (Claude Code, Codex, Cursor). Read-only; reports gaps with fix commands.

Skill source lives here; `install.sh` symlinks or copies individual skill folders into `~/.claude/skills/`.
