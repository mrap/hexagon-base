#!/bin/bash
# sync-guard.sh — Prevent personal data from leaking to hexagon-base
# sync-safe
# Usage:
#   sync-guard.sh check-path <relative-path>    # Is this path allowed?
#   sync-guard.sh scan-file <file-path>          # Does this file contain personal data?
#   sync-guard.sh scan-all <directory>           # Scan all staged files in a git repo
#
# Exit 0 = safe, Exit 1 = blocked

set -euo pipefail

# Auto-detect AGENT_DIR
if [ -z "${AGENT_DIR:-}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  candidate="$SCRIPT_DIR"
  while [ "$candidate" != "/" ]; do
    if [ -f "$candidate/CLAUDE.md" ]; then
      AGENT_DIR="$candidate"
      break
    fi
    candidate="$(dirname "$candidate")"
  done
  AGENT_DIR="${AGENT_DIR:-$HOME/hexagon}"
fi

# ─── Path Allowlist (deny by default) ────────────────────────────────────────
# Only these paths can be synced to hexagon-base.
# Everything else is blocked.
ALLOWED_PATHS=(
  "dot-claude/scripts/"
  "dot-claude/skills/"
  "dot-claude/commands/"
  "dot-claude/hooks/"
  "dot-claude/templates/"
  "CLAUDE.md"
  "SKILL.md"
  "README.md"
  "LICENSE"
  "VALIDATION.md"
  "scripts/"
  "templates/"
  "tests/"
  "docs/"
)

# ─── Personal Data Patterns ──────────────────────────────────────────────────
# Load personal terms from the agent's me.md and people/ directory
build_personal_patterns() {
  local patterns=()

  # Read name from me/me.md
  if [ -f "$AGENT_DIR/me/me.md" ]; then
    local name
    name=$(grep "^\*\*Name:\*\*" "$AGENT_DIR/me/me.md" 2>/dev/null | sed 's/\*\*Name:\*\* //' | tr -d '\r')
    if [ -n "$name" ] && [ "$name" != "Your name here" ]; then
      patterns+=("$name")
      # Also add first name and last name separately if multi-word
      local first last
      first=$(echo "$name" | awk '{print $1}')
      last=$(echo "$name" | awk '{print $NF}')
      if [ "$first" != "$last" ]; then
        patterns+=("$first" "$last")
      fi
    fi

    # Extract email-like patterns
    local emails
    emails=$(grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$AGENT_DIR/me/me.md" 2>/dev/null || true)
    for email in $emails; do
      patterns+=("$email")
    done
  fi

  # Read people names from people/ directory
  if [ -d "$AGENT_DIR/people" ]; then
    for profile in "$AGENT_DIR/people"/*/profile.md; do
      if [ -f "$profile" ]; then
        local pname
        pname=$(grep "^\*\*Name:\*\*\|^# " "$profile" 2>/dev/null | head -1 | sed 's/^# //;s/\*\*Name:\*\* //' | tr -d '\r')
        if [ -n "$pname" ]; then
          patterns+=("$pname")
        fi
      fi
    done
  fi

  # Hardcoded home directory paths (should never appear in base code)
  if [ -n "${HOME:-}" ]; then
    patterns+=("$HOME")
  fi

  # References to personal directories (should never appear in base)
  patterns+=(
    "me/me.md"
    "me/learnings.md"
    "me/decisions/"
    "people/"
    "projects/"
    "landings/"
    "evolution/"
    "todo.md"
    "teams.json"
    "raw/transcripts"
    "raw/messages"
    ".sessions/"
  )

  # Print patterns, one per line
  printf '%s\n' "${patterns[@]}"
}

# ─── Commands ─────────────────────────────────────────────────────────────────

check_path() {
  local path="$1"
  for allowed in "${ALLOWED_PATHS[@]}"; do
    if [[ "$path" == "$allowed"* ]]; then
      return 0
    fi
  done
  echo "BLOCKED: $path (not in allowlist)"
  return 1
}

scan_file() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "File not found: $file"
    return 1
  fi

  # Files with "# sync-safe" marker skip structural pattern checks
  # (these are scripts that reference directory names as part of their job)
  local is_sync_safe=false
  if grep -q "# sync-safe" "$file" 2>/dev/null; then
    is_sync_safe=true
  fi

  local patterns
  patterns=$(build_personal_patterns)
  local found=0

  while IFS= read -r pattern; do
    if [ -z "$pattern" ]; then continue; fi

    # If file is sync-safe, only check identity patterns (names, emails)
    # Skip structural patterns (directory references like me/, people/, etc.)
    if $is_sync_safe; then
      case "$pattern" in
        */|*.md|*.json|.*|raw/*) continue ;;  # Skip path-like patterns
      esac
      # Skip $HOME check (it's a path, not identity data, but contains /)
      if [[ "$pattern" == "$HOME" ]]; then continue; fi
    fi

    if grep -qi "$pattern" "$file" 2>/dev/null; then
      echo "BLOCKED: $file contains personal data: '$pattern'"
      found=1
    fi
  done <<< "$patterns"

  if [ "$found" -eq 0 ]; then
    return 0
  else
    return 1
  fi
}

scan_all() {
  local dir="$1"
  cd "$dir"
  local blocked=0

  # Check all staged files
  git diff --cached --name-only 2>/dev/null | while read -r file; do
    if ! check_path "$file" 2>/dev/null; then
      blocked=1
    fi
    if [ -f "$file" ]; then
      if ! scan_file "$file" 2>/dev/null; then
        blocked=1
      fi
    fi
  done

  return $blocked
}

# ─── Main ─────────────────────────────────────────────────────────────────────

case "${1:-}" in
  check-path)
    check_path "${2:?Usage: sync-guard.sh check-path <path>}"
    ;;
  scan-file)
    scan_file "${2:?Usage: sync-guard.sh scan-file <file>}"
    ;;
  scan-all)
    scan_all "${2:?Usage: sync-guard.sh scan-all <git-repo-dir>}"
    ;;
  build-patterns)
    build_personal_patterns
    ;;
  *)
    echo "Usage: sync-guard.sh {check-path|scan-file|scan-all|build-patterns} [args]"
    exit 1
    ;;
esac
