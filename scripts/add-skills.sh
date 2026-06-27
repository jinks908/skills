#!/usr/bin/env bash
set -euo pipefail

# Cherry-picks individual skills from this repo into a single target repo's
# project-local skill directory (<target>/.claude/skills), so that only that
# repo sees them. Use this instead of link-skills.sh when you don't want every
# skill installed globally.
#
# Each entry is a symlink into this repo, so a `git pull` here keeps the
# installed skills up to date. Pass --copy to drop frozen, committable copies
# instead (useful for sharing a repo with people who don't have this fork).
#
# Usage:
#   scripts/add-skills.sh <target-repo> <skill-name> [skill-name...]
#   scripts/add-skills.sh --copy <target-repo> <skill-name> [skill-name...]
#
# Example:
#   scripts/add-skills.sh ~/code/repos/my-api tdd diagnosing-bugs grill-with-docs

REPO="$(cd "$(dirname "$0")/.." && pwd)"

COPY=0
if [ "${1:-}" = "--copy" ]; then
  COPY=1
  shift
fi

if [ "$#" -lt 2 ]; then
  echo "usage: $(basename "$0") [--copy] <target-repo> <skill-name> [skill-name...]" >&2
  exit 1
fi

TARGET_REPO="$1"
shift

if [ ! -d "$TARGET_REPO" ]; then
  echo "error: target repo not found: $TARGET_REPO" >&2
  exit 1
fi

DEST="$(cd "$TARGET_REPO" && pwd)/.claude/skills"
mkdir -p "$DEST"

# Every known skill name in the repo (excluding deprecated). Used both to
# resolve requests and to recognise skill references inside skill bodies.
ALL_NAMES="$(find "$REPO/skills" -name SKILL.md \
  -not -path '*/node_modules/*' -not -path '*/deprecated/*' \
  -exec dirname {} \; | xargs -n1 basename | sort -u)"

# Track which skills the user actually asked for, so we can tell when a
# referenced dependency was left out.
requested=" "
for name in "$@"; do
  requested+="$name "
done

status=0
installed=()
for name in "$@"; do
  # Resolve the skill by directory name, excluding deprecated/ and node_modules.
  src="$(find "$REPO/skills" -type d -name "$name" \
    -not -path '*/node_modules/*' -not -path '*/deprecated/*' -print 2>/dev/null | head -1)"

  if [ -z "$src" ] || [ ! -f "$src/SKILL.md" ]; then
    echo "skipped $name (no such skill in $REPO/skills)" >&2
    status=1
    continue
  fi

  target="$DEST/$name"

  # Replace any existing real dir/file at the target so re-runs are idempotent.
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    rm -rf "$target"
  fi

  if [ "$COPY" -eq 1 ]; then
    rm -rf "$target"
    cp -R "$src" "$target"
    echo "copied $name -> $target"
  else
    ln -sfn "$src" "$target"
    echo "linked $name -> $src ($DEST)"
  fi

  installed+=("$name:$src")
done

# Warn about skill dependencies that were referenced but not installed.
# Skills invoke each other as `/other-skill` in their SKILL.md body, so we scan
# each installed skill for /name tokens that match a real skill the user didn't
# also request. This is advisory only — it never changes the exit status.
for entry in "${installed[@]}"; do
  name="${entry%%:*}"
  src="${entry#*:}"

  refs="$(grep -oE '/[a-z][a-z0-9-]+' "$src/SKILL.md" 2>/dev/null | sed 's|^/||' | sort -u || true)"
  missing=""
  for r in $refs; do
    [ "$r" = "$name" ] && continue
    echo "$ALL_NAMES" | grep -qx "$r" || continue            # not a real skill name
    case "$requested" in *" $r "*) continue ;; esac          # already requested
    missing+=" $r"
  done

  if [ -n "$missing" ]; then
    echo "warning: $name references skills you didn't install:$missing" >&2
    echo "         add them too if you want $name to work end-to-end:" >&2
    echo "         $(basename "$0") $TARGET_REPO$missing" >&2
  fi
done

exit "$status"
