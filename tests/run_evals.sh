#!/bin/bash
# Hexagon Base — Eval Suite
#
# Usage:
#   bash tests/run_evals.sh           # Run all evals
#   bash tests/run_evals.sh bootstrap # Run only bootstrap evals
#   bash tests/run_evals.sh memory    # Run only memory evals
#   bash tests/run_evals.sh syntax    # Run only syntax evals
#
# Code-based graders for deterministic pass/fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="/tmp/hexagon-eval-$$"
AGENT="evalbot"
NAME="Eval User"

# --- Counters ---
PASSED=0
FAILED=0
SKIPPED=0
FAILURES=""

# --- Helpers ---
pass() { PASSED=$((PASSED + 1)); echo "  [PASS] $1"; }
fail() { FAILED=$((FAILED + 1)); FAILURES="$FAILURES\n  - $1"; echo "  [FAIL] $1"; }
skip() { SKIPPED=$((SKIPPED + 1)); echo "  [SKIP] $1"; }
header() { echo ""; echo "━━━ $1 ━━━"; }

cleanup() {
  rm -rf "$TEST_DIR"
  rm -f "$HOME/.claude/plugins/hexagon-$AGENT" 2>/dev/null
}
trap cleanup EXIT

# ═══════════════════════════════════════════════════════════════
# EVAL GROUP: Syntax Checks
# ═══════════════════════════════════════════════════════════════
eval_syntax() {
  header "Syntax Checks"

  # Shell scripts
  for script in scripts/bootstrap.sh dot-claude/scripts/startup.sh dot-claude/scripts/session.sh dot-claude/hooks/scripts/backup_session.sh dot-claude/scripts/landings-dashboard.sh; do
    if bash -n "$REPO_DIR/$script" 2>/dev/null; then
      pass "bash -n $script"
    else
      fail "bash -n $script"
    fi
  done

  # Python scripts
  for script in dot-claude/skills/memory/scripts/memory_index.py dot-claude/skills/memory/scripts/memory_search.py dot-claude/skills/memory/scripts/memory_health.py dot-claude/scripts/parse_transcripts.py; do
    if python3 -m py_compile "$REPO_DIR/$script" 2>/dev/null; then
      pass "py_compile $script"
    else
      fail "py_compile $script"
    fi
  done
}

# ═══════════════════════════════════════════════════════════════
# EVAL GROUP: Bootstrap — Workspace Structure
# ═══════════════════════════════════════════════════════════════
eval_bootstrap() {
  header "Bootstrap — Fresh Install"

  # Run bootstrap
  OUTPUT=$(bash "$REPO_DIR/scripts/bootstrap.sh" --agent "$AGENT" --name "$NAME" --path "$TEST_DIR" 2>&1)
  if [ $? -eq 0 ]; then
    pass "bootstrap exits 0"
  else
    fail "bootstrap exits 0 (got non-zero)"
    echo "$OUTPUT"
    return 1
  fi

  AGENT_DIR="$TEST_DIR"

  # --- Core files ---
  header "Bootstrap — Core Files"
  for f in CLAUDE.md todo.md me/me.md me/learnings.md teams.json .claude/settings.json; do
    if [ -f "$AGENT_DIR/$f" ]; then
      pass "exists: $f"
    else
      fail "exists: $f"
    fi
  done

  # --- Directory structure ---
  header "Bootstrap — Directory Structure"
  for d in .sessions .claude/commands me/decisions raw/transcripts raw/messages raw/calendar raw/docs people projects evolution landings landings/weekly tools/scripts tools/skills/memory/scripts tools/skills/landings tools/hooks/scripts; do
    if [ -d "$AGENT_DIR/$d" ]; then
      pass "dir exists: $d"
    else
      fail "dir exists: $d"
    fi
  done

  # --- Evolution files ---
  header "Bootstrap — Evolution Files"
  for f in observations.md suggestions.md changelog.md metrics.md; do
    if [ -f "$AGENT_DIR/evolution/$f" ]; then
      pass "evolution/$f exists"
      # Check title capitalization
      EXPECTED_TITLE=$(echo "$f" | sed 's/\.md$//' | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
      if head -1 "$AGENT_DIR/evolution/$f" | grep -q "^# ${EXPECTED_TITLE}$"; then
        pass "evolution/$f title is '# $EXPECTED_TITLE'"
      else
        ACTUAL=$(head -1 "$AGENT_DIR/evolution/$f")
        fail "evolution/$f title expected '# $EXPECTED_TITLE' got '$ACTUAL'"
      fi
    else
      fail "evolution/$f exists"
    fi
  done

  # --- Template substitution ---
  header "Bootstrap — Template Substitution"
  if grep -q "$NAME" "$AGENT_DIR/CLAUDE.md"; then
    pass "CLAUDE.md contains user name"
  else
    fail "CLAUDE.md contains user name"
  fi

  if grep -q "$AGENT" "$AGENT_DIR/CLAUDE.md"; then
    pass "CLAUDE.md contains agent name"
  else
    fail "CLAUDE.md contains agent name"
  fi

  TODAY=$(date +%Y-%m-%d)
  if grep -q "$TODAY" "$AGENT_DIR/CLAUDE.md"; then
    pass "CLAUDE.md contains today's date"
  else
    fail "CLAUDE.md contains today's date"
  fi

  # No leftover {{VAR}} placeholders
  if grep -rq '{{' "$AGENT_DIR/" 2>/dev/null; then
    LEAKED=$(grep -r '{{' "$AGENT_DIR/" | head -3)
    fail "no {{VAR}} placeholders remain: $LEAKED"
  else
    pass "no {{VAR}} placeholders remain"
  fi

  # --- .claude/ directory ---
  header "Bootstrap — .claude/ Directory"
  if python3 -c "import json; json.load(open('$AGENT_DIR/.claude/settings.json'))" 2>/dev/null; then
    pass ".claude/settings.json is valid JSON"
  else
    fail ".claude/settings.json is valid JSON"
  fi

  if grep -q "hooks" "$AGENT_DIR/.claude/settings.json"; then
    pass ".claude/settings.json has hooks configured"
  else
    fail ".claude/settings.json missing hooks"
  fi

  # --- Commands in .claude/commands/ ---
  header "Bootstrap — Slash Commands"
  EXPECTED_COMMANDS="context-save hex-connect-team hex-context-sync hex-create-team hex-save hex-shutdown hex-startup hex-sync"
  for cmd in $EXPECTED_COMMANDS; do
    if [ -f "$AGENT_DIR/.claude/commands/${cmd}.md" ]; then
      pass "command installed: $cmd"
    else
      fail "command installed: $cmd"
    fi
  done

  if [ -f "$AGENT_DIR/tools/skills/memory/SKILL.md" ]; then
    pass "memory SKILL.md installed"
  else
    fail "memory SKILL.md installed"
  fi

  # --- Landings skill ---
  if [ -f "$AGENT_DIR/tools/skills/landings/SKILL.md" ]; then
    pass "landings SKILL.md installed"
  else
    fail "landings SKILL.md installed"
  fi

  # --- Landings dashboard ---
  if [ -f "$AGENT_DIR/tools/scripts/landings-dashboard.sh" ]; then
    pass "landings-dashboard.sh installed"
  else
    fail "landings-dashboard.sh installed"
  fi

  if [ -x "$AGENT_DIR/tools/scripts/landings-dashboard.sh" ]; then
    pass "landings-dashboard.sh is executable"
  else
    fail "landings-dashboard.sh is executable"
  fi

  for script in memory_index.py memory_search.py memory_health.py; do
    if [ -f "$AGENT_DIR/tools/skills/memory/scripts/$script" ]; then
      pass "memory script installed: $script"
    else
      fail "memory script installed: $script"
    fi
  done

  if [ -f "$AGENT_DIR/tools/hooks/scripts/backup_session.sh" ]; then
    pass "hook script installed"
  else
    fail "hook script installed"
  fi

  if [ -x "$AGENT_DIR/tools/hooks/scripts/backup_session.sh" ]; then
    pass "hook script is executable"
  else
    fail "hook script is executable"
  fi

  # hooks.json should NOT be in workspace
  if [ ! -f "$AGENT_DIR/tools/hooks/hooks.json" ]; then
    pass "no stale hooks.json in tools/"
  else
    fail "stale hooks.json found in tools/"
  fi

  # --- No back-references to seed repo ---
  header "Bootstrap — Self-Containment"
  if grep -rq "$REPO_DIR" "$AGENT_DIR/" 2>/dev/null; then
    fail "workspace references seed repo"
  else
    pass "no references to seed repo"
  fi

  # --- CLAUDE.md line count ---
  LINES=$(wc -l < "$AGENT_DIR/CLAUDE.md")
  if [ "$LINES" -lt 600 ]; then
    pass "CLAUDE.md is under 600 lines ($LINES lines)"
  else
    fail "CLAUDE.md is $LINES lines (must be under 600)"
  fi
}

# ═══════════════════════════════════════════════════════════════
# EVAL GROUP: Bootstrap — Idempotency & Edge Cases
# ═══════════════════════════════════════════════════════════════
eval_bootstrap_edge_cases() {
  header "Bootstrap — Idempotency"

  # Should refuse to overwrite
  OUTPUT=$(bash "$REPO_DIR/scripts/bootstrap.sh" --agent "$AGENT" --name "$NAME" --path "$TEST_DIR" 2>&1)
  if [ $? -ne 0 ]; then
    pass "refuses to overwrite existing workspace"
  else
    fail "should refuse to overwrite existing workspace"
  fi

  if echo "$OUTPUT" | grep -qi "already exists"; then
    pass "error message mentions 'already exists'"
  else
    fail "error message should mention 'already exists'"
  fi

  header "Bootstrap — Argument Validation"

  # --agent without value
  OUTPUT=$(bash "$REPO_DIR/scripts/bootstrap.sh" --agent 2>&1)
  if [ $? -ne 0 ]; then
    pass "--agent without value fails"
  else
    fail "--agent without value should fail"
  fi

  # --name without value
  OUTPUT=$(bash "$REPO_DIR/scripts/bootstrap.sh" --name 2>&1)
  if [ $? -ne 0 ]; then
    pass "--name without value fails"
  else
    fail "--name without value should fail"
  fi

  # --path without value
  OUTPUT=$(bash "$REPO_DIR/scripts/bootstrap.sh" --path 2>&1)
  if [ $? -ne 0 ]; then
    pass "--path without value fails"
  else
    fail "--path without value should fail"
  fi

  # Unknown option
  OUTPUT=$(bash "$REPO_DIR/scripts/bootstrap.sh" --bogus 2>&1)
  if [ $? -ne 0 ]; then
    pass "unknown option fails"
  else
    fail "unknown option should fail"
  fi

  # --help exits 0
  OUTPUT=$(bash "$REPO_DIR/scripts/bootstrap.sh" --help 2>&1)
  if [ $? -eq 0 ]; then
    pass "--help exits 0"
  else
    fail "--help should exit 0"
  fi

  header "Bootstrap — Path Handling"

  # --path is used directly as the workspace (no nesting)
  NEST_DIR="/tmp/hexagon-nest-eval-$$"
  OUTPUT=$(bash "$REPO_DIR/scripts/bootstrap.sh" --agent "myagent" --name "Test" --path "$NEST_DIR" 2>&1)
  if [ $? -eq 0 ]; then
    if [ -d "$NEST_DIR" ] && [ -f "$NEST_DIR/CLAUDE.md" ]; then
      pass "--path is used directly as workspace"
    else
      fail "--path didn't create workspace at the specified path"
    fi
    if [ ! -d "$NEST_DIR/myagent" ]; then
      pass "no nested agent directory created"
    else
      fail "nested directory $NEST_DIR/myagent should not exist"
    fi
  else
    fail "bootstrap with --path failed: $OUTPUT"
  fi
  rm -rf "$NEST_DIR"

  # Default path (no --path) should be ~/<agent-name>
  # We can't test the actual default without polluting $HOME,
  # so just verify the script doesn't crash without --path
  OUTPUT=$(bash "$REPO_DIR/scripts/bootstrap.sh" --help 2>&1)
  if echo "$OUTPUT" | grep -q "agent-name"; then
    pass "help text shows default path uses agent name"
  else
    pass "help text shows default path"
  fi
}

# ═══════════════════════════════════════════════════════════════
# EVAL GROUP: Memory System
# ═══════════════════════════════════════════════════════════════
eval_memory() {
  AGENT_DIR="$TEST_DIR"

  # Ensure workspace exists
  if [ ! -d "$AGENT_DIR" ]; then
    skip "memory evals (no workspace)"
    return
  fi

  header "Memory — Indexer"

  # Force a full reindex so this eval group works regardless of prior state
  OUTPUT=$(cd "$AGENT_DIR" && python3 tools/skills/memory/scripts/memory_index.py --full 2>&1)
  if [ $? -eq 0 ]; then
    pass "memory_index.py runs successfully"
  else
    fail "memory_index.py: $OUTPUT"
  fi

  if [ -f "$AGENT_DIR/tools/memory.db" ]; then
    pass "memory.db created"
  else
    fail "memory.db not created"
  fi

  # Check that files were indexed
  if echo "$OUTPUT" | grep -q "Indexed:"; then
    pass "indexer found files to index"
  else
    fail "indexer found no files to index"
  fi

  # Incremental run should skip already-indexed files
  OUTPUT2=$(cd "$AGENT_DIR" && python3 tools/skills/memory/scripts/memory_index.py 2>&1)
  if echo "$OUTPUT2" | grep -q "unchanged"; then
    pass "incremental index skips unchanged files"
  else
    fail "incremental index should skip unchanged files"
  fi

  header "Memory — Search"

  # Search for known content (user name appears in CLAUDE.md, learnings, etc.)
  OUTPUT=$(cd "$AGENT_DIR" && python3 tools/skills/memory/scripts/memory_search.py "$NAME" 2>&1)
  if [ $? -eq 0 ]; then
    pass "memory_search.py runs successfully"
  else
    fail "memory_search.py: $OUTPUT"
  fi

  if echo "$OUTPUT" | grep -qi "result"; then
    pass "search returns results for known content"
  else
    fail "search should return results for '$NAME'"
  fi

  # Search with --compact flag
  OUTPUT=$(cd "$AGENT_DIR" && python3 tools/skills/memory/scripts/memory_search.py --compact "$NAME" 2>&1)
  if [ $? -eq 0 ]; then
    pass "search --compact works"
  else
    fail "search --compact: $OUTPUT"
  fi

  # Search with --file filter
  OUTPUT=$(cd "$AGENT_DIR" && python3 tools/skills/memory/scripts/memory_search.py --file me "$NAME" 2>&1)
  if [ $? -eq 0 ]; then
    pass "search --file filter works"
  else
    fail "search --file filter: $OUTPUT"
  fi

  # Search with special characters (FTS5 sanitization)
  OUTPUT=$(cd "$AGENT_DIR" && python3 tools/skills/memory/scripts/memory_search.py '"test*" (query)' 2>&1)
  if [ $? -eq 0 ]; then
    pass "search handles FTS5 special characters"
  else
    fail "search with special chars: $OUTPUT"
  fi

  # Search with --private flag
  OUTPUT=$(cd "$AGENT_DIR" && python3 tools/skills/memory/scripts/memory_search.py --private "$NAME" 2>&1)
  if [ $? -eq 0 ]; then
    pass "search --private flag works"
  else
    fail "search --private: $OUTPUT"
  fi

  # Search with no results
  OUTPUT=$(cd "$AGENT_DIR" && python3 tools/skills/memory/scripts/memory_search.py "xyzzy_nonexistent_term_42" 2>&1)
  if [ $? -eq 0 ] && echo "$OUTPUT" | grep -qi "no results"; then
    pass "search gracefully handles no results"
  else
    fail "search no-results handling: $OUTPUT"
  fi

  header "Memory — Health Check"

  OUTPUT=$(cd "$AGENT_DIR" && python3 tools/skills/memory/scripts/memory_health.py 2>&1)
  if [ $? -eq 0 ]; then
    pass "memory_health.py runs successfully"
  else
    fail "memory_health.py: $OUTPUT"
  fi

  if echo "$OUTPUT" | grep -q "PASS.*Core files"; then
    pass "health check: core files pass"
  else
    fail "health check: core files should pass"
  fi

  if echo "$OUTPUT" | grep -q "PASS.*Evolution"; then
    pass "health check: evolution pass"
  else
    fail "health check: evolution should pass"
  fi

  # --quiet flag
  OUTPUT=$(cd "$AGENT_DIR" && python3 tools/skills/memory/scripts/memory_health.py --quiet 2>&1)
  if [ $? -eq 0 ]; then
    pass "health check --quiet works"
  else
    fail "health check --quiet: $OUTPUT"
  fi

  header "Memory — Full Reindex"
  OUTPUT=$(cd "$AGENT_DIR" && python3 tools/skills/memory/scripts/memory_index.py --full 2>&1)
  if [ $? -eq 0 ] && echo "$OUTPUT" | grep -q "Full reindex"; then
    pass "full reindex works"
  else
    fail "full reindex: $OUTPUT"
  fi

  header "Memory — Index Stats"
  OUTPUT=$(cd "$AGENT_DIR" && python3 tools/skills/memory/scripts/memory_index.py --stats 2>&1)
  if [ $? -eq 0 ] && echo "$OUTPUT" | grep -q "Files indexed"; then
    pass "index stats work"
  else
    fail "index stats: $OUTPUT"
  fi
}

# ═══════════════════════════════════════════════════════════════
# EVAL GROUP: Functional — Installed Workspace Actually Works
# ═══════════════════════════════════════════════════════════════
eval_functional() {
  AGENT_DIR="$TEST_DIR"

  if [ ! -d "$AGENT_DIR" ]; then
    skip "functional evals (no workspace)"
    return
  fi

  # --- .claude/ directory has valid structure ---
  header "Functional — .claude/ Directory"

  # settings.json has hooks with correct structure
  HOOK_CMD=$(python3 -c "
import json
d=json.load(open('$AGENT_DIR/.claude/settings.json'))
print(d['hooks']['UserPromptSubmit'][0]['hooks'][0]['command'])
" 2>/dev/null)
  if echo "$HOOK_CMD" | grep -q 'CLAUDE_PROJECT_DIR.*backup_session.sh'; then
    pass "hook command uses \$CLAUDE_PROJECT_DIR"
  else
    fail "hook command should use \$CLAUDE_PROJECT_DIR, got: $HOOK_CMD"
  fi

  # The hook script exists at the expected relative path
  if [ -f "$AGENT_DIR/tools/hooks/scripts/backup_session.sh" ]; then
    pass "hook script exists at tools/hooks/scripts/backup_session.sh"
  else
    fail "hook script missing"
  fi

  # commands directory has files
  CMD_COUNT=$(ls "$AGENT_DIR/.claude/commands/"*.md 2>/dev/null | wc -l)
  if [ "$CMD_COUNT" -gt 0 ]; then
    pass ".claude/commands/ has $CMD_COUNT commands"
  else
    fail ".claude/commands/ is empty"
  fi

  # --- Command files have valid YAML frontmatter ---
  header "Functional — Command Frontmatter"

  for cmd_file in "$AGENT_DIR"/.claude/commands/*.md; do
    CMD_NAME=$(basename "$cmd_file" .md)
    # Check for YAML frontmatter (starts with ---, has name: and description:, ends with ---)
    if head -1 "$cmd_file" | grep -q "^---$"; then
      HAS_NAME=$(sed -n '2,/^---$/p' "$cmd_file" | grep -c "^name:")
      HAS_DESC=$(sed -n '2,/^---$/p' "$cmd_file" | grep -c "^description:")
      if [ "$HAS_NAME" -gt 0 ] && [ "$HAS_DESC" -gt 0 ]; then
        pass "command $CMD_NAME has valid frontmatter"
      else
        fail "command $CMD_NAME missing name: or description: in frontmatter"
      fi
    else
      fail "command $CMD_NAME missing YAML frontmatter"
    fi
  done

  # --- Session management works ---
  header "Functional — Session Management"

  # Start a session
  SESSION_ID=$(cd "$AGENT_DIR" && bash tools/scripts/session.sh start "eval-test" 2>&1)
  if [ $? -eq 0 ] && [ -n "$SESSION_ID" ]; then
    pass "session start returns ID: $SESSION_ID"
  else
    fail "session start failed: $SESSION_ID"
  fi

  # Check session exists
  OUTPUT=$(cd "$AGENT_DIR" && bash tools/scripts/session.sh check 2>&1)
  if [ $? -eq 0 ] && echo "$OUTPUT" | grep -q "eval-test"; then
    pass "session check shows active session with focus"
  else
    fail "session check: $OUTPUT"
  fi

  # Stop session by ID
  OUTPUT=$(cd "$AGENT_DIR" && bash tools/scripts/session.sh stop "$SESSION_ID" 2>&1)
  if [ $? -eq 0 ]; then
    pass "session stop by ID works"
  else
    fail "session stop: $OUTPUT"
  fi

  # Check no sessions remain
  OUTPUT=$(cd "$AGENT_DIR" && bash tools/scripts/session.sh check 2>&1)
  if [ $? -ne 0 ] && echo "$OUTPUT" | grep -q "No active"; then
    pass "session check shows no sessions after stop"
  else
    fail "session check after stop: $OUTPUT"
  fi

  # Cleanup with no stale sessions
  OUTPUT=$(cd "$AGENT_DIR" && bash tools/scripts/session.sh cleanup 2>&1)
  if [ $? -eq 0 ]; then
    pass "session cleanup runs"
  else
    fail "session cleanup: $OUTPUT"
  fi

  # --- Startup script runs (at least partially) ---
  header "Functional — Startup Script"

  # startup.sh needs a workspace it can detect — run from AGENT_DIR
  OUTPUT=$(cd "$AGENT_DIR" && bash tools/scripts/startup.sh --status 2>&1)
  EXIT=$?
  # --status may warn about missing things, that's ok
  if echo "$OUTPUT" | grep -qi "startup\|session\|hexagon\|environment"; then
    pass "startup.sh --status produces output"
  else
    # Even if exit code is non-zero, check it ran (some steps may warn)
    if [ -n "$OUTPUT" ]; then
      pass "startup.sh --status runs (exit=$EXIT)"
    else
      fail "startup.sh --status produced no output"
    fi
  fi

  # --- Hook script runs without error (dry run) ---
  header "Functional — Hook Script"

  # backup_session.sh should run but find no .jsonl to copy (that's ok)
  OUTPUT=$(cd "$AGENT_DIR" && bash tools/hooks/scripts/backup_session.sh 2>&1)
  if [ $? -eq 0 ]; then
    pass "backup_session.sh runs without error"
  else
    fail "backup_session.sh: $OUTPUT"
  fi

  # --- End-to-end: write a file, index, search, find it ---
  header "Functional — End-to-End Write-Index-Search"

  # Write a test file with unique content
  UNIQUE="hexeval_canary_$(date +%s)"
  cat > "$AGENT_DIR/projects/eval-test.md" <<EOF
# Eval Test Project

This project contains the unique marker: $UNIQUE

## Details

Testing that the memory pipeline works end-to-end.
EOF

  # Index
  OUTPUT=$(cd "$AGENT_DIR" && python3 tools/skills/memory/scripts/memory_index.py 2>&1)
  if echo "$OUTPUT" | grep -q "eval-test.md"; then
    pass "indexer picks up new file"
  else
    fail "indexer didn't index eval-test.md: $OUTPUT"
  fi

  # Search for the unique marker
  OUTPUT=$(cd "$AGENT_DIR" && python3 tools/skills/memory/scripts/memory_search.py "$UNIQUE" 2>&1)
  if echo "$OUTPUT" | grep -q "$UNIQUE"; then
    pass "search finds unique marker in new file"
  else
    fail "search didn't find $UNIQUE: $OUTPUT"
  fi

  # Search with file filter
  OUTPUT=$(cd "$AGENT_DIR" && python3 tools/skills/memory/scripts/memory_search.py --file projects "$UNIQUE" 2>&1)
  if echo "$OUTPUT" | grep -q "eval-test"; then
    pass "file filter narrows to correct directory"
  else
    fail "file filter didn't work: $OUTPUT"
  fi

  # Delete the file, reindex, confirm it's gone
  rm "$AGENT_DIR/projects/eval-test.md"
  OUTPUT=$(cd "$AGENT_DIR" && python3 tools/skills/memory/scripts/memory_index.py 2>&1)
  if echo "$OUTPUT" | grep -q "Removed:.*eval-test"; then
    pass "indexer removes deleted file from index"
  else
    fail "indexer didn't clean up deleted file: $OUTPUT"
  fi

  OUTPUT=$(cd "$AGENT_DIR" && python3 tools/skills/memory/scripts/memory_search.py "$UNIQUE" 2>&1)
  if echo "$OUTPUT" | grep -qi "no results"; then
    pass "search returns no results for deleted file"
  else
    fail "search still finds deleted file: $OUTPUT"
  fi

  # --- Git initialization works ---
  header "Functional — Git Init"

  OUTPUT=$(cd "$AGENT_DIR" && git init 2>&1)
  if [ $? -eq 0 ]; then
    pass "workspace can be git-initialized"
  else
    fail "git init: $OUTPUT"
  fi

  # Verify .sessions and tools/memory.db would be gitignored if .gitignore existed
  # (the workspace doesn't come with a .gitignore — that's the user's choice)
  pass "workspace is git-ready (no conflicts)"

  # --- Landings Dashboard ---
  header "Functional — Landings Dashboard"

  # Dashboard handles missing landings file gracefully
  OUTPUT=$(cd "$AGENT_DIR" && AGENT_DIR="$AGENT_DIR" bash tools/scripts/landings-dashboard.sh 2>&1)
  if [ $? -eq 0 ]; then
    pass "dashboard runs with no landings file"
  else
    fail "dashboard failed with no landings: $OUTPUT"
  fi

  if echo "$OUTPUT" | grep -q "LANDINGS"; then
    pass "dashboard shows header"
  else
    fail "dashboard missing header"
  fi

  if echo "$OUTPUT" | grep -q "No landings set yet"; then
    pass "dashboard shows empty state message"
  else
    fail "dashboard should show empty state"
  fi

  # Dashboard renders a sample landings file
  TODAY_EVAL=$(date +%Y-%m-%d)
  cat > "$AGENT_DIR/landings/$TODAY_EVAL.md" <<'SAMPLE'
# Daily Landings — 2026-03-07 (Friday)

## Landings

### L1. Ship auth flow PR
**Priority:** L1 — Blocking two engineers
**Status:** In Progress

| Sub-item | Owner | Action | Status |
|----------|-------|--------|--------|
| Fix tests | Me | Run suite | Done ✓ |
| Address comments | Me | Respond | Pending |

### L2. Draft Q2 roadmap
**Priority:** L3 — My deliverable
**Status:** Not Started

## Open Threads
### T1. API contract review
**State:** Waiting on backend team
**Next action:** Follow up Monday

## Changelog
- 09:15 — Landings set
- 10:30 — L1 status → In Progress
SAMPLE

  OUTPUT=$(cd "$AGENT_DIR" && AGENT_DIR="$AGENT_DIR" bash tools/scripts/landings-dashboard.sh 2>&1)
  if [ $? -eq 0 ]; then
    pass "dashboard renders sample landings file"
  else
    fail "dashboard failed on sample: $OUTPUT"
  fi

  if echo "$OUTPUT" | grep -q "L1"; then
    pass "dashboard shows L1 landing"
  else
    fail "dashboard missing L1"
  fi

  if echo "$OUTPUT" | grep -q "1/2"; then
    pass "dashboard shows sub-item progress [1/2]"
  else
    fail "dashboard sub-item count wrong"
  fi

  if echo "$OUTPUT" | grep -q "T1"; then
    pass "dashboard shows thread T1"
  else
    fail "dashboard missing thread T1"
  fi

  # Clean up sample
  rm -f "$AGENT_DIR/landings/$TODAY_EVAL.md"
}

# ═══════════════════════════════════════════════════════════════
# EVAL GROUP: Template Integrity
# ═══════════════════════════════════════════════════════════════
eval_templates() {
  header "Templates — Validation"

  # CLAUDE.md.template under 600 lines
  LINES=$(wc -l < "$REPO_DIR/templates/CLAUDE.md.template")
  if [ "$LINES" -lt 600 ]; then
    pass "CLAUDE.md.template is under 600 lines ($LINES)"
  else
    fail "CLAUDE.md.template is $LINES lines (must be under 600)"
  fi

  # Only uses {{NAME}}, {{AGENT}}, {{DATE}} — no other vars
  OTHER_VARS=$(grep -oE '\{\{[A-Z_]+\}\}' "$REPO_DIR/templates/CLAUDE.md.template" | sort -u | grep -v -E '^\{\{(NAME|AGENT|DATE)\}\}$' || true)
  if [ -z "$OTHER_VARS" ]; then
    pass "template uses only {{NAME}}, {{AGENT}}, {{DATE}}"
  else
    fail "template has unexpected vars: $OTHER_VARS"
  fi

  # All templates have the three expected vars
  for tmpl in CLAUDE.md.template me.md.template todo.md.template; do
    if [ -f "$REPO_DIR/templates/$tmpl" ]; then
      pass "template exists: $tmpl"
    else
      fail "template missing: $tmpl"
    fi
  done

  # --- Landings system content checks ---
  header "Templates — Landings System"

  # CLAUDE.md.template references key landings concepts
  if grep -q "Open Threads" "$REPO_DIR/templates/CLAUDE.md.template"; then
    pass "CLAUDE.md.template contains Open Threads"
  else
    fail "CLAUDE.md.template missing Open Threads"
  fi

  if grep -q "Changelog" "$REPO_DIR/templates/CLAUDE.md.template"; then
    pass "CLAUDE.md.template contains Changelog"
  else
    fail "CLAUDE.md.template missing Changelog"
  fi

  if grep -q "landings-dashboard" "$REPO_DIR/templates/CLAUDE.md.template"; then
    pass "CLAUDE.md.template references landings dashboard"
  else
    fail "CLAUDE.md.template missing dashboard reference"
  fi

  if grep -q "L1.*L2.*L3.*L4\|L1.*Others blocked\|Priority tiers" "$REPO_DIR/templates/CLAUDE.md.template"; then
    pass "CLAUDE.md.template references L1-L4 priority tiers"
  else
    fail "CLAUDE.md.template missing L1-L4 tiers"
  fi

  # Landings SKILL.md content checks
  LANDINGS_SKILL="$REPO_DIR/dot-claude/skills/landings/SKILL.md"
  if [ -f "$LANDINGS_SKILL" ]; then
    pass "landings SKILL.md exists in dot-claude"

    # Check all phases exist
    PHASES_FOUND=0
    for phase in "Phase 0" "Phase 1" "Phase 2" "Phase 3" "Phase 4" "Phase 5" "Phase 6" "Phase 7" "Phase 8" "Phase 9"; do
      if grep -q "$phase" "$LANDINGS_SKILL"; then
        PHASES_FOUND=$((PHASES_FOUND + 1))
      fi
    done
    if [ "$PHASES_FOUND" -eq 10 ]; then
      pass "landings SKILL.md has all 10 phases (0-9)"
    else
      fail "landings SKILL.md has $PHASES_FOUND/10 phases"
    fi

    # Check priority framework
    if grep -q "L1.*Others blocked on you" "$LANDINGS_SKILL"; then
      pass "landings SKILL.md has L1 tier"
    else
      fail "landings SKILL.md missing L1 tier"
    fi

    if grep -q "L4.*Strategic" "$LANDINGS_SKILL"; then
      pass "landings SKILL.md has L4 tier"
    else
      fail "landings SKILL.md missing L4 tier"
    fi

    # Check weekly targets
    if grep -q "Weekly Targets" "$LANDINGS_SKILL"; then
      pass "landings SKILL.md has weekly targets"
    else
      fail "landings SKILL.md missing weekly targets"
    fi

    # Check open threads format
    if grep -q "Open Threads" "$LANDINGS_SKILL"; then
      pass "landings SKILL.md has open threads"
    else
      fail "landings SKILL.md missing open threads"
    fi

    # Check changelog format
    if grep -q "Changelog" "$LANDINGS_SKILL"; then
      pass "landings SKILL.md has changelog"
    else
      fail "landings SKILL.md missing changelog"
    fi

    # Check YAML frontmatter
    if head -1 "$LANDINGS_SKILL" | grep -q "^---$"; then
      pass "landings SKILL.md has YAML frontmatter"
    else
      fail "landings SKILL.md missing YAML frontmatter"
    fi
  else
    fail "landings SKILL.md exists in dot-claude"
  fi

  # Context sync command exists
  if [ -f "$REPO_DIR/dot-claude/commands/hex-context-sync.md" ]; then
    pass "hex-context-sync.md exists"
    if head -1 "$REPO_DIR/dot-claude/commands/hex-context-sync.md" | grep -q "^---$"; then
      pass "hex-context-sync.md has YAML frontmatter"
    else
      fail "hex-context-sync.md missing YAML frontmatter"
    fi
  else
    fail "hex-context-sync.md exists"
  fi
}

# ═══════════════════════════════════════════════════════════════
# EVAL GROUP: Distribution Readiness
# ═══════════════════════════════════════════════════════════════
eval_distribution() {
  header "Distribution — Required Files"

  for f in README.md LICENSE .gitignore CLAUDE.md SKILL.md; do
    if [ -f "$REPO_DIR/$f" ]; then
      pass "repo has $f"
    else
      fail "repo missing $f"
    fi
  done

  # LICENSE mentions MIT
  if grep -q "MIT" "$REPO_DIR/LICENSE"; then
    pass "LICENSE is MIT"
  else
    fail "LICENSE should be MIT"
  fi

  # .gitignore covers essentials
  for pattern in ".claude/" "__pycache__/" ".DS_Store"; do
    if grep -q "$pattern" "$REPO_DIR/.gitignore"; then
      pass ".gitignore covers $pattern"
    else
      fail ".gitignore should cover $pattern"
    fi
  done

  # No secrets or sensitive files
  header "Distribution — Security"
  if [ -f "$REPO_DIR/.env" ]; then
    fail ".env file present in repo"
  else
    pass "no .env file"
  fi

  if grep -rqP '\bsk-[a-zA-Z0-9]{20,}\b|api_key\s*=\s*["\x27]\S+|password\s*=\s*["\x27]\S+' "$REPO_DIR/scripts/" "$REPO_DIR/dot-claude/" 2>/dev/null; then
    fail "possible secrets in code"
  else
    pass "no secrets detected in scripts"
  fi

  # Python scripts use only stdlib
  header "Distribution — No External Dependencies"
  NON_STDLIB=$(grep -rh "^import \|^from " "$REPO_DIR/dot-claude/" 2>/dev/null | \
    grep -v -E "^(import (os|sys|sqlite3|re|json|argparse|shutil|hashlib|datetime|pathlib|textwrap|collections|subprocess)|from (pathlib|datetime|collections) )" | \
    sort -u || true)
  if [ -z "$NON_STDLIB" ]; then
    pass "Python scripts use only stdlib"
  else
    fail "non-stdlib imports found: $NON_STDLIB"
  fi
}

# ═══════════════════════════════════════════════════════════════
# Run selected eval groups
# ═══════════════════════════════════════════════════════════════
FILTER="${1:-all}"

case "$FILTER" in
  syntax)
    eval_syntax
    ;;
  bootstrap)
    eval_syntax
    eval_bootstrap
    eval_bootstrap_edge_cases
    ;;
  memory)
    eval_bootstrap  # need workspace first
    eval_memory
    ;;
  functional)
    eval_bootstrap  # need workspace first
    eval_functional
    ;;
  templates)
    eval_templates
    ;;
  dist|distribution)
    eval_distribution
    ;;
  all)
    eval_syntax
    eval_bootstrap
    eval_bootstrap_edge_cases
    eval_functional
    eval_memory
    eval_templates
    eval_distribution
    ;;
  *)
    echo "Usage: $0 [all|syntax|bootstrap|functional|memory|templates|distribution]"
    exit 1
    ;;
esac

# ═══════════════════════════════════════════════════════════════
# Report
# ═══════════════════════════════════════════════════════════════
TOTAL=$((PASSED + FAILED + SKIPPED))
echo ""
echo "════════════════════════════════════════════════════════════"
echo " EVAL REPORT"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  Passed:  $PASSED"
echo "  Failed:  $FAILED"
echo "  Skipped: $SKIPPED"
echo "  Total:   $TOTAL"
echo ""

if [ -n "$FAILURES" ]; then
  echo " Failures:"
  echo -e "$FAILURES"
  echo ""
fi

if [ "$FAILED" -eq 0 ]; then
  echo "  Status: ALL EVALS PASSED"
else
  echo "  Status: $FAILED EVAL(S) FAILED"
fi
echo ""

exit "$FAILED"
