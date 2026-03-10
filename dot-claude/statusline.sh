#!/bin/bash
# Hexagon statusline — context, cost, mission
input=$(cat)

AGENT_DIR="${AGENT_DIR:-$(pwd)}"
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')

# Context color: green < 50%, yellow 50-80%, red > 80%
if [ "$PCT" -gt 80 ] 2>/dev/null; then
  CTX_COLOR="\033[31m"
elif [ "$PCT" -gt 50 ] 2>/dev/null; then
  CTX_COLOR="\033[33m"
else
  CTX_COLOR="\033[32m"
fi
RESET="\033[0m"
DIM="\033[2m"

COST_FMT=$(printf "%.2f" "$COST" 2>/dev/null || echo "0.00")

# Current mission from .claude/mission
MISSION=""
if [ -f "$AGENT_DIR/.claude/mission" ]; then
  MISSION=$(head -1 "$AGENT_DIR/.claude/mission")
fi

if [ -n "$MISSION" ]; then
  printf "${CTX_COLOR}${PCT}%%${RESET}  ${DIM}\$${COST_FMT}${RESET}  |  ${MISSION}"
else
  printf "${CTX_COLOR}${PCT}%%${RESET}  ${DIM}\$${COST_FMT}${RESET}"
fi
