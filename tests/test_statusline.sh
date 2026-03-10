#!/bin/bash
# Tests for statusline.sh
# sync-safe
# Usage: bash tests/test_statusline.sh
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
# Support both deployed (.claude/) and template repo (dot-claude/) layouts
if [ -d "$AGENT_DIR/.claude" ]; then
  CLAUDE_DIR="$AGENT_DIR/.claude"
elif [ -d "$AGENT_DIR/dot-claude" ]; then
  CLAUDE_DIR="$AGENT_DIR/dot-claude"
else
  echo "Cannot find .claude/ or dot-claude/ directory" >&2
  exit 1
fi
SCRIPT="$CLAUDE_DIR/statusline.sh"
if [ ! -f "$SCRIPT" ]; then
  echo "=== statusline.sh tests ==="
  echo "  SKIP: statusline.sh not found at $SCRIPT"
  echo "=== Results: 0 passed, 0 failed ==="
  exit 0
fi
PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected to contain: $expected"
    echo "    actual: $actual"
  fi
}

assert_not() {
  local desc="$1" unexpected="$2" actual="$3"
  if [[ "$actual" != *"$unexpected"* ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc (found unexpected: $unexpected)"
  fi
}

# Minimal valid JSON input
MOCK_INPUT='{"model":{"id":"claude-opus-4-6","display_name":"Opus"},"context_window":{"used_percentage":42,"remaining_percentage":58},"cost":{"total_cost_usd":1.23,"total_lines_added":50,"total_lines_removed":10},"cwd":"/tmp"}'

echo "=== statusline.sh tests ==="
echo ""

# Test: basic output contains context percentage
echo "--- basic output ---"
OUT=$(echo "$MOCK_INPUT" | AGENT_DIR="$AGENT_DIR" bash "$SCRIPT" 2>&1)
assert_eq "shows context percentage" "42%" "$OUT"
assert_eq "shows cost" "1.23" "$OUT"

# Test: with mission file
echo "--- mission display ---"
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.claude"
echo "Build the thing" > "$TMPDIR/.claude/mission"
OUT=$(echo "$MOCK_INPUT" | AGENT_DIR="$TMPDIR" bash "$SCRIPT" 2>&1)
assert_eq "shows mission" "Build the thing" "$OUT"
assert_eq "shows separator" "|" "$OUT"
rm -rf "$TMPDIR"

# Test: without mission file
echo "--- no mission ---"
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.claude"
OUT=$(echo "$MOCK_INPUT" | AGENT_DIR="$TMPDIR" bash "$SCRIPT" 2>&1)
assert_not "no separator without mission" "|" "$OUT"
rm -rf "$TMPDIR"

# Test: high context triggers color (we check it doesn't crash, can't easily verify ANSI)
echo "--- high context ---"
HIGH_CTX='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":85},"cost":{"total_cost_usd":0},"cwd":"/tmp"}'
OUT=$(echo "$HIGH_CTX" | AGENT_DIR="$AGENT_DIR" bash "$SCRIPT" 2>&1)
assert_eq "high context shows 85%" "85%" "$OUT"

# Test: zero/null values don't crash
echo "--- edge cases ---"
ZERO='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":0},"cost":{"total_cost_usd":0},"cwd":"/tmp"}'
OUT=$(echo "$ZERO" | AGENT_DIR="$AGENT_DIR" bash "$SCRIPT" 2>&1)
assert_eq "zero context shows 0%" "0%" "$OUT"
assert_eq "zero cost shows 0.00" "0.00" "$OUT"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
