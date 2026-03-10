#!/bin/bash
# Hexagon Base — Integration Test
#
# Bootstraps a workspace and verifies every internal reference resolves.
# Catches broken paths in commands, settings, skills, and CLAUDE.md.
#
# Usage:
#   bash tests/run_integration.sh
#
# This is a separate script from run_evals.sh because it tests the
# installed workspace as a coherent whole, not individual components.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="/tmp/hexagon-integration-$$"
AGENT="integbot"
NAME="Integration User"

# --- Counters ---
PASSED=0
FAILED=0
FAILURES=""

pass() { PASSED=$((PASSED + 1)); echo "  [PASS] $1"; }
fail() { FAILED=$((FAILED + 1)); FAILURES="$FAILURES\n  - $1"; echo "  [FAIL] $1"; }
header() { echo ""; echo "━━━ $1 ━━━"; }

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

# ═══════════════════════════════════════════════════════════════
# Step 1: Bootstrap
# ═══════════════════════════════════════════════════════════════
header "Bootstrap"

OUTPUT=$(bash "$REPO_DIR/scripts/bootstrap.sh" --agent "$AGENT" --name "$NAME" --path "$TEST_DIR" 2>&1)
if [ $? -eq 0 ]; then
  pass "bootstrap exits 0"
else
  fail "bootstrap exits 0"
  echo "$OUTPUT"
  echo ""
  echo "Cannot continue without a workspace. Exiting."
  exit 1
fi

AGENT_DIR="$TEST_DIR"

# ═══════════════════════════════════════════════════════════════
# Step 2: Verify slash commands are discoverable
# ═══════════════════════════════════════════════════════════════
header "Slash Command Discovery"

EXPECTED_COMMANDS="context-save hex-checkpoint hex-connect-team hex-context-sync hex-create-team hex-decide hex-save hex-shutdown hex-startup hex-sync hex-sync-base hex-triage hex-ui hex-upgrade"

# Check each expected command has a file with valid frontmatter
for cmd in $EXPECTED_COMMANDS; do
  CMD_FILE="$AGENT_DIR/.claude/commands/${cmd}.md"
  if [ ! -f "$CMD_FILE" ]; then
    fail "/$cmd — file missing: .claude/commands/${cmd}.md"
    continue
  fi

  # Must start with YAML frontmatter
  if ! head -1 "$CMD_FILE" | grep -q "^---$"; then
    fail "/$cmd — missing YAML frontmatter (Claude won't discover it)"
    continue
  fi

  # Must have name: field in frontmatter
  FRONTMATTER=$(sed -n '2,/^---$/p' "$CMD_FILE" | sed '$d')
  if ! echo "$FRONTMATTER" | grep -q "^name:"; then
    fail "/$cmd — missing name: in frontmatter"
    continue
  fi

  # Must have description: field
  if ! echo "$FRONTMATTER" | grep -q "^description:"; then
    fail "/$cmd — missing description: in frontmatter"
    continue
  fi

  pass "/$cmd — discoverable with valid frontmatter"
done

# No stray commands in .claude/ root
STRAY=$(find "$AGENT_DIR/.claude" -maxdepth 1 -name "*.md" 2>/dev/null)
if [ -z "$STRAY" ]; then
  pass "no stray .md files in .claude/ root"
else
  fail "stray .md files in .claude/ root (won't be found as commands): $STRAY"
fi

# No unexpected commands (catch leftover files)
ACTUAL_COMMANDS=$(ls "$AGENT_DIR/.claude/commands/"*.md 2>/dev/null | xargs -n1 basename | sed 's/.md//' | sort)
EXPECTED_SORTED=$(echo "$EXPECTED_COMMANDS" | tr ' ' '\n' | sort)
UNEXPECTED=$(comm -23 <(echo "$ACTUAL_COMMANDS") <(echo "$EXPECTED_SORTED"))
if [ -z "$UNEXPECTED" ]; then
  pass "no unexpected command files"
else
  fail "unexpected command files: $UNEXPECTED"
fi

# ═══════════════════════════════════════════════════════════════
# Step 3: Cross-reference all $AGENT_DIR paths in commands
# ═══════════════════════════════════════════════════════════════
header "Command Path Integrity"

for cmd_file in "$AGENT_DIR"/.claude/commands/*.md; do
  CMD_NAME=$(basename "$cmd_file" .md)

  # Extract paths like $AGENT_DIR/.claude/scripts/foo.sh or $AGENT_DIR/.claude/skills/bar.py
  PATHS=$(grep -oE '\$AGENT_DIR/[^ "]+\.(sh|py)' "$cmd_file" 2>/dev/null || true)

  for ref_path in $PATHS; do
    # Resolve $AGENT_DIR to actual path
    RESOLVED="${ref_path/\$AGENT_DIR/$AGENT_DIR}"

    if [ ! -f "$RESOLVED" ]; then
      fail "/$CMD_NAME references $ref_path — file not found"
      continue
    fi

    # Shell scripts should be executable
    if [[ "$RESOLVED" == *.sh ]] && [ ! -x "$RESOLVED" ]; then
      fail "/$CMD_NAME references $ref_path — not executable"
      continue
    fi

    pass "/$CMD_NAME → $ref_path exists"
  done
done

# ═══════════════════════════════════════════════════════════════
# Step 4: Verify settings.json hook paths
# ═══════════════════════════════════════════════════════════════
header "Hook Path Integrity"

if [ ! -f "$AGENT_DIR/.claude/settings.json" ]; then
  fail "settings.json missing"
else
  # Validate JSON
  if ! python3 -c "import json; json.load(open('$AGENT_DIR/.claude/settings.json'))" 2>/dev/null; then
    fail "settings.json is not valid JSON"
  else
    pass "settings.json is valid JSON"

    # Extract hook commands and verify referenced scripts
    HOOK_CMDS=$(python3 -c "
import json
d = json.load(open('$AGENT_DIR/.claude/settings.json'))
for event, matchers in d.get('hooks', {}).items():
    for matcher in matchers:
        for hook in matcher.get('hooks', []):
            if 'command' in hook:
                print(f'{event}|{hook[\"command\"]}')
" 2>/dev/null)

    while IFS='|' read -r event cmd; do
      [ -z "$event" ] && continue

      # Extract the script path from the command (handles bash "path" and similar)
      SCRIPT_PATH=$(echo "$cmd" | grep -oE '\$CLAUDE_PROJECT_DIR/[^ "]+' | head -1)
      if [ -z "$SCRIPT_PATH" ]; then
        fail "hook $event — can't parse script path from: $cmd"
        continue
      fi

      RESOLVED="${SCRIPT_PATH/\$CLAUDE_PROJECT_DIR/$AGENT_DIR}"

      if [ ! -f "$RESOLVED" ]; then
        fail "hook $event → $SCRIPT_PATH — file not found"
      elif [ ! -x "$RESOLVED" ]; then
        fail "hook $event → $SCRIPT_PATH — not executable"
      else
        pass "hook $event → $SCRIPT_PATH exists and is executable"
      fi
    done <<< "$HOOK_CMDS"
  fi
fi

# ═══════════════════════════════════════════════════════════════
# Step 5: Verify SKILL.md script references
# ═══════════════════════════════════════════════════════════════
header "Skill Path Integrity"

find "$AGENT_DIR/.claude/skills" -name "SKILL.md" 2>/dev/null | while read -r skill_file; do
  SKILL_NAME=$(basename "$(dirname "$skill_file")")

  # Extract $AGENT_DIR paths from skill file
  PATHS=$(grep -oE '\$AGENT_DIR/[^ "]+\.(sh|py)' "$skill_file" 2>/dev/null || true)

  if [ -z "$PATHS" ]; then
    pass "skill/$SKILL_NAME — no script references (OK)"
    continue
  fi

  for ref_path in $PATHS; do
    RESOLVED="${ref_path/\$AGENT_DIR/$AGENT_DIR}"

    if [ ! -f "$RESOLVED" ]; then
      fail "skill/$SKILL_NAME references $ref_path — file not found"
    else
      pass "skill/$SKILL_NAME → $ref_path exists"
    fi
  done
done

# ═══════════════════════════════════════════════════════════════
# Step 6: Verify CLAUDE.md script references
# ═══════════════════════════════════════════════════════════════
header "CLAUDE.md Path Integrity"

if [ -f "$AGENT_DIR/CLAUDE.md" ]; then
  PATHS=$(grep -oE '\$AGENT_DIR/[^ "]+\.(sh|py)' "$AGENT_DIR/CLAUDE.md" 2>/dev/null | sort -u || true)

  for ref_path in $PATHS; do
    RESOLVED="${ref_path/\$AGENT_DIR/$AGENT_DIR}"

    if [ ! -f "$RESOLVED" ]; then
      fail "CLAUDE.md references $ref_path — file not found"
    else
      pass "CLAUDE.md → $ref_path exists"
    fi
  done

  # Also check directory references like $AGENT_DIR/.claude/skills/
  DIR_REFS=$(grep -oE '\$AGENT_DIR/[^ "]+/' "$AGENT_DIR/CLAUDE.md" 2>/dev/null | sort -u || true)

  for ref_dir in $DIR_REFS; do
    RESOLVED="${ref_dir/\$AGENT_DIR/$AGENT_DIR}"

    if [ ! -d "$RESOLVED" ]; then
      fail "CLAUDE.md references directory $ref_dir — not found"
    fi
  done
else
  fail "CLAUDE.md missing from workspace"
fi

# ═══════════════════════════════════════════════════════════════
# Step 7: End-to-end smoke test — run key scripts
# ═══════════════════════════════════════════════════════════════
header "Script Smoke Tests"

# Memory indexer
OUTPUT=$(cd "$AGENT_DIR" && python3 .claude/skills/memory/scripts/memory_index.py --full 2>&1)
if [ $? -eq 0 ]; then
  pass "memory_index.py --full runs"
else
  fail "memory_index.py --full: $OUTPUT"
fi

# Memory search
OUTPUT=$(cd "$AGENT_DIR" && python3 .claude/skills/memory/scripts/memory_search.py "$NAME" 2>&1)
if [ $? -eq 0 ]; then
  pass "memory_search.py runs"
else
  fail "memory_search.py: $OUTPUT"
fi

# Memory health
OUTPUT=$(cd "$AGENT_DIR" && python3 .claude/skills/memory/scripts/memory_health.py --quiet 2>&1)
if [ $? -eq 0 ]; then
  pass "memory_health.py runs"
else
  fail "memory_health.py: $OUTPUT"
fi

# Session management
SESSION_ID=$(cd "$AGENT_DIR" && bash .claude/scripts/session.sh start "integration-test" 2>&1)
if [ $? -eq 0 ] && [ -n "$SESSION_ID" ]; then
  pass "session.sh start works"
  cd "$AGENT_DIR" && bash .claude/scripts/session.sh stop "$SESSION_ID" > /dev/null 2>&1
else
  fail "session.sh start: $SESSION_ID"
fi

# Startup script
OUTPUT=$(cd "$AGENT_DIR" && bash .claude/scripts/startup.sh --status 2>&1)
if [ -n "$OUTPUT" ]; then
  pass "startup.sh --status runs"
else
  fail "startup.sh --status produced no output"
fi

# Hook script
OUTPUT=$(cd "$AGENT_DIR" && bash .claude/hooks/scripts/backup_session.sh 2>&1)
if [ $? -eq 0 ]; then
  pass "backup_session.sh runs"
else
  fail "backup_session.sh: $OUTPUT"
fi

# Dashboard
OUTPUT=$(cd "$AGENT_DIR" && AGENT_DIR="$AGENT_DIR" bash .claude/scripts/landings-dashboard.sh 2>&1)
if [ $? -eq 0 ]; then
  pass "landings-dashboard.sh runs"
else
  fail "landings-dashboard.sh: $OUTPUT"
fi

# ═══════════════════════════════════════════════════════════════
# Report
# ═══════════════════════════════════════════════════════════════
TOTAL=$((PASSED + FAILED))
echo ""
echo "════════════════════════════════════════════════════════════"
echo " INTEGRATION TEST REPORT"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  Passed:  $PASSED"
echo "  Failed:  $FAILED"
echo "  Total:   $TOTAL"
echo ""

if [ -n "$FAILURES" ]; then
  echo " Failures:"
  echo -e "$FAILURES"
  echo ""
fi

if [ "$FAILED" -eq 0 ]; then
  echo "  Status: ALL INTEGRATION TESTS PASSED"
else
  echo "  Status: $FAILED TEST(S) FAILED"
fi
echo ""

exit "$FAILED"
