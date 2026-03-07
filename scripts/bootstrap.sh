#!/bin/bash
# Hexagon Base — Bootstrap a personal AI agent workspace
#
# Usage:
#   bash bootstrap.sh                       # Interactive
#   bash bootstrap.sh --agent myagent       # Non-interactive with agent name
#   bash bootstrap.sh --path /custom/path   # Custom install location
#
# Auto-detects your name from the system.
# Only asks one question: what to name your agent.

set -euo pipefail

# --- Resolve script directory ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES_DIR="$SKILL_DIR/templates"
DOT_CLAUDE_DIR="$SKILL_DIR/dot-claude"

# --- Helpers ---
info()  { echo "  $1"; }
warn()  { echo "  WARNING: $1"; }
error() { echo "  ERROR: $1" >&2; exit 1; }

# --- Auto-detect name ---
UNIXNAME=$(whoami)

if [[ "$OSTYPE" == darwin* ]]; then
  NAME=$(id -F 2>/dev/null || echo "")
else
  NAME=$(getent passwd "$UNIXNAME" 2>/dev/null | cut -d: -f5 | cut -d, -f1 || echo "")
fi

# Fallback: capitalize unixname
if [ -z "${NAME:-}" ]; then
  NAME="$UNIXNAME"
fi

# --- Parse arguments ---
AGENT=""
CUSTOM_PATH=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --agent) [[ $# -ge 2 ]] || error "--agent requires a value"; AGENT="$2"; shift 2 ;;
    --name) [[ $# -ge 2 ]] || error "--name requires a value"; NAME="$2"; shift 2 ;;
    --path) [[ $# -ge 2 ]] || error "--path requires a value"; CUSTOM_PATH="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: bootstrap.sh [--agent name] [--name 'Full Name'] [--path /install/path]"
      echo ""
      echo "Options:"
      echo "  --agent    Agent folder name (e.g., atlas, friday)"
      echo "  --name     Override auto-detected full name"
      echo "  --path     Install path (default: ~/<agent-name>)"
      echo ""
      echo "Auto-detects your full name from the system."
      echo "If --agent is not provided, you'll be prompted."
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# --- Prompt for agent name if not provided ---
if [ -z "$AGENT" ]; then
  SUGGESTED=$(echo "$NAME" | awk '{print tolower($1)}')
  echo ""
  echo "What do you want to name your agent?"
  read -rp "Agent name [${SUGGESTED}]: " AGENT
  AGENT="${AGENT:-$SUGGESTED}"
fi

if [ -z "$AGENT" ]; then
  error "Agent name is required."
fi

# --- Determine install directory ---
if [ -z "$CUSTOM_PATH" ]; then
  CUSTOM_PATH="$HOME/$AGENT"
fi

AGENT_DIR="${CUSTOM_PATH/#\~/$HOME}"

echo ""
echo "========================================"
echo " Hexagon Base — Bootstrap for $NAME"
echo "========================================"
echo "  Name:     $NAME"
echo "  Agent:    $AGENT"
echo "  Path:     $AGENT_DIR"
echo ""

# --- Check for existing agent ---
if [ -d "$AGENT_DIR" ]; then
  error "Directory already exists at $AGENT_DIR. Remove it first or choose a different agent name."
fi

TODAY=$(date +%Y-%m-%d)

# --- Step 1: Create folder structure ---
echo "[1/5] Creating folder structure..."
mkdir -p "$AGENT_DIR"/.sessions
mkdir -p "$AGENT_DIR"/me/decisions
mkdir -p "$AGENT_DIR"/raw/{transcripts,messages,calendar,docs}
mkdir -p "$AGENT_DIR"/people
mkdir -p "$AGENT_DIR"/projects
mkdir -p "$AGENT_DIR"/evolution
mkdir -p "$AGENT_DIR"/landings/weekly
info "Done."

# --- Step 2: Install .claude/ directory ---
echo "[2/5] Installing .claude/ directory..."

if [ -d "$DOT_CLAUDE_DIR" ]; then
  # Single recursive copy — dot-claude/ becomes .claude/
  # Use rsync to exclude __pycache__ (contains compiled paths from source repo)
  rsync -a --exclude='__pycache__' "$DOT_CLAUDE_DIR/" "$AGENT_DIR/.claude/"

  # Substitute template vars in commands and skills
  find "$AGENT_DIR/.claude" -name "*.md" -type f | while read -r file; do
    if grep -q '{{NAME}}\|{{AGENT}}\|{{DATE}}' "$file" 2>/dev/null; then
      sed -e "s|{{NAME}}|$NAME|g" -e "s|{{AGENT}}|$AGENT|g" -e "s|{{DATE}}|$TODAY|g" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    fi
  done

  # Make scripts executable
  find "$AGENT_DIR/.claude" -name "*.sh" -type f -exec chmod +x {} +

  CMDS=$(ls "$DOT_CLAUDE_DIR/commands/"*.md 2>/dev/null | xargs -n1 basename | sed 's/.md//' | tr '\n' ', ' | sed 's/,$//')
  info "Installed commands: $CMDS"
  info "Installed skills, hooks, scripts, and settings"
fi

# --- Step 3: Generate CLAUDE.md from template ---
echo "[3/5] Generating CLAUDE.md..."
if [ -f "$TEMPLATES_DIR/CLAUDE.md.template" ]; then
  sed -e "s|{{NAME}}|$NAME|g" \
      -e "s|{{AGENT}}|$AGENT|g" \
      -e "s|{{DATE}}|$TODAY|g" \
      "$TEMPLATES_DIR/CLAUDE.md.template" > "$AGENT_DIR/CLAUDE.md"
  info "Generated CLAUDE.md for $NAME."
else
  warn "CLAUDE.md.template not found at $TEMPLATES_DIR. Skipping."
fi

# --- Step 4: Create skeleton files ---
echo "[4/5] Creating skeleton files..."

# todo.md
if [ -f "$TEMPLATES_DIR/todo.md.template" ]; then
  TARGET="$AGENT_DIR/todo.md"
  if [ ! -f "$TARGET" ]; then
    sed -e "s|{{NAME}}|$NAME|g" \
        -e "s|{{AGENT}}|$AGENT|g" \
        -e "s|{{DATE}}|$TODAY|g" \
        "$TEMPLATES_DIR/todo.md.template" > "$TARGET"
    info "Created todo.md"
  else
    info "todo.md already exists. Skipping."
  fi
fi

# me.md
if [ -f "$TEMPLATES_DIR/me.md.template" ]; then
  TARGET="$AGENT_DIR/me/me.md"
  if [ ! -f "$TARGET" ]; then
    sed -e "s|{{NAME}}|$NAME|g" \
        -e "s|{{AGENT}}|$AGENT|g" \
        -e "s|{{DATE}}|$TODAY|g" \
        "$TEMPLATES_DIR/me.md.template" > "$TARGET"
    info "Created me/me.md"
  else
    info "me/me.md already exists. Skipping."
  fi
fi

# learnings.md
if [ ! -f "$AGENT_DIR/me/learnings.md" ]; then
  cat > "$AGENT_DIR/me/learnings.md" <<LEARN
# Learnings — $NAME

_Observations about how $NAME works, communicates, and makes decisions._
_Updated every session with new patterns._

## Session 1 — $TODAY

_(First session. Observations will be added as we work together.)_
LEARN
  info "Created me/learnings.md"
fi

# teams.json
if [ ! -f "$AGENT_DIR/teams.json" ]; then
  cat > "$AGENT_DIR/teams.json" <<'TEAMS'
{
  "teams": {}
}
TEAMS
  info "Created teams.json"
fi

# Evolution files
for efile in observations.md suggestions.md changelog.md metrics.md; do
  TARGET="$AGENT_DIR/evolution/$efile"
  if [ ! -f "$TARGET" ]; then
    TITLE=$(echo "$efile" | sed 's/\.md$//')
    TITLE="$(echo "${TITLE:0:1}" | tr '[:lower:]' '[:upper:]')${TITLE:1}"
    cat > "$TARGET" <<EVOFILE
# ${TITLE}

_Part of the improvement engine. See CLAUDE.md for the protocol._
EVOFILE
  fi
done
info "Created evolution/ files"

info "Done."

# --- Step 5: Verify ---
echo "[5/5] Verifying..."
MISSING=""
for f in CLAUDE.md todo.md me/me.md me/learnings.md teams.json .claude/settings.json; do
  if [ ! -f "$AGENT_DIR/$f" ]; then
    MISSING="$MISSING  - $f\n"
  fi
done

# Check that commands were installed
CMD_COUNT=$(ls "$AGENT_DIR/.claude/commands/"*.md 2>/dev/null | wc -l)
if [ "$CMD_COUNT" -eq 0 ]; then
  MISSING="$MISSING  - .claude/commands/ (no commands)\n"
fi

if [ -n "$MISSING" ]; then
  warn "Some files are missing:"
  echo -e "$MISSING"
else
  info "All core files present. $CMD_COUNT commands installed."
fi

# --- Summary ---
echo ""
echo "========================================"
echo " Setup Complete!"
echo "========================================"
echo ""
echo "  Agent:     $AGENT_DIR"
echo ""
echo "  Components:"
echo "    Commands: /hex-startup, /hex-save, /hex-shutdown, /hex-sync, /hex-create-team, /hex-connect-team, /hex-context-sync, /context-save"
echo "    Skills:   memory (search, index, health), landings (daily + weekly)"
echo "    Scripts:  landings-dashboard.sh (tmux pane)"
echo "    Hooks:    transcript backup on every prompt + session end"
echo ""
echo "  Next steps:"
echo ""
echo "    cd \"$AGENT_DIR\" && claude"
echo ""
echo "  Then run /hex-startup. Your agent will ask 3 quick questions"
echo "  to get started, then you're off."
echo ""
