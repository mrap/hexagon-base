#!/bin/bash
# session.sh — Session registry for multi-session coordination
#
# Usage:
#   session.sh start [focus]   — Register a new session
#   session.sh check           — List active sessions
#   session.sh stop [id]       — Deregister a session (default: this process)
#   session.sh cleanup         — Remove stale sessions (>12h old)

set -uo pipefail

# Resolve agent root from script location (tools/scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$SCRIPT_DIR" == */tools/scripts ]]; then
    AGENT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
else
    AGENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
SESSIONS_DIR="$AGENT_DIR/.sessions"
mkdir -p "$SESSIONS_DIR"
shopt -s nullglob

case "${1:-check}" in
  start)
    FOCUS="${2:-general}"
    SESSION_ID="$(date +%s)_$$"
    PPID_VAL="$PPID"
    cat > "$SESSIONS_DIR/session_${SESSION_ID}.json" <<EOF
{
  "id": "$SESSION_ID",
  "started": "$(date -Iseconds)",
  "focus": "$FOCUS",
  "pid": "$PPID_VAL"
}
EOF
    echo "$SESSION_ID"
    ;;

  check)
    ACTIVE=0
    for f in "$SESSIONS_DIR"/session_*.json; do
      [ -f "$f" ] || continue
      SID=$(grep -o '"id": "[^"]*"' "$f" | cut -d'"' -f4)
      STARTED=$(grep -o '"started": "[^"]*"' "$f" | cut -d'"' -f4)
      FOCUS=$(grep -o '"focus": "[^"]*"' "$f" | cut -d'"' -f4)
      PID=$(grep -o '"pid": "[^"]*"' "$f" | cut -d'"' -f4)

      # Skip stale sessions (>12h)
      if [[ "$OSTYPE" == darwin* ]]; then
        FILE_MOD=$(stat -f %m "$f" 2>/dev/null || echo 0)
      else
        FILE_MOD=$(stat -c %Y "$f" 2>/dev/null || echo 0)
      fi
      FILE_AGE=$(( $(date +%s) - FILE_MOD ))
      if [ "$FILE_AGE" -gt 43200 ]; then
        continue
      fi

      echo "SESSION $SID | focus: $FOCUS | started: $STARTED | pid: $PID"
      ACTIVE=$((ACTIVE + 1))
    done

    if [ "$ACTIVE" -eq 0 ]; then
      echo "No active sessions."
      exit 1
    else
      echo "---"
      echo "$ACTIVE active session(s)."
      exit 0
    fi
    ;;

  stop)
    TARGET="${2:-}"
    REMOVED=false
    if [ -z "$TARGET" ]; then
      for f in "$SESSIONS_DIR"/session_*.json; do
        [ -f "$f" ] || continue
        PID=$(grep -o '"pid": "[^"]*"' "$f" | cut -d'"' -f4)
        if [ "$PID" = "$PPID" ]; then
          rm -f "$f"
          echo "Stopped session (pid match: $PPID)"
          REMOVED=true
          break
        fi
      done
      if [ "$REMOVED" = false ]; then
        echo "No session found for current process. Specify session ID."
        exit 1
      fi
    else
      rm -f "$SESSIONS_DIR/session_${TARGET}.json"
      echo "Stopped session $TARGET"
    fi
    ;;

  cleanup)
    REMOVED=0
    for f in "$SESSIONS_DIR"/session_*.json; do
      [ -f "$f" ] || continue
      if [[ "$OSTYPE" == darwin* ]]; then
        FILE_MOD=$(stat -f %m "$f" 2>/dev/null || echo 0)
      else
        FILE_MOD=$(stat -c %Y "$f" 2>/dev/null || echo 0)
      fi
      FILE_AGE=$(( $(date +%s) - FILE_MOD ))
      if [ "$FILE_AGE" -gt 43200 ]; then
        rm -f "$f"
        REMOVED=$((REMOVED + 1))
      fi
    done
    echo "Cleaned up $REMOVED stale session(s)."

    # Purge old transcripts (keep last 7 days)
    TRANSCRIPTS_DIR="$AGENT_DIR/raw/transcripts"
    if [ -d "$TRANSCRIPTS_DIR" ]; then
      # Process unprocessed transcripts before deleting
      PARSER="$AGENT_DIR/tools/scripts/parse_transcripts.py"
      if [ -f "$PARSER" ]; then
        python3 "$PARSER" 2>/dev/null || true
      fi

      # Delete .jsonl files older than 7 days
      PURGED=0
      CUTOFF=$(( $(date +%s) - 604800 ))
      for f in "$TRANSCRIPTS_DIR"/*.jsonl; do
        [ -f "$f" ] || continue
        if [[ "$OSTYPE" == darwin* ]]; then
          FILE_MOD=$(stat -f %m "$f" 2>/dev/null || echo 0)
        else
          FILE_MOD=$(stat -c %Y "$f" 2>/dev/null || echo 0)
        fi
        if [ "$FILE_MOD" -lt "$CUTOFF" ] 2>/dev/null; then
          rm -f "$f"
          PURGED=$((PURGED + 1))
        fi
      done
      if [ "$PURGED" -gt 0 ]; then
        echo "Purged $PURGED transcript(s) older than 7 days."
      fi
    fi
    ;;

  *)
    echo "Usage: session.sh {start|check|stop|cleanup} [args]"
    exit 1
    ;;
esac
