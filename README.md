# skills

A personal collection of opinionated **Agent Skills** — the conventions, standards, and workflows I want a CLI coding agent to follow when it works in my repos. Skills are plain `SKILL.md` folders, so they work across Claude Code, Codex CLI, Cursor, and other agents that read the Agent Skills format.

## What this is

Three strands, all delivered as skills:

1. **Coding standards & conventions** — how I want code written and structured, encoded so an agent applies them by default instead of guessing. The source-of-truth docs live in `standards/`; the skills reference them rather than hardcoding rules.
2. **Refactoring & design diagnosis** — skills that read a codebase and report (then, separately, *apply*) improvements: design-pattern fit/misfit, Domain-Driven-Design adherence, and the refactorings that follow.
3. **Agentic-CLI onboarding** — meeting work that's still done by hand (commits, PRs, DB queries, migrations) and moving it into the agent loop. `repo-doctor` is the first of these.

Nothing here assumes a Chief-of-Staff vault or any orchestration setup — that's a deliberate separation from its sibling [`cos-tools`](../cos-tools) (which *is* CoS-specific). These are general-purpose skills for everyday agentic coding.

## Skills

Each skill lives under `skills/<name>/` and is invoked from a CLI agent session.

- **`repo-doctor`** — given any repo, dynamically infers the toolchain it needs (from `package.json`, `pyproject.toml`/`uv.lock`, `sfdx-project.json`, `Cargo.toml`, `go.mod`, …) and checks that toolchain plus the dev-flow tools (`git`, `gh`) the commit→PR loop depends on. Read-only: reports what's installed, authenticated, and missing, each gap paired with the fix command.
- **`agent-doctor`** — checks that the *agent* is equipped for a repo's work: it reads the skills and MCP servers the repo declares in its `AGENTS.md` `## Requirements`, then checks each of Claude Code, Codex CLI, and Cursor (those installed) for whether the skill is present and the MCP server configured. Read-only and cross-agent: reports gaps with fix commands; never installs or authenticates. Companion to `repo-doctor` (repo toolchain) and `cos-doctor` (CoS orchestration, in `cos-tools`).

Planned: a `standards/` area encoding coding conventions, and design-diagnosis skills that consult it. (Earlier sketches of `ddd-diagnose`/`pattern-diagnose`/`refactor` are on hold — not imminent.)

## Install

Run the install script from the repo root:

```sh
./install.sh                  # symlink every skill into ~/.claude/skills/
./install.sh repo-doctor      # just one
./install.sh --copy           # copy instead of symlink — a pinned snapshot
```

Symlink mode (the default) follows this checkout — updates flow through `git pull`, but checking out a branch here swaps the live skills too; `git checkout <tag>` to pin, or use `--copy`. Copy mode stamps the source commit into `<skill>/.installed-from` and refreshes on re-run. The script never touches anything in `~/.claude/skills/` it didn't install itself.

Skills also install fine by hand — symlink (or copy) any `skills/<name>/` folder into `~/.claude/skills/`.

## Status

Early. First skill (`repo-doctor`) implemented; standards area and refactoring/diagnosis skills are next. Target platform is WSL Linux first — cross-platform support is aspirational.

## License

Not yet specified.
