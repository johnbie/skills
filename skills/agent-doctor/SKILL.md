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

**If `AGENTS.md` is absent, or it has no `## Requirements` section, say so clearly and stop.** There is nothing to check — that is the whole result. Do not fall back to inference, and do not scan the repo for what it "might" need; the absence of a declaration is itself the report. (Optionally note that a repo can opt in by adding a `## Requirements` section, and show the format above.)

## How it runs

Run the steps in order; capture output; then synthesize one report — don't stream raw command output at the user.

### Step 1 — read the declaration

Read `AGENTS.md` at the repo root. Extract the required **skills** and required **MCP servers** from `## Requirements`. If the file or the section is missing, stop and report that (above). Otherwise you now have two lists (either may be empty).

### Step 2 — detect which agents are installed

Probe each of the three agents. Only an installed agent is checked; the rest are reported "not installed — skipped".

```sh
command -v claude       >/dev/null 2>&1 && claude --version 2>&1 | head -1   || echo "claude: not installed"
command -v codex        >/dev/null 2>&1 && codex --version  2>&1 | head -1   || echo "codex: not installed"
command -v cursor-agent >/dev/null 2>&1 && cursor-agent --version 2>&1 | head -1 || echo "cursor-agent: not installed"
```

### Step 3 — check skills, per installed agent

A skill is "installed" for an agent if a directory named after it, containing a `SKILL.md`, exists in that agent's skills path (personal or project scope). Check both scopes; report which scope satisfied it. Locations (verified — see the table below; if a path doesn't exist on this machine, treat it as "no skills there" rather than an error):

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

### Step 4 — check MCP servers, per installed agent

Prefer each agent's own status command (it reflects the live, merged config); fall back to parsing the config file only if the command is unavailable. Match the declared server name against the configured server names (the identifier, not the URL).

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

Emit one consolidated report (format below): the declaration that was found, then a matrix of requirement × agent, then a Fix list covering only the gaps for agents that are actually installed.

## The report format

```
agent-doctor — <repo name>
Declares (AGENTS.md ## Requirements): skills [repo-doctor, agent-doctor], MCP [github, postgres]
Agents detected: Claude Code 2.1.x ✓ · Cursor (cursor-agent) ✓ · Codex CLI — not installed

Overall: EQUIPPED  |  GAPS (N missing for installed agents)

Skills
                     Claude Code     Cursor
  repo-doctor        ✓ (~/.claude)   ✗ missing
  agent-doctor       ✓ (~/.claude)   ✗ missing
MCP servers
                     Claude Code     Cursor
  github             ✓ configured    ✓ configured
  postgres           ✗ missing       ⚠ configured, needs auth

Codex CLI — not installed, skipped.

Fix
  - Cursor / repo-doctor:  ln -s <skills-checkout>/skills/repo-doctor ~/.cursor/skills/repo-doctor
  - Cursor / agent-doctor: ln -s <skills-checkout>/skills/agent-doctor ~/.cursor/skills/agent-doctor
  - Claude Code / postgres MCP: claude mcp add postgres -- <command…>   (see the repo's Requirements note)
  - Cursor / postgres MCP auth: cursor-agent mcp login postgres
```

Use ✓ / ⚠ / ✗. A **declared skill missing** or **declared MCP server not configured** for an *installed* agent is a gap (GAPS). A server **configured but unauthenticated** is a warning. An **agent not installed** is neither — it's skipped and called out separately, never counted as a gap. If every installed agent has every declared requirement, the verdict is EQUIPPED. Keep the matrix terse; put commands in the Fix list.

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
