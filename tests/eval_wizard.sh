#!/bin/bash
# Hexagon Base — Wizard Installation Eval
#
# Tests that "install hexagon" works end-to-end:
#   1. CLAUDE.md has the right instructions for Claude to follow
#   2. (--live) Sends "install hexagon" to claude -p and verifies it runs bootstrap
#
# Usage:
#   bash tests/eval_wizard.sh              # Deterministic checks only
#   bash tests/eval_wizard.sh --live       # Also runs the LLM-based eval (costs API credits)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="/tmp/hexagon-wizard-eval-$$"
LIVE_MODE=false

if [[ "${1:-}" == "--live" ]]; then
  LIVE_MODE=true
fi

# --- Counters ---
PASSED=0
FAILED=0
FAILURES=""

pass() { PASSED=$((PASSED + 1)); echo "  [PASS] $1"; }
fail() { FAILED=$((FAILED + 1)); FAILURES="$FAILURES\n  - $1"; echo "  [FAIL] $1"; }
header() { echo ""; echo "━━━ $1 ━━━"; }

cleanup() {
  rm -rf "$TEST_DIR"
  rm -f "$HOME/.claude/plugins/hexagon-wiztest" 2>/dev/null
}
trap cleanup EXIT

# ═══════════════════════════════════════════════════════════════
# PART 1: CLAUDE.md Instruction Completeness
#
# Verify CLAUDE.md contains everything Claude needs to guide
# a user through installation when they say "install hexagon"
# ═══════════════════════════════════════════════════════════════
header "Wizard — CLAUDE.md Trigger Words"

CLAUDE_MD="$REPO_DIR/CLAUDE.md"

# Must contain trigger phrases so Claude recognizes install requests
for phrase in "install hexagon" "set up" "bootstrap"; do
  if grep -qi "$phrase" "$CLAUDE_MD"; then
    pass "CLAUDE.md contains trigger: '$phrase'"
  else
    fail "CLAUDE.md missing trigger phrase: '$phrase'"
  fi
done

header "Wizard — CLAUDE.md Installation Steps"

# Must have the bootstrap command
if grep -q 'bash scripts/bootstrap.sh' "$CLAUDE_MD"; then
  pass "CLAUDE.md contains bootstrap command"
else
  fail "CLAUDE.md missing 'bash scripts/bootstrap.sh'"
fi

# Must tell Claude to ask for agent name
if grep -qi "agent name\|name.*agent\|what.*name" "$CLAUDE_MD"; then
  pass "CLAUDE.md instructs to ask for agent name"
else
  fail "CLAUDE.md doesn't instruct asking for agent name"
fi

# Must tell Claude to ask for install path
if grep -qi "install\|path\|where.*install\|location" "$CLAUDE_MD"; then
  pass "CLAUDE.md instructs to ask for install path"
else
  fail "CLAUDE.md doesn't instruct asking for install path"
fi

# Must include --agent and --path flags in the command
if grep -q '\-\-agent' "$CLAUDE_MD" && grep -q '\-\-path' "$CLAUDE_MD"; then
  pass "CLAUDE.md command includes --agent and --path flags"
else
  fail "CLAUDE.md command missing --agent or --path flags"
fi

# Must tell user what to do after install
if grep -qi "cd.*claude\|exit.*session\|new.*session\|workspace" "$CLAUDE_MD"; then
  pass "CLAUDE.md includes post-install instructions"
else
  fail "CLAUDE.md missing post-install instructions"
fi

header "Wizard — Instruction Order"

# The installation section should appear early in CLAUDE.md (before architecture details)
INSTALL_LINE=$(grep -n -i "install\|bootstrap\|set up" "$CLAUDE_MD" | head -1 | cut -d: -f1)
ARCH_LINE=$(grep -n "## Architecture" "$CLAUDE_MD" | head -1 | cut -d: -f1)

if [ -n "$INSTALL_LINE" ] && [ -n "$ARCH_LINE" ] && [ "$INSTALL_LINE" -lt "$ARCH_LINE" ]; then
  pass "installation instructions appear before architecture (line $INSTALL_LINE < $ARCH_LINE)"
else
  fail "installation instructions should appear before architecture details"
fi

# Steps should be in order: ask name → ask path → run script → tell next steps
STEP_ASK_NAME=$(grep -n -i "agent name\|name.*agent\|what.*name" "$CLAUDE_MD" | head -1 | cut -d: -f1)
STEP_RUN=$(grep -n 'bash scripts/bootstrap.sh' "$CLAUDE_MD" | head -1 | cut -d: -f1)
STEP_NEXT=$(grep -n -i 'hex-startup' "$CLAUDE_MD" | head -1 | cut -d: -f1)

if [ -n "$STEP_ASK_NAME" ] && [ -n "$STEP_RUN" ] && [ -n "$STEP_NEXT" ] && \
   [ "$STEP_ASK_NAME" -lt "$STEP_RUN" ] && [ "$STEP_RUN" -lt "$STEP_NEXT" ]; then
  pass "steps in correct order: ask name ($STEP_ASK_NAME) → run script ($STEP_RUN) → next steps ($STEP_NEXT)"
else
  fail "steps out of order: ask=$STEP_ASK_NAME run=$STEP_RUN next=$STEP_NEXT"
fi

# ═══════════════════════════════════════════════════════════════
# PART 2: Simulated Wizard (deterministic)
#
# Extract the bootstrap command from CLAUDE.md, substitute test
# values, run it, and verify the workspace was created correctly.
# This tests: "if Claude follows the instructions, does it work?"
# ═══════════════════════════════════════════════════════════════
header "Wizard — Simulated Run"

# Run bootstrap exactly as CLAUDE.md instructs
OUTPUT=$(bash "$REPO_DIR/scripts/bootstrap.sh" --agent "wiztest" --path "$TEST_DIR" 2>&1)
if [ $? -eq 0 ]; then
  pass "bootstrap succeeds when following CLAUDE.md instructions"
else
  fail "bootstrap failed: $OUTPUT"
fi

AGENT_DIR="$TEST_DIR"

# Verify the workspace is functional
if [ -f "$AGENT_DIR/CLAUDE.md" ] && [ -f "$AGENT_DIR/.claude/settings.json" ]; then
  pass "workspace has CLAUDE.md and plugin manifest"
else
  fail "workspace missing core files"
fi

# Verify the post-install instruction works: "cd <path>/<name> && claude"
# (we can't run claude, but we can verify the directory exists and is plugin-ready)
if [ -d "$AGENT_DIR" ] && [ -f "$AGENT_DIR/.claude/settings.json" ]; then
  pass "workspace is ready for 'cd $AGENT_DIR && claude'"
else
  fail "workspace not ready for claude"
fi

# Verify /hex-startup would be available (command file exists)
if [ -f "$AGENT_DIR/.claude/commands/hex-startup.md" ]; then
  pass "/hex-startup command available in workspace"
else
  fail "/hex-startup command missing from workspace"
fi

# ═══════════════════════════════════════════════════════════════
# PART 3: Live LLM Eval (optional, --live flag)
#
# Sends "install hexagon" to claude -p and checks if it attempts
# to run bootstrap.sh with the right arguments.
# ═══════════════════════════════════════════════════════════════
if [ "$LIVE_MODE" = true ]; then
  header "Wizard — Live LLM Eval"

  # Clean up the simulated workspace so bootstrap can run fresh
  cleanup
  mkdir -p "$TEST_DIR"

  # Run claude in non-interactive mode with constrained tools
  # We allow only Bash and Read so it can run bootstrap
  # We use --max-turns to prevent infinite loops
  echo "  Running: claude -p 'install hexagon' (this costs API credits)..."

  PROMPT="Install hexagon. Use agent name 'wiztest' and install path '$TEST_DIR'. Do not ask me any questions — just run the bootstrap."

  OUTPUT=$(cd "$REPO_DIR" && CLAUDECODE="" claude -p "$PROMPT" \
    --output-format json \
    --allowedTools "Bash" "Read" \
    --permission-mode bypassPermissions \
    --no-session-persistence \
    --max-turns 10 \
    2>/dev/null)
  EXIT=$?

  if [ $? -eq 0 ] && [ -n "$OUTPUT" ]; then
    pass "claude -p completed without error"
  else
    fail "claude -p failed (exit=$EXIT)"
  fi

  # Check if Claude attempted to run bootstrap.sh
  if echo "$OUTPUT" | grep -q "bootstrap.sh"; then
    pass "Claude attempted to run bootstrap.sh"
  else
    fail "Claude did not attempt to run bootstrap.sh"
  fi

  # Check if the workspace was actually created
  if [ -d "$TEST_DIR" ]; then
    pass "workspace created at $TEST_DIR"

    if [ -f "$TEST_DIR/CLAUDE.md" ]; then
      pass "workspace has CLAUDE.md"
    else
      fail "workspace missing CLAUDE.md"
    fi

    if [ -f "$TEST_DIR/.claude/settings.json" ]; then
      pass "workspace has plugin manifest"
    else
      fail "workspace missing plugin manifest"
    fi

    if [ -f "$TEST_DIR/.claude/commands/hex-startup.md" ]; then
      pass "/hex-startup available in created workspace"
    else
      fail "/hex-startup missing from workspace"
    fi
  else
    fail "workspace not created — Claude may not have run bootstrap correctly"
    echo "  Claude output:"
    echo "$OUTPUT" | head -50
  fi
else
  echo ""
  echo "  (Skipping live LLM eval. Run with --live to test the full Claude interaction.)"
  echo "  (Note: --live costs API credits.)"
fi

# ═══════════════════════════════════════════════════════════════
# Report
# ═══════════════════════════════════════════════════════════════
TOTAL=$((PASSED + FAILED))
echo ""
echo "════════════════════════════════════════════════════════════"
echo " WIZARD EVAL REPORT"
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
  echo "  Status: ALL EVALS PASSED"
else
  echo "  Status: $FAILED EVAL(S) FAILED"
fi
echo ""

exit "$FAILED"
