# agent-doctor

Check that the **agent itself** is equipped for a repo's work — that the skills and MCP servers the repo declares it needs are actually installed and configured in the CLI agent driving it. Cross-agent (Claude Code, Codex CLI, Cursor); read-only: for each agent installed on the machine it reports which required skills are present and which MCP servers are configured, each gap paired with the fix command. Never installs, authenticates, or edits anything.

Where [`repo-doctor`](../repo-doctor) asks "is the *repo* buildable?", agent-doctor asks "is the *agent* equipped?". Two lanes, no overlap.

## Install

Quickest: `./install.sh agent-doctor` from the repo root (see the [toolkit README](../../README.md) for options). Or by hand — skills live under `~/.claude/skills/`; symlink from your local `skills` checkout (preferred, so updates flow through `git pull`):

```sh
# Run from inside your skills checkout:
ln -s "$(pwd)/skills/agent-doctor" ~/.claude/skills/agent-doctor
```

> **Heads up about symlinks + branches:** the live skill follows whichever branch your checkout is on. For stability, copy instead of symlink, or `git checkout <tag>` before symlinking.

Or copy to pin a snapshot:

```sh
cp -r "$(pwd)/skills/agent-doctor" ~/.claude/skills/agent-doctor
```

## Invoke

From a CLI-agent session running **inside the repo** you want to check:

```
/agent-doctor
```

Or describe the intent — e.g. "is my agent equipped with the skills and MCP servers this repo needs?", or "why can't the agent do the github/PR step here?"

## How a repo declares its requirements

agent-doctor checks nothing it isn't told to. The repo declares what it needs in a `## Requirements` section of its root `AGENTS.md`:

```markdown
## Requirements

### Skills
- `repo-doctor` — toolchain readiness (source: github.com/johnbie/skills)

### MCP servers
- `github` — PR / issue operations
```

No `AGENTS.md`, or no `## Requirements` section → there's nothing to check, and agent-doctor says exactly that and stops. It never infers requirements.

**Scoping to specific agents.** By default each requirement is checked against every installed agent. For agent-specific requirements (a Claude Code–only skill is meaningless in Cursor), narrow the scope — per requirement with a trailing `(agents: claude, cursor)`, or for a whole single-agent repo with one `Default agents: claude` line under the `## Requirements` heading. An installed agent outside a requirement's scope shows `–` (not applicable), never a gap.

```markdown
## Requirements

Default agents: claude

### Skills
- `cos-upgrade` — vault baseline upgrade (source: github.com/johnbie/cos-tools)
- `repo-doctor` — toolchain readiness (source: github.com/johnbie/skills) (agents: claude, cursor)
```

## What it does

Reads the repo's `## Requirements` declaration, detects which of Claude Code / Codex CLI / Cursor are installed on the machine, and for each *installed* agent checks whether the declared skills are present (in its skills directories) and the declared MCP servers are configured (via `claude mcp list` / `cursor-agent mcp list` / `codex mcp list`, falling back to config files). Prints one matrix of requirement × agent, each gap paired with the exact install/configure command. An agent that isn't installed is reported "skipped", never a failure.

It stays in its lane and is agent-agnostic: it does **not** check the repo toolchain — that's `repo-doctor`.

Full flow, the verified per-agent paths, and the report format live in [`SKILL.md`](./SKILL.md).
