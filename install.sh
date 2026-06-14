#!/usr/bin/env bash
# Install skills from this repo into ~/.claude/skills/.
#
# Usage:
#   ./install.sh                  # symlink every skill
#   ./install.sh repo-doctor      # symlink one skill
#   ./install.sh --copy           # copy instead of symlink (pinned snapshot)
#   ./install.sh --copy repo-doctor
#
# Symlink mode (default) follows the checkout: updates flow through
# `git pull`, but checking out a branch in this repo instantly swaps the
# live skills too. Copy mode pins a snapshot and stamps the source commit
# into <skill>/.installed-from; re-running refreshes the copy.
#
# Target dir defaults to ~/.claude/skills; override with CLAUDE_SKILLS_DIR.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$REPO_DIR/skills"
TARGET_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
MARKER=".installed-from"

MODE="symlink"
REQUESTED=()
for arg in "$@"; do
  case "$arg" in
    --copy) MODE="copy" ;;
    -h|--help) sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "error: unknown flag: $arg" >&2; exit 1 ;;
    *) REQUESTED+=("$arg") ;;
  esac
done

# All installable skills = subdirs of skills/ that contain a SKILL.md.
mapfile -t ALL_SKILLS < <(for d in "$SKILLS_SRC"/*/; do
  [ -f "$d/SKILL.md" ] && basename "$d"
done)

if [ "${#REQUESTED[@]}" -eq 0 ]; then
  SELECTED=("${ALL_SKILLS[@]}")
else
  SELECTED=()
  for name in "${REQUESTED[@]}"; do
    if [ ! -f "$SKILLS_SRC/$name/SKILL.md" ]; then
      echo "error: no such skill: $name (available: ${ALL_SKILLS[*]})" >&2
      exit 1
    fi
    SELECTED+=("$name")
  done
fi

COMMIT="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
mkdir -p "$TARGET_DIR"

installed=() skipped=()
for name in "${SELECTED[@]}"; do
  src="$SKILLS_SRC/$name"
  dest="$TARGET_DIR/$name"

  # Decide whether anything already at $dest is ours to replace.
  if [ -L "$dest" ]; then
    if [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ] && [ "$MODE" = "symlink" ]; then
      echo "ok: $name already symlinked"
      installed+=("$name")
      continue
    fi
    case "$(readlink -f "$dest" || true)" in
      "$REPO_DIR"/*) rm "$dest" ;;  # our old symlink; replacing
      *) echo "skip: $dest is a symlink to somewhere outside this checkout — not touching it" >&2
         skipped+=("$name"); continue ;;
    esac
  elif [ -d "$dest" ]; then
    if [ -f "$dest/$MARKER" ]; then
      rm -rf "$dest"            # our earlier copy; refreshing
    else
      echo "skip: $dest exists and wasn't installed by this script — not touching it" >&2
      skipped+=("$name"); continue
    fi
  elif [ -e "$dest" ]; then
    echo "skip: $dest exists and isn't a skill folder — not touching it" >&2
    skipped+=("$name"); continue
  fi

  if [ "$MODE" = "symlink" ]; then
    ln -s "$src" "$dest"
    echo "symlinked: $name -> $src"
  else
    cp -r "$src" "$dest"
    printf 'repo: %s\ncommit: %s\ndate: %s\n' "$REPO_DIR" "$COMMIT" "$(date -I)" > "$dest/$MARKER"
    echo "copied: $name (at $COMMIT)"
  fi
  installed+=("$name")
done

echo
echo "done: ${#installed[@]} installed, ${#skipped[@]} skipped, into $TARGET_DIR"
if [ "$MODE" = "symlink" ]; then
  echo "note: symlinks follow this checkout's branch — 'git checkout <tag>' to pin, or re-run with --copy for a snapshot."
fi
[ "${#skipped[@]}" -gt 0 ] && exit 1 || exit 0
