---
name: repo-doctor
description: Check that a repo has the toolchain and dev-flow tools a CLI coding agent needs to actually work in it — build, test, commit, and open PRs — by dynamically detecting the toolchain from the repo's own manifest files. Invoke from any repo before handing it to an agent, when onboarding someone to agentic CLI work, or to diagnose why a build/test/commit/PR loop is failing. Tool-agnostic (Claude Code, Codex, etc.); read-only — reports what's installed, the right version, authenticated, and missing, each gap paired with the exact fix command, and never installs or changes anything.
---

# repo-doctor

When you hand a repo to a CLI agent — or sit down to drive one yourself instead of clicking through a GUI — the agent can only close the loop (build → test → commit → PR) if the repo's toolchain and the dev-flow tools are actually installed, the right version, and authenticated. A missing `uv`, a `node` two majors behind the repo's `.nvmrc`, a `gh` that isn't logged in: each turns into a confusing mid-loop failure. This skill reads the repo's *own manifest files*, infers exactly what it needs, checks it, and reports every gap with the command to fix it.

It is **read-only and tool-agnostic**: it runs detection and version/status commands only — never installs a package, runs a login flow, or edits the repo — and it assumes nothing about which agent you use. (For the *orchestration* layer of a Chief-of-Staff vault — `tmux`, `claude`, MCP servers — see the separate `cos-doctor` skill in `cos-tools`. This skill stays at the repo level.)

## What it checks

1. **Repo toolchain — auto-detected.** Inferred from the manifest/lock/config files actually present in the repo (see the detection table). Only what the repo signals is checked; an unrelated language is never flagged.
2. **Pinned versions.** When the repo pins a version (`.nvmrc`, `.python-version`, `.tool-versions`, `engines` in `package.json`, `rust-version` in `Cargo.toml`, the `go` directive in `go.mod`…), the installed version is compared against it and a mismatch is flagged.
3. **Dev-flow tools — the agentic loop.** Always relevant regardless of language:
   - `git` — and `user.name` / `user.email` set (commits fail otherwise).
   - `gh` — and `gh auth status` (logged in, with `repo` + `workflow` scopes) so the agent can push branches and open PRs.

## How it runs

Run the steps in order; capture output; then synthesize the report — don't stream raw command output at the user.

### Step 1 — detect the toolchain

Inspect the repo root (and a shallow scan where it matters — e.g. `**/*.csproj`). Build the set of required tools from the signals present:

| Signal file(s) in the repo | Toolchain to check | Pin source |
|---|---|---|
| `package.json` | `node` + a package manager: `pnpm` (if `pnpm-lock.yaml`), `yarn` (`yarn.lock`), `bun` (`bun.lockb`), else `npm` | `.nvmrc` / `.node-version` / `engines` |
| `pyproject.toml` / `requirements.txt` / `setup.py` | `python3` + the manager: `uv` (`uv.lock`), `poetry` (`poetry.lock`), `pipenv` (`Pipfile.lock`), else `pip` | `.python-version` / `requires-python` |
| `sfdx-project.json` | `sf` (Salesforce CLI; legacy `sfdx`) | — |
| `Cargo.toml` | `cargo` + `rustc` | `rust-version` |
| `go.mod` | `go` | the `go` directive |
| `Gemfile` | `ruby` + `bundle` | `.ruby-version` |
| `composer.json` | `php` + `composer` | `config.platform.php` |
| `mix.exs` | `elixir` + `mix` | — |
| `pom.xml` | `java` + `mvn` | — |
| `build.gradle` / `build.gradle.kts` | `java` + `gradle` (prefer `./gradlew`) | — |
| `*.csproj` / `*.sln` / `global.json` | `dotnet` | `global.json` sdk |
| `Dockerfile` / `docker-compose.yml` / `compose.yaml` | `docker` (+ `docker compose`) | — |
| `*.tf` | `terraform` | `required_version` |
| `Makefile` | `make` | — |
| `.tool-versions` | `asdf` or `mise` (it pins several tools at once) | the file itself |
| `flake.nix` / `shell.nix` | `nix` | — |
| `prisma/schema.prisma`, `migrations/`, `*.sql`, a DB URL in `.env.example` | a DB client the repo implies (`psql` / `mysql` / `sqlite3`) — report as **likely**, since this is a softer signal | — |

If none of these are present, say so — the repo has no detectable toolchain beyond the dev-flow tools, which is itself useful to report.

### Step 2 — check each detected tool

For every tool in the set:

```sh
command -v <tool> >/dev/null 2>&1 && <tool> --version 2>&1 | head -1 || echo "MISSING"
```

Record present/missing + version. Where the repo pins a version (Step 1's "Pin source"), compare and flag a mismatch (e.g. `.nvmrc` says `20`, `node` is `18` → warning). Prefer a project-local runner when present (`./gradlew`, `./mvnw`, a `.venv`) over the global tool, and note that.

### Step 3 — dev-flow tools

```sh
git --version; git config --get user.name; git config --get user.email
gh --version; gh auth status
```

`user.name`/`user.email` must be non-empty. For `gh`, note login state, that `repo` + `workflow` scopes are present, and flag any account showing an error/timeout.

### Step 4 — report

Emit one consolidated report (format below): overall verdict, a grouped status table, then a Fix list covering only the gaps.

## The report format

```
repo-doctor — <repo name>
Detected: Node (package.json, pnpm), Python (pyproject.toml, uv)

Overall: READY  |  NOT READY (N blocker(s), M warning(s))

Toolchain
  ✓ node     20.11.0   (matches .nvmrc)
  ⚠ node     18.19.0   (.nvmrc pins 20 — version mismatch)
  ✗ uv       MISSING                         → blocker
  ✓ pnpm     9.1.0
Dev-flow
  ✓ git      2.51.0     identity: Jane Dev <jane@…>
  ✗ gh       installed, NOT authenticated    → blocker

Fix
  - uv: `curl -LsSf https://astral.sh/uv/install.sh | sh`  (or `pipx install uv`)
  - node 20: `nvm install 20 && nvm use 20`  (repo pins 20 via .nvmrc)
  - gh auth: `gh auth login`  (needs `repo`,`workflow` scopes for PRs)
```

Use ✓ / ⚠ / ✗. A **missing required tool** or **unauthenticated `gh`** / **unset git identity** is a blocker (NOT READY). A **version mismatch against a pin**, a missing soft-signal DB client, or a missing optional tool is a warning. Keep the table terse; put commands in the Fix list.

## Remediation hints to draw from

Adapt install commands to the detected platform (`apt`/`dnf`/`pacman`, `brew`, or the tool's official installer):

- **node** — a version manager is best for pinned repos: `nvm install <v>` / `fnm install <v>`; or `brew install node` / `sudo apt install nodejs`.
- **pnpm / yarn / bun** — `corepack enable` (ships with node) covers pnpm + yarn; `bun` via `curl -fsSL https://bun.sh/install | bash`.
- **python / uv / poetry** — `uv`: `curl -LsSf https://astral.sh/uv/install.sh | sh`; `poetry`: `pipx install poetry`; python via `pyenv install <v>` for pins.
- **sf** — `npm install -g @salesforce/cli`.
- **cargo/rustc** — `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`.
- **go** — `brew install go` / official tarball; respect the `go.mod` directive.
- **docker, terraform, dotnet, java, ruby, php, elixir** — official installer or the platform package manager.
- **git** — `sudo apt install git` / `brew install git`; identity: `git config --global user.name "<name>"` / `user.email "<email>"`.
- **gh** — `sudo apt install gh` / `brew install gh`, then `gh auth login`; missing scopes: `gh auth refresh -s repo,workflow`.

## What this skill does not do

- **No installing or authenticating.** It reports the command; you run it. Safe to run in any repo, avoids platform-specific mistakes.
- **No orchestration-layer checks.** It does not check `tmux`, the `claude` CLI, or MCP servers — that vault-level readiness is `cos-doctor`'s job (in `cos-tools`). repo-doctor is repo-local and agent-agnostic.
- **No repo edits.** It only reads the repo's files.

## Reference

- The repo's own manifest/lock/version files — the source of truth for what it needs.
- `gh auth status` — the PR-flow auth probe.
