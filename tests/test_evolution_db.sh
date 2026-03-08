#!/bin/bash
# Tests for evolution_db.py
# sync-safe
# Usage: bash tests/test_evolution_db.sh
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
REAL_AGENT_DIR="$AGENT_DIR"
SCRIPT="$REAL_AGENT_DIR/.claude/skills/memory/scripts/evolution_db.py"
PASS=0
FAIL=0

# Isolated test environment
TEST_DIR="/tmp/test_evolution_agent_$$"
mkdir -p "$TEST_DIR/.claude" "$TEST_DIR/evolution"
touch "$TEST_DIR/CLAUDE.md"
TEST_DB="$TEST_DIR/.claude/test_memory.db"

export AGENT_DIR="$TEST_DIR"
export EVOLUTION_DB="$TEST_DB"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

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

assert_exit() {
  local desc="$1" expected_code="$2"
  shift 2
  set +e
  "$@" >/dev/null 2>&1
  local actual_code=$?
  set -e
  if [[ "$actual_code" -eq "$expected_code" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc (expected exit $expected_code, got $actual_code)"
  fi
}

echo "=== evolution_db.py tests ==="
echo ""

# Test: add item
echo "--- add ---"
OUT=$(python3 "$SCRIPT" add "Test friction item" --category automation-candidate --impact "test impact" --context "first occurrence" 2>&1)
assert_eq "add returns item ID" "Added item #1" "$OUT"

# Test: list shows the item
echo "--- list ---"
OUT=$(python3 "$SCRIPT" list 2>&1)
assert_eq "list shows item" "Test friction item" "$OUT"
assert_eq "list shows category" "automation-candidate" "$OUT"
assert_eq "list shows 1 occurrence" "  1  " "$OUT"

# Test: add occurrence
echo "--- occur ---"
OUT=$(python3 "$SCRIPT" occur 1 "second time this happened" 2>&1)
assert_eq "occur increments count" "total: 2" "$OUT"

# Test: list sorted by occurrences
echo "--- list --sort ---"
python3 "$SCRIPT" add "Another item" --category bug-recurring --context "once" >/dev/null 2>&1
OUT=$(python3 "$SCRIPT" list --sort occurrences 2>&1)
# Item #1 (2 occurrences) should come before item #2 (1 occurrence)
LINE1=$(echo "$OUT" | grep "Test friction")
LINE2=$(echo "$OUT" | grep "Another item")
POS1=$(echo "$OUT" | grep -n "Test friction" | cut -d: -f1)
POS2=$(echo "$OUT" | grep -n "Another item" | cut -d: -f1)
if [[ "$POS1" -lt "$POS2" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: sort by occurrences orders correctly"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: sort by occurrences orders correctly"
fi

# Test: get item details
echo "--- get ---"
OUT=$(python3 "$SCRIPT" get 1 2>&1)
assert_eq "get shows title" "Test friction item" "$OUT"
assert_eq "get shows impact" "test impact" "$OUT"
assert_eq "get shows first occurrence" "first occurrence" "$OUT"
assert_eq "get shows second occurrence" "second time" "$OUT"

# Test: update status
echo "--- update ---"
OUT=$(python3 "$SCRIPT" update 1 --status resolved --notes "fixed it" 2>&1)
assert_eq "update confirms" "Updated item #1" "$OUT"
OUT=$(python3 "$SCRIPT" list --status resolved 2>&1)
assert_eq "resolved item shows in filtered list" "Test friction item" "$OUT"

# Test: change logging
echo "--- change ---"
OUT=$(python3 "$SCRIPT" change --item-id 1 --type bug-fix "Fixed the friction" 2>&1)
assert_eq "change logged" "Change logged" "$OUT"

# Test: get nonexistent item
echo "--- error cases ---"
assert_exit "get nonexistent item exits 1" 1 python3 "$SCRIPT" get 999
assert_exit "occur on nonexistent item exits 1" 1 python3 "$SCRIPT" occur 999 "nope"

# Test: export
echo "--- export ---"
OUT=$(python3 "$SCRIPT" export 2>&1)
assert_eq "export confirms" "Exported to" "$OUT"
assert_eq "observations.md created" "" "$(test -f "$AGENT_DIR/evolution/observations.md" && echo 'exists')"
assert_eq "changelog.md created" "" "$(test -f "$AGENT_DIR/evolution/changelog.md" && echo 'exists')"
# Check export content
OBS=$(cat "$AGENT_DIR/evolution/observations.md")
assert_eq "export contains item title" "Test friction item" "$OBS"
assert_eq "export shows RESOLVED tag" "RESOLVED" "$OBS"
CHG=$(cat "$AGENT_DIR/evolution/changelog.md")
assert_eq "changelog contains change" "Fixed the friction" "$CHG"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
