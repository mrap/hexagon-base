#!/bin/bash
# Returns today's date in the user's configured timezone.
# Use this ALWAYS when creating date-stamped files (landings, meetings, etc.)
# Usage: $(bash $AGENT_DIR/.claude/scripts/today.sh)
#   or:  $(bash $AGENT_DIR/.claude/scripts/today.sh +%a)  # day name

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_DIR="${AGENT_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

if [ -f "$AGENT_DIR/.claude/timezone" ]; then
  export TZ="$(cat "$AGENT_DIR/.claude/timezone" | tr -d '[:space:]')"
fi

if [ -n "$1" ]; then
  date "$1"
else
  date +%Y-%m-%d
fi
