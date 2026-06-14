# repo-doctor

Check that a repo has the toolchain and dev-flow tools a CLI coding agent needs to build, test, commit, and open PRs in it — by **dynamically detecting** the toolchain from the repo's own manifest files. Tool-agnostic (Claude Code, Codex, …); read-only: reports what's installed, the right version, authenticated, and missing, each gap paired with the fix command. Never installs or changes anything.

## Install

Quickest: `./install.sh repo-doctor` from the repo root (see the [toolkit README](../../README.md) for options). Or by hand — skills live under `~/.claude/skills/`; symlink from your local `skills` checkout (preferred, so updates flow through `git pull`):

```sh
# Run from inside your skills checkout:
ln -s "$(pwd)/skills/repo-doctor" ~/.claude/skills/repo-doctor
```

> **Heads up about symlinks + branches:** the live skill follows whichever branch your checkout is on. For stability, copy instead of symlink, or `git checkout <tag>` before symlinking.

Or copy to pin a snapshot:

```sh
cp -r "$(pwd)/skills/repo-doctor" ~/.claude/skills/repo-doctor
```

## Invoke

From a CLI-agent session running **inside the repo** you want to check:

```
/repo-doctor
```

Or describe the intent — e.g. "is this repo ready for an agent to build and open PRs in?", or "why does the build/test loop keep failing?"

## What it does

Reads the repo's manifest/lock/version files (`package.json`, `pyproject.toml`/`uv.lock`, `sfdx-project.json`, `Cargo.toml`, `go.mod`, `.tool-versions`, …), infers exactly which tools the repo needs, and checks each for presence, version (against any pin like `.nvmrc`), and — for the dev-flow tools `git` and `gh` — authentication. Prints one readiness report, each gap paired with the exact install/auth command.

It stays at the repo level and is agent-agnostic: it does **not** check a Chief-of-Staff vault's orchestration layer (`tmux`, `claude`, MCP servers) — that's `cos-doctor` in `cos-tools`.

Full flow lives in [`SKILL.md`](./SKILL.md).
