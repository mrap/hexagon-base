#!/bin/bash
# Tests for sync-guard.sh
# sync-safe
# Usage: bash tests/test_sync_guard.sh
set -e

# Auto-detect agent dir
if [ -z "${AGENT_DIR:-}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  candidate="$(dirname "$SCRIPT_DIR")"
  while [ "$candidate" != "/" ]; do
    if [ -f "$candidate/CLAUDE.md" ]; then AGENT_DIR="$candidate"; break; fi
    candidate="$(dirname "$candidate")"
  done
fi
GUARD="$AGENT_DIR/.claude/scripts/sync-guard.sh"
PASS=0
FAIL=0

assert_pass() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc (expected pass, got blocked)"
  fi
}

assert_block() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc (expected block, got pass)"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  fi
}

echo "=== sync-guard.sh tests ==="
echo ""

# Test: allowed paths
echo "--- path allowlist ---"
assert_pass "scripts path allowed" bash "$GUARD" check-path "dot-claude/scripts/startup.sh"
assert_pass "skills path allowed" bash "$GUARD" check-path "dot-claude/skills/memory/SKILL.md"
assert_pass "commands path allowed" bash "$GUARD" check-path "dot-claude/commands/hex-save.md"
assert_pass "CLAUDE.md allowed" bash "$GUARD" check-path "CLAUDE.md"
assert_pass "README.md allowed" bash "$GUARD" check-path "README.md"
assert_pass "tests/ allowed" bash "$GUARD" check-path "tests/test_foo.sh"

# Test: blocked paths
echo "--- blocked paths ---"
assert_block "me/ blocked" bash "$GUARD" check-path "me/me.md"
assert_block "people/ blocked" bash "$GUARD" check-path "people/alice/profile.md"
assert_block "projects/ blocked" bash "$GUARD" check-path "projects/foo/context.md"
assert_block "landings/ blocked" bash "$GUARD" check-path "landings/2026-03-07.md"
assert_block "todo.md blocked" bash "$GUARD" check-path "todo.md"
assert_block "evolution/ blocked" bash "$GUARD" check-path "evolution/observations.md"
assert_block "random file blocked" bash "$GUARD" check-path "some-unknown-file.txt"
assert_block "settings.json blocked" bash "$GUARD" check-path ".claude/settings.json"

# Test: content scanning
echo "--- content scanning ---"
TMPFILE=$(mktemp)
trap "rm -f $TMPFILE" EXIT

# Safe content
echo "This is a generic script for hexagon users" > "$TMPFILE"
assert_pass "generic content passes" bash "$GUARD" scan-file "$TMPFILE"

# Personal name (dynamically read from me.md)
USER_NAME=$(grep '^\*\*Name:\*\*' "$AGENT_DIR/me/me.md" 2>/dev/null | sed 's/\*\*Name:\*\* //' | tr -d '\r')
if [ -n "$USER_NAME" ]; then
  echo "This script is for $USER_NAME specifically" > "$TMPFILE"
  assert_block "personal name blocked" bash "$GUARD" scan-file "$TMPFILE"
else
  PASS=$((PASS + 1))
  echo "  SKIP: no user name configured in me/me.md"
fi

# Personal directory reference
echo "See me/learnings.md for details" > "$TMPFILE"
assert_block "me/learnings.md reference blocked" bash "$GUARD" scan-file "$TMPFILE"

echo "Check projects/ directory" > "$TMPFILE"
assert_block "projects/ reference blocked" bash "$GUARD" scan-file "$TMPFILE"

echo "Update todo.md with new items" > "$TMPFILE"
assert_block "todo.md reference blocked" bash "$GUARD" scan-file "$TMPFILE"

# Test: pattern builder
echo "--- pattern builder ---"
PATTERNS=$(bash "$GUARD" build-patterns 2>/dev/null)
USER_NAME_CHECK=$(grep '^\*\*Name:\*\*' "$AGENT_DIR/me/me.md" 2>/dev/null | sed 's/\*\*Name:\*\* //' | awk '{print $1}' | tr -d '\r')
if [ -n "$USER_NAME_CHECK" ] && echo "$PATTERNS" | grep -q "$USER_NAME_CHECK"; then
  PASS=$((PASS + 1))
  echo "  PASS: patterns include user's name"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: patterns should include user's name"
fi

if echo "$PATTERNS" | grep -q "todo.md"; then
  PASS=$((PASS + 1))
  echo "  PASS: patterns include personal file references"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: patterns should include personal file references"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
