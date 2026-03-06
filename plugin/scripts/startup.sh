#!/bin/bash
# startup.sh — Automated session startup checklist
#
# Runs the full startup sequence for the hexagon agent.
#
# Usage:
#   startup.sh              # Full startup
#   startup.sh --quick      # Skip integration pulls
#   startup.sh --step NAME  # Run a single step
#   startup.sh --status     # Show what's been done today
#
# Exit codes:
#   0 = all steps passed
#   1 = warnings (non-fatal)
#   2 = failures (something broke)

set -uo pipefail

# ─── Resolve paths ───────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TOOLS_DIR="$AGENT_DIR/tools"
SCRIPTS_DIR="$TOOLS_DIR/scripts"
SKILLS_DIR="$TOOLS_DIR/skills"
MEMORY_SCRIPTS="$SKILLS_DIR/memory/scripts"

# Colors
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# State
WARNINGS=0
FAILURES=0
SESSION_ID=""
IS_SOLO=true
PRIVACY_MODE=false
TODAY=$(date +%Y-%m-%d)

# Privacy mode check
if [[ "${HEX_PRIVACY:-}" == "1" ]]; then
    PRIVACY_MODE=true
fi

# ─── Helpers ─────────────────────────────────────────────────────────────────
pass()   { echo -e "  [${GREEN}PASS${RESET}] $1"; }
warn()   { echo -e "  [${YELLOW}WARN${RESET}] $1"; WARNINGS=$((WARNINGS + 1)); }
fail()   { echo -e "  [${RED}FAIL${RESET}] $1"; FAILURES=$((FAILURES + 1)); }
info()   { echo -e "  ${DIM}→${RESET} $1"; }
header() { echo -e "\n${BOLD}$1${RESET}"; }

# ─── Step: Environment Detection ────────────────────────────────────────────
step_env() {
    header "1. Environment Detection"

    if [[ "$OSTYPE" == darwin* ]]; then
        pass "macOS"
    elif [[ "$OSTYPE" == linux* ]]; then
        pass "Linux"
    else
        warn "Unknown environment: $OSTYPE"
    fi

    info "AGENT_DIR=$AGENT_DIR"
}

# ─── Step: Session Management ───────────────────────────────────────────────
step_session() {
    header "2. Session Management"

    SESSION_SH="$SCRIPTS_DIR/session.sh"
    if [[ ! -f "$SESSION_SH" ]]; then
        fail "session.sh not found at $SESSION_SH"
        return
    fi

    # Cleanup stale sessions first
    CLEANUP_OUT=$(bash "$SESSION_SH" cleanup 2>&1)
    info "$CLEANUP_OUT"

    # Check for other sessions
    CHECK_OUT=$(bash "$SESSION_SH" check 2>&1) || true
    if echo "$CHECK_OUT" | grep -q "No active sessions"; then
        IS_SOLO=true
        pass "No other sessions. Solo mode."
    else
        IS_SOLO=false
        ACTIVE_COUNT=$(echo "$CHECK_OUT" | grep -c "^SESSION" || echo "0")
        warn "$ACTIVE_COUNT other session(s) active. Limited mode."
        echo "$CHECK_OUT" | grep "^SESSION" | while read -r line; do
            info "$line"
        done
    fi

    # Register this session
    SESSION_ID=$(bash "$SESSION_SH" start "startup-script" 2>&1)
    pass "Registered session: $SESSION_ID"
}

# ─── Step: Parse Transcripts ───────────────────────────────────────────────
step_transcripts() {
    header "3. Parse Transcripts"

    PARSER="$SCRIPTS_DIR/parse_transcripts.py"
    if [[ ! -f "$PARSER" ]]; then
        warn "parse_transcripts.py not found"
        return
    fi

    PARSE_OUT=$(python3 "$PARSER" 2>&1)
    if echo "$PARSE_OUT" | grep -q "No new transcripts"; then
        pass "All transcripts already parsed"
    elif echo "$PARSE_OUT" | grep -q "No .jsonl files"; then
        pass "No transcripts to parse"
    else
        echo "$PARSE_OUT" | while read -r line; do
            [[ -n "$line" ]] && info "$line"
        done
        pass "Transcripts parsed"
    fi
}

# ─── Step: Rebuild Memory Index ────────────────────────────────────────────
step_index() {
    header "4. Memory Index"

    INDEXER="$MEMORY_SCRIPTS/memory_index.py"
    if [[ ! -f "$INDEXER" ]]; then
        fail "memory_index.py not found"
        return
    fi

    INDEX_OUT=$(python3 "$INDEXER" 2>&1)
    INDEXED=$(echo "$INDEX_OUT" | grep "^Done:" || echo "$INDEX_OUT" | tail -1)
    if [[ -n "$INDEXED" ]]; then
        info "$INDEXED"
    fi
    pass "Memory index rebuilt"
}

# ─── Step: Memory Health Check ─────────────────────────────────────────────
step_health() {
    header "5. Memory Health"

    HEALTH="$MEMORY_SCRIPTS/memory_health.py"
    if [[ ! -f "$HEALTH" ]]; then
        warn "memory_health.py not found"
        return
    fi

    HEALTH_OUT=$(python3 "$HEALTH" --quiet 2>&1)
    if echo "$HEALTH_OUT" | grep -q "FAIL"; then
        echo "$HEALTH_OUT" | grep "FAIL" | while read -r line; do
            fail "$(echo "$line" | sed 's/.*FAIL.*\] //')"
        done
    elif echo "$HEALTH_OUT" | grep -q "WARN"; then
        echo "$HEALTH_OUT" | grep "WARN" | while read -r line; do
            warn "$(echo "$line" | sed 's/.*WARN.*\] //')"
        done
    else
        pass "All health checks passed"
    fi
}

# ─── Step: Integrations Check ──────────────────────────────────────────────
step_integrations() {
    header "6. Integrations"

    # Check for integrations.json (user-configured external tools)
    INTEGRATIONS="$AGENT_DIR/integrations.json"
    if [[ ! -f "$INTEGRATIONS" ]]; then
        info "No integrations configured. The agent works without them."
        info "Create integrations.json to connect external tools (calendar, messaging, etc.)"
        return
    fi

    # Parse and report configured integrations
    while IFS= read -r line; do
        NAME=$(echo "$line" | grep -o '"name": "[^"]*"' | cut -d'"' -f4)
        ENABLED=$(echo "$line" | grep -o '"enabled": [a-z]*' | cut -d: -f2 | xargs)
        if [[ "$ENABLED" == "true" ]]; then
            pass "$NAME connected"
        else
            info "$NAME configured but disabled"
        fi
    done < <(python3 -c "
import json, sys
try:
    with open('$INTEGRATIONS') as f:
        data = json.load(f)
    for name, cfg in data.get('integrations', {}).items():
        print(json.dumps({'name': name, 'enabled': cfg.get('enabled', False)}))
except Exception as e:
    print(f'Error reading integrations: {e}', file=sys.stderr)
" 2>&1) || true
}

# ─── Step: Evolution Check ─────────────────────────────────────────────────
step_evolution() {
    header "7. Improvement Engine"

    SUGGESTIONS="$AGENT_DIR/evolution/suggestions.md"
    if [[ ! -f "$SUGGESTIONS" ]]; then
        info "No improvement suggestions yet"
        return
    fi

    # Count pending suggestions (lines starting with "## " that have "Status: proposed")
    PENDING=$(grep -c "Status: proposed" "$SUGGESTIONS" 2>/dev/null || echo "0")
    if [[ "$PENDING" -gt 0 ]]; then
        warn "$PENDING pending improvement suggestion(s). Review at session start."
    else
        pass "No pending suggestions"
    fi
}

# ─── Step: Status ──────────────────────────────────────────────────────────
step_status() {
    header "Startup Status — $TODAY"

    # Active sessions
    if ls "$AGENT_DIR/.sessions"/session_*.json 1>/dev/null 2>&1; then
        SESSION_COUNT=$(ls "$AGENT_DIR/.sessions"/session_*.json 2>/dev/null | wc -l | xargs)
        info "Active sessions: $SESSION_COUNT"
    else
        info "No active sessions"
    fi

    # Transcripts
    if ls "$AGENT_DIR/raw/transcripts"/*.md 1>/dev/null 2>&1; then
        MD_COUNT=$(ls "$AGENT_DIR/raw/transcripts"/*.md 2>/dev/null | wc -l | xargs)
        pass "Transcripts: $MD_COUNT parsed files"
    else
        info "No parsed transcripts"
    fi

    # Memory DB freshness
    DB="$TOOLS_DIR/memory.db"
    if [[ -f "$DB" ]]; then
        if [[ "$OSTYPE" == darwin* ]]; then
            DB_MOD=$(stat -f %m "$DB")
        else
            DB_MOD=$(stat -c %Y "$DB")
        fi
        DB_AGE=$(( ($(date +%s) - DB_MOD) / 60 ))
        if [[ $DB_AGE -lt 60 ]]; then
            pass "Memory index fresh (${DB_AGE}min ago)"
        else
            warn "Memory index stale (${DB_AGE}min ago)"
        fi
    else
        warn "No memory.db"
    fi
}

# ─── Main ──────────────────────────────────────────────────────────────────
main() {
    local QUICK=false
    local SINGLE_STEP=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --quick)  QUICK=true; shift ;;
            --step)   SINGLE_STEP="${2:-}"; shift 2 ;;
            --status) step_status; exit 0 ;;
            --help|-h)
                echo "Usage: startup.sh [--quick] [--step NAME] [--status]"
                echo ""
                echo "Steps: env, session, transcripts, index, health, integrations, evolution"
                echo ""
                echo "Options:"
                echo "  --quick    Skip integration checks"
                echo "  --step X   Run only step X"
                echo "  --status   Show what's been done today"
                exit 0
                ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done

    # Single step mode
    if [[ -n "$SINGLE_STEP" ]]; then
        case "$SINGLE_STEP" in
            env)          step_env ;;
            session)      step_session ;;
            transcripts)  step_transcripts ;;
            index)        step_index ;;
            health)       step_health ;;
            integrations) step_integrations ;;
            evolution)    step_evolution ;;
            *) echo "Unknown step: $SINGLE_STEP"; exit 1 ;;
        esac
        exit 0
    fi

    # Full startup
    echo ""
    echo "============================================================"
    echo " Hexagon Startup — $(date '+%Y-%m-%d %H:%M')"
    echo "============================================================"

    if $PRIVACY_MODE; then
        echo ""
        echo -e "  ${YELLOW}${BOLD}[PRIVACY MODE]${RESET} Sensitive context loading disabled."
        echo ""
    fi

    step_env
    step_session
    step_transcripts

    if $IS_SOLO && ! $QUICK; then
        step_index
        step_health
        step_integrations
        step_evolution
    elif $QUICK; then
        step_index
        step_health
        info ""
        info "Quick mode. Skipped integrations and evolution check."
    else
        info ""
        info "Multi-session mode. Skipped index rebuild and data pulls."
        info "Read todo.md and latest context to get started."
    fi

    # Summary
    echo ""
    echo "────────────────────────────────────────────────────────────"
    if [[ $FAILURES -gt 0 ]]; then
        echo -e "  ${RED}${FAILURES} failure(s)${RESET}, ${YELLOW}${WARNINGS} warning(s)${RESET}"
        exit 2
    elif [[ $WARNINGS -gt 0 ]]; then
        echo -e "  ${GREEN}Startup complete${RESET} with ${YELLOW}${WARNINGS} warning(s)${RESET}"
        exit 1
    else
        echo -e "  ${GREEN}Startup complete. All checks passed.${RESET}"
        exit 0
    fi
}

main "$@"
