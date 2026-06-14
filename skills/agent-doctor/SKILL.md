---
name: agent-doctor
description: Check that the AGENT itself is equipped for a repo's work — that the skills and MCP servers the repo declares it needs are actually installed and configured in the CLI agent. Invoke from a repo whose AGENTS.md declares a `## Requirements` section, before handing the repo to an agent or when a skill/MCP-dependent workflow is failing. Cross-agent (Claude Code, Codex CLI, Cursor) and read-only — for each installed agent it reports which required skills are present and which MCP servers are configured, every gap paired with the exact fix command, and never installs, authenticates, or edits anything.
---

# agent-doctor

`repo-doctor` checks the *repo's* toolchain. `agent-doctor` checks the *agent's own equipment*: when a repo's work depends on a particular skill being installed (say `repo-doctor` itself) or a particular MCP server being configured (say `github` for PR/issue operations), the agent can only do that work if those are actually present in whatever CLI agent is driving it. A declared-but-missing skill or an unconfigured MCP server turns into a silent capability gap — the agent simply can't do the thing, and it's not obvious why. This skill reads what the repo *declares* it needs, checks that declaration against reality for every CLI agent installed on the machine, and reports each gap with the command to fix it.

It is **read-only and cross-agent**: it runs detection and status commands only — never installs a skill, runs a login/auth flow, or edits any file — and it checks Claude Code, Codex CLI, and Cursor side by side. An agent that isn't installed on the machine is reported "not installed — skipped", never a failure.

It pairs with `repo-doctor`, and each stays strictly in its lane:

- **`repo-doctor`** (this repo) — the *repo's* toolchain and dev-flow tools (`node`, `uv`, `git`, `gh`, …). Is the repo buildable?
- **`agent-doctor`** (this skill) — the *agent's* skills and MCP servers, against the repo's declaration. Is the agent equipped?

agent-doctor does **not** infer requirements or check the toolchain — that's `repo-doctor`'s job.

## The source of truth: the repo's `## Requirements`

agent-doctor checks nothing it isn't told to. The target repo declares its needs in a `## Requirements` section of its `AGENTS.md` (repo root). The skill reads that declaration and checks reality against it — it never guesses what a repo "probably" needs.

The expected format is human-readable Markdown — two optional subsections, each a bullet list of backtick-quoted names with a short purpose (and, for skills, where to get them):

```markdown
## Requirements

### Skills
- `repo-doctor` — toolchain readiness (source: github.com/johnbie/skills)
- `agent-doctor` — agent-equipment readiness (source: github.com/johnbie/skills)

### MCP servers
- `github` — PR / issue operations
- `postgres` — read-only queries against the dev database
```

Parsing is deliberately forgiving: the requirement name is the first backtick-quoted token on each bullet under the `### Skills` / `### MCP servers` headings (case-insensitive heading match; `MCP servers`, `MCP`, and `Servers` all accepted). Text after the name (purpose, source) is shown in the report but not required. A repo may declare only skills, only MCP servers, or both.

### Scoping a requirement to specific agents

By default a requirement is checked against **every installed agent** — correct for cross-agent skills (a `repo-doctor` SKILL.md works in Claude Code, Codex, or Cursor alike). But some requirements are agent-specific: a Claude Code–only orchestration skill has no meaning for Cursor, and checking it there is noise, not a gap. A requirement may therefore declare which agents it applies to, two ways:

```markdown
## Requirements

Default agents: claude

### Skills
- `cos-upgrade` — vault baseline upgrade (source: github.com/johnbie/cos-tools)
- `repo-doctor` — toolchain readiness (source: github.com/johnbie/skills) (agents: claude, cursor)
```

- **Per-requirement marker:** a trailing `(agents: <comma-separated>)` on a bullet scopes *that* requirement. Tokens are case-insensitive and accept the obvious aliases — `claude` / `claude code`, `cursor` / `cursor-agent`, `codex` / `codex cli`.
- **Section default:** an optional `Default agents: <comma-separated>` line anywhere between the `## Requirements` heading and the first subsection sets the scope for every requirement that lacks its own marker. Use it for repos driven by a single agent (the whole repo is, say, Claude-only) instead of repeating the marker on every line.

**Effective scope resolution, per requirement:** its own `(agents: …)` marker, else the `Default agents:` line, else **all installed agents**. agent-doctor checks and reports a requirement only against agents in its effective scope; an installed agent *outside* a requirement's scope is shown as `–` (not applicable) and never counts as a gap. Unknown agent tokens are reported once as a warning (a likely typo) and otherwise ignored.

**If `AGENTS.md` is absent, or it has no `## Requirements` section, say so clearly and stop.** There is nothing to check — that is the whole result. Do not fall back to inference, and do not scan the repo for what it "might" need; the absence of a declaration is itself the report. (Optionally note that a repo can opt in by adding a `## Requirements` section, and show the format above.)

## How it runs

Run the steps in order; capture output; then synthesize one report — don't stream raw command output at the user.

### Step 1 — read the declaration

Read `AGENTS.md` at the repo root. Extract the required **skills** and required **MCP servers** from `## Requirements`. For each requirement, also resolve its **effective agent scope** (per-requirement `(agents: …)` marker → `Default agents:` line → all installed agents — see [Scoping a requirement](#scoping-a-requirement-to-specific-agents)). If the file or the section is missing, stop and report that (above). Otherwise you now have two lists (either may be empty), each entry carrying its scope.

### Step 2 — detect which agents are installed

Probe each of the three agents. Only an installed agent is checked; the rest are reported "not installed — skipped". An agent is only ever checked for a requirement when it is **both** installed **and** in that requirement's effective scope.

```sh
command -v claude       >/dev/null 2>&1 && claude --version 2>&1 | head -1   || echo "claude: not installed"
command -v codex        >/dev/null 2>&1 && codex --version  2>&1 | head -1   || echo "codex: not installed"
command -v cursor-agent >/dev/null 2>&1 && cursor-agent --version 2>&1 | head -1 || echo "cursor-agent: not installed"
```

### Step 3 — check skills, per in-scope installed agent

Check each skill only against agents in its effective scope (intersected with what's installed). A skill is "installed" for an agent if a directory named after it, containing a `SKILL.md`, exists in that agent's skills path (personal or project scope). Check both scopes; report which scope satisfied it. Locations (verified — see the table below; if a path doesn't exist on this machine, treat it as "no skills there" rather than an error):

| Agent | Personal skills | Project skills | Notes |
|---|---|---|---|
| Claude Code | `~/.claude/skills/<name>/SKILL.md` | `<repo>/.claude/skills/<name>/SKILL.md` | symlinks count — a skill symlinked in from a checkout is installed |
| Cursor | `~/.cursor/skills/<name>/SKILL.md` | `<repo>/.cursor/skills/<name>/SKILL.md` | Cursor's *bundled* skills live in `~/.cursor/skills-cursor/`; user skills are in `~/.cursor/skills/` |
| Codex CLI | `~/.agents/skills/<name>/SKILL.md` | `<repo>/.agents/skills/<name>/SKILL.md` and `<repo>/.codex/skills/<name>/SKILL.md` | per OpenAI's docs Codex discovers from `.agents/skills`; some installs/tooling also use `~/.codex/skills/` — **check both and report whichever is found** |

```sh
# For each required skill <name>, for each installed agent's scope dir <dir>:
[ -f "<dir>/<name>/SKILL.md" ] && echo "present: <name> @ <dir>" || echo "missing: <name> @ <dir>"
```

Use a glob over the candidate dirs rather than assuming one exact path; a skill found in *any* of an agent's candidate locations counts as installed for that agent.

### Step 4 — check MCP servers, per in-scope installed agent

As with skills, check each server only against agents in its effective scope (intersected with what's installed). Prefer each agent's own status command (it reflects the live, merged config); fall back to parsing the config file only if the command is unavailable. Match the declared server name against the configured server names (the identifier, not the URL).

| Agent | Status command (preferred) | Config fallback |
|---|---|---|
| Claude Code | `claude mcp list` | `~/.claude.json` (global) and `<repo>/.mcp.json` (project) |
| Cursor | `cursor-agent mcp list` | `<repo>/.cursor/mcp.json` (project) and `~/.cursor/mcp.json` (global) |
| Codex CLI | `codex mcp list` (if unavailable, `codex mcp --help` to confirm the subcommand) | `~/.codex/config.toml` and `<repo>/.codex/config.toml`, section `[mcp_servers.<name>]` |

```sh
claude mcp list 2>&1        # lines look like "<name>: <url> - ✔ Connected | ! Needs authentication"
cursor-agent mcp list 2>&1
codex mcp list 2>&1
```

A server is **configured** if its name appears in the agent's list/config. Note this skill checks *configured*, not *authenticated* — a server present but showing "Needs authentication" is reported configured-but-unauthenticated (a warning, with the login command as the fix), because authenticating is an action the user takes, not this read-only skill.

### Step 5 — report

Emit one consolidated report (format below): the declaration that was found, then a matrix of requirement × agent, then a Fix list covering only the gaps for in-scope installed agents.

## The report format

```
agent-doctor — <repo name>
Declares (AGENTS.md ## Requirements): skills [cos-upgrade, repo-doctor], MCP [github]
Default agents: claude
Agents detected: Claude Code 2.1.x ✓ · Cursor (cursor-agent) ✓ · Codex CLI — not installed

Overall: EQUIPPED  |  GAPS (N missing for in-scope installed agents)

Skills
                     Claude Code     Cursor
  cos-upgrade        ✓ (~/.claude)   –            (scope: claude)
  repo-doctor        ✓ (~/.claude)   ✗ missing    (scope: claude, cursor)
MCP servers
                     Claude Code     Cursor
  github             ✓ configured    –            (scope: claude)

Codex CLI — not installed, skipped.

Fix
  - Cursor / repo-doctor:  ln -s <skills-checkout>/skills/repo-doctor ~/.cursor/skills/repo-doctor
```

Use ✓ / ⚠ / ✗ / – . A **declared skill missing** or **declared MCP server not configured** for an *in-scope, installed* agent is a gap (GAPS). A server **configured but unauthenticated** is a warning. An agent that is **not installed** (skipped, called out separately) or **out of a requirement's scope** (shown `–`) is neither — never a gap. Show each requirement's `(scope: …)` only when it isn't the default-all-agents (i.e. when a marker or `Default agents:` narrowed it), so the reader sees *why* a cell is `–`. If every in-scope installed agent has every declared requirement, the verdict is EQUIPPED. Keep the matrix terse; put commands in the Fix list.

## Fix commands to draw from

Report the command; never run it. Adapt to the declared source where the repo gives one.

- **Install a skill (Claude Code)** — symlink from a checkout (updates flow through `git pull`): `ln -s <checkout>/skills/<name> ~/.claude/skills/<name>`; or copy for a pinned snapshot. A repo that ships skills in-tree (`.claude/skills/`) needs nothing.
- **Install a skill (Cursor)** — `ln -s <checkout>/skills/<name> ~/.cursor/skills/<name>` (or `<repo>/.cursor/skills/` for project scope).
- **Install a skill (Codex CLI)** — `ln -s <checkout>/skills/<name> ~/.agents/skills/<name>` (personal) or place under `<repo>/.agents/skills/` (project). If the repo's source line points at a git repo, clone it first.
- **Configure an MCP server (Claude Code)** — `claude mcp add <name> -- <command and args>` (or `claude mcp add --transport http <name> <url>`); per-project servers go in `<repo>/.mcp.json`.
- **Configure an MCP server (Cursor)** — add an entry to `<repo>/.cursor/mcp.json` (or `~/.cursor/mcp.json`); authenticate with `cursor-agent mcp login <name>`.
- **Configure an MCP server (Codex CLI)** — `codex mcp add <name> -- <command…>`, or add a `[mcp_servers.<name>]` block to `~/.codex/config.toml`.
- **Authenticate a configured-but-unauthenticated server** — use that agent's login flow (`cursor-agent mcp login <name>`; for Claude, re-run the server's auth or `/mcp` in-session). This skill only flags it.

Whenever the repo's `## Requirements` gives a source or command for a requirement, prefer reproducing *that* in the Fix list over a generic command.

## What this skill does not do

- **No inferring requirements.** It checks only what `AGENTS.md`'s `## Requirements` declares. No declaration → no check.
- **No installing or authenticating.** It reports the command; you run it. Safe to run anywhere.
- **No toolchain checks.** Whether `node`/`uv`/`git`/`gh` are present is `repo-doctor`'s job.
- **No edits.** It only reads `AGENTS.md`, skills directories, and MCP config/status.

## Reference

- The target repo's `AGENTS.md` `## Requirements` — the source of truth for what to check.
- Claude Code — skills `~/.claude/skills/`; MCP `claude mcp list`, config `~/.claude.json` / `.mcp.json`.
- Cursor — skills `~/.cursor/skills/` (bundled in `~/.cursor/skills-cursor/`); MCP `cursor-agent mcp list`, config `.cursor/mcp.json` / `~/.cursor/mcp.json`.
- Codex CLI — skills `~/.agents/skills/` (per OpenAI docs; also seen at `~/.codex/skills/`); MCP `codex mcp list`, config `~/.codex/config.toml` `[mcp_servers.*]`.
