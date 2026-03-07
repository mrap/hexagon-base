#!/bin/bash
# workspace.sh — Launch hexagon workspace: Claude Code + landings dashboard
#
# Usage:
#   bash workspace.sh           # Launch workspace
#   alias hex='bash /path/to/workspace.sh'   # Add to .bashrc/.zshrc
#
# Behavior:
#   Not in tmux  → Creates tmux session "hex", splits panes, launches both
#   In tmux      → Splits current window, launches dashboard in right pane
#   Session exists → Attaches to existing "hex" session

# ─── Resolve agent directory ────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
candidate="$SCRIPT_DIR"
while [ "$candidate" != "/" ]; do
  if [ -f "$candidate/CLAUDE.md" ]; then
    AGENT_DIR="$candidate"
    break
  fi
  candidate="$(dirname "$candidate")"
done

if [ -z "${AGENT_DIR:-}" ]; then
  echo "Error: Could not find CLAUDE.md. Run this from your hexagon directory."
  exit 1
fi

DASHBOARD="$AGENT_DIR/.claude/scripts/landings-dashboard.sh"
SESSION_NAME="hex"
DASH_WIDTH="20%"

# ─── Already in the hex session? ────────────────────────────────────────────
if [ -n "${TMUX:-}" ]; then
  CURRENT_SESSION=$(tmux display-message -p '#S')
  if [ "$CURRENT_SESSION" = "$SESSION_NAME" ]; then
    # Already in hex session. Check if dashboard pane exists.
    PANE_COUNT=$(tmux list-panes | wc -l | tr -d ' ')
    if [ "$PANE_COUNT" -eq 1 ]; then
      # Split and launch dashboard
      tmux split-window -h -l "$DASH_WIDTH" "AGENT_DIR='$AGENT_DIR' bash '$DASHBOARD' --watch"
      tmux select-pane -L
    fi
    # If claude isn't running in the main pane, start it
    exit 0
  fi
fi

# ─── Tmux session already exists? Attach to it. ────────────────────────────
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  if [ -n "${TMUX:-}" ]; then
    tmux switch-client -t "$SESSION_NAME"
  else
    exec tmux attach-session -t "$SESSION_NAME"
  fi
  exit 0
fi

# ─── Create new tmux session ────────────────────────────────────────────────
# Start session with claude in the main pane
tmux new-session -d -s "$SESSION_NAME" -c "$AGENT_DIR" "claude '/hex-startup'"

# Split right pane for dashboard
tmux split-window -h -t "$SESSION_NAME" -l "$DASH_WIDTH" -c "$AGENT_DIR" \
  "AGENT_DIR='$AGENT_DIR' bash '$DASHBOARD' --watch"

# Focus the main (left) pane
tmux select-pane -t "$SESSION_NAME:0.0"

# Attach
if [ -n "${TMUX:-}" ]; then
  tmux switch-client -t "$SESSION_NAME"
else
  exec tmux attach-session -t "$SESSION_NAME"
fi
