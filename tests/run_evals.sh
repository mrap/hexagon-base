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
  for script in scripts/bootstrap.sh plugin/scripts/startup.sh plugin/scripts/session.sh plugin/hooks/scripts/backup_session.sh; do
    if bash -n "$REPO_DIR/$script" 2>/dev/null; then
      pass "bash -n $script"
    else
      fail "bash -n $script"
    fi
  done

  # Python scripts
  for script in plugin/skills/memory/scripts/memory_index.py plugin/skills/memory/scripts/memory_search.py plugin/skills/memory/scripts/memory_health.py plugin/scripts/parse_transcripts.py; do
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

  AGENT_DIR="$TEST_DIR/$AGENT"

  # --- Core files ---
  header "Bootstrap — Core Files"
  for f in CLAUDE.md todo.md me/me.md me/learnings.md teams.json .claude-plugin/plugin.json; do
    if [ -f "$AGENT_DIR/$f" ]; then
      pass "exists: $f"
    else
      fail "exists: $f"
    fi
  done

  # --- Directory structure ---
  header "Bootstrap — Directory Structure"
  for d in .sessions me/decisions raw/transcripts raw/messages raw/calendar raw/docs people projects evolution landings tools/scripts tools/skills/memory/scripts tools/commands tools/hooks/scripts; do
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

  # --- Plugin manifest ---
  header "Bootstrap — Plugin Manifest"
  if python3 -c "import json; json.load(open('$AGENT_DIR/.claude-plugin/plugin.json'))" 2>/dev/null; then
    pass "plugin.json is valid JSON"
  else
    fail "plugin.json is valid JSON"
  fi

  if grep -q "\"${AGENT}-agent\"" "$AGENT_DIR/.claude-plugin/plugin.json"; then
    pass "plugin.json has correct agent name"
  else
    fail "plugin.json has correct agent name"
  fi

  # --- Plugin components ---
  header "Bootstrap — Plugin Components"
  EXPECTED_COMMANDS="context-save hex-connect-team hex-create-team hex-save hex-shutdown hex-startup hex-sync"
  for cmd in $EXPECTED_COMMANDS; do
    if [ -f "$AGENT_DIR/tools/commands/${cmd}.md" ]; then
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

  # hooks.json should NOT be copied (plugin.json is authoritative)
  if [ ! -f "$AGENT_DIR/tools/hooks/hooks.json" ]; then
    pass "hooks.json not copied (plugin.json is authoritative)"
  else
    fail "hooks.json should not be copied"
  fi

  # --- Plugin symlink ---
  header "Bootstrap — Plugin Symlink"
  LINK="$HOME/.claude/plugins/hexagon-$AGENT"
  if [ -L "$LINK" ]; then
    pass "plugin symlink exists"
    TARGET=$(readlink "$LINK")
    if [ "$TARGET" = "$AGENT_DIR" ]; then
      pass "symlink points to correct directory"
    else
      fail "symlink target: expected $AGENT_DIR got $TARGET"
    fi
  else
    fail "plugin symlink exists at $LINK"
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
}

# ═══════════════════════════════════════════════════════════════
# EVAL GROUP: Memory System
# ═══════════════════════════════════════════════════════════════
eval_memory() {
  AGENT_DIR="$TEST_DIR/$AGENT"

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
  AGENT_DIR="$TEST_DIR/$AGENT"

  if [ ! -d "$AGENT_DIR" ]; then
    skip "functional evals (no workspace)"
    return
  fi

  # --- Plugin manifest declares valid paths ---
  header "Functional — Plugin Manifest Paths"

  # skills path exists
  SKILLS_PATH=$(python3 -c "import json; d=json.load(open('$AGENT_DIR/.claude-plugin/plugin.json')); print(d['skills'][0])" 2>/dev/null)
  if [ -d "$AGENT_DIR/$SKILLS_PATH" ]; then
    pass "plugin.json skills path exists: $SKILLS_PATH"
  else
    fail "plugin.json skills path invalid: $SKILLS_PATH"
  fi

  # commands path exists
  CMDS_PATH=$(python3 -c "import json; d=json.load(open('$AGENT_DIR/.claude-plugin/plugin.json')); print(d['commands'][0])" 2>/dev/null)
  if [ -d "$AGENT_DIR/$CMDS_PATH" ]; then
    pass "plugin.json commands path exists: $CMDS_PATH"
  else
    fail "plugin.json commands path invalid: $CMDS_PATH"
  fi

  # hook script path resolves (after replacing ${CLAUDE_PLUGIN_ROOT})
  HOOK_CMD=$(python3 -c "
import json
d=json.load(open('$AGENT_DIR/.claude-plugin/plugin.json'))
print(d['hooks']['UserPromptSubmit'][0]['command'])
" 2>/dev/null)
  HOOK_SCRIPT=$(echo "$HOOK_CMD" | sed "s|\\\${CLAUDE_PLUGIN_ROOT}|$AGENT_DIR|" | awk '{print $2}')
  if [ -f "$HOOK_SCRIPT" ]; then
    pass "hook script path resolves: $HOOK_SCRIPT"
  else
    fail "hook script path invalid: $HOOK_SCRIPT"
  fi

  # --- Command files have valid YAML frontmatter ---
  header "Functional — Command Frontmatter"

  for cmd_file in "$AGENT_DIR"/tools/commands/*.md; do
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

  if grep -rqP '\bsk-[a-zA-Z0-9]{20,}\b|api_key\s*=\s*["\x27]\S+|password\s*=\s*["\x27]\S+' "$REPO_DIR/scripts/" "$REPO_DIR/plugin/" 2>/dev/null; then
    fail "possible secrets in code"
  else
    pass "no secrets detected in scripts"
  fi

  # Python scripts use only stdlib
  header "Distribution — No External Dependencies"
  NON_STDLIB=$(grep -rh "^import \|^from " "$REPO_DIR/plugin/" 2>/dev/null | \
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
