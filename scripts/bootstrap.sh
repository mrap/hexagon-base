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
PLUGIN_DIR="$SKILL_DIR/plugin"

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
      echo "  --path     Install path (default: ~/hexagon)"
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

# --- Ask for install location if not provided ---
DEFAULT_PATH="$HOME/hexagon"

if [ -z "$CUSTOM_PATH" ] && [ -t 0 ]; then
  echo ""
  read -rp "Where do you want to install? [${DEFAULT_PATH}]: " CUSTOM_PATH
fi

if [ -n "$CUSTOM_PATH" ]; then
  INSTALL_DIR="${CUSTOM_PATH/#\~/$HOME}"
else
  INSTALL_DIR="$DEFAULT_PATH"
fi

AGENT_DIR="$INSTALL_DIR/$AGENT"

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
echo "[1/7] Creating folder structure..."
mkdir -p "$AGENT_DIR"/{.claude-plugin,.sessions}
mkdir -p "$AGENT_DIR"/me/decisions
mkdir -p "$AGENT_DIR"/raw/{transcripts,messages,calendar,docs}
mkdir -p "$AGENT_DIR"/people
mkdir -p "$AGENT_DIR"/projects
mkdir -p "$AGENT_DIR"/evolution
mkdir -p "$AGENT_DIR"/landings
mkdir -p "$AGENT_DIR"/tools/{scripts,skills/memory/{scripts,references},commands,hooks/scripts,templates}
info "Done."

# --- Step 2: Create plugin manifest ---
echo "[2/7] Creating plugin manifest..."
cat > "$AGENT_DIR/.claude-plugin/plugin.json" <<PLUGIN
{
  "name": "${AGENT}-agent",
  "version": "1.0.0",
  "description": "Personal AI agent for ${NAME}",
  "skills": ["./tools/skills/"],
  "commands": ["./tools/commands/"],
  "hooks": {
    "UserPromptSubmit": [
      {
        "type": "command",
        "command": "bash \${CLAUDE_PLUGIN_ROOT}/tools/hooks/scripts/backup_session.sh"
      }
    ],
    "Stop": [
      {
        "type": "command",
        "command": "bash \${CLAUDE_PLUGIN_ROOT}/tools/hooks/scripts/backup_session.sh"
      }
    ]
  }
}
PLUGIN
info "Created .claude-plugin/plugin.json"

# --- Step 3: Install plugin components ---
echo "[3/7] Installing plugin components..."

# Skills: memory system
if [ -d "$PLUGIN_DIR/skills/memory" ]; then
  cp "$PLUGIN_DIR/skills/memory/SKILL.md" "$AGENT_DIR/tools/skills/memory/" 2>/dev/null || true
  cp "$PLUGIN_DIR/skills/memory/scripts/"*.py "$AGENT_DIR/tools/skills/memory/scripts/" 2>/dev/null || true
  if [ -d "$PLUGIN_DIR/skills/memory/references" ]; then
    cp "$PLUGIN_DIR/skills/memory/references/"*.md "$AGENT_DIR/tools/skills/memory/references/" 2>/dev/null || true
  fi
  info "Installed memory skill"
fi

# Commands
if [ -d "$PLUGIN_DIR/commands" ]; then
  cp "$PLUGIN_DIR/commands/"*.md "$AGENT_DIR/tools/commands/" 2>/dev/null || true
  CMDS=$(ls "$PLUGIN_DIR/commands/"*.md 2>/dev/null | xargs -n1 basename | sed 's/.md//' | tr '\n' ', ' | sed 's/,$//')
  info "Installed commands: $CMDS"
fi

# Hooks
if [ -d "$PLUGIN_DIR/hooks" ]; then
  # hooks.json is not copied — plugin.json is the authoritative hook manifest
  if ls "$PLUGIN_DIR/hooks/scripts/"*.sh 1>/dev/null 2>&1; then
    cp "$PLUGIN_DIR/hooks/scripts/"*.sh "$AGENT_DIR/tools/hooks/scripts/"
    chmod +x "$AGENT_DIR/tools/hooks/scripts/"*.sh
  fi
  info "Installed hooks"
fi

# Core scripts
if [ -d "$PLUGIN_DIR/scripts" ]; then
  cp "$PLUGIN_DIR/scripts/"*.sh "$AGENT_DIR/tools/scripts/" 2>/dev/null || true
  cp "$PLUGIN_DIR/scripts/"*.py "$AGENT_DIR/tools/scripts/" 2>/dev/null || true
  chmod +x "$AGENT_DIR/tools/scripts/"*.sh 2>/dev/null || true
  info "Installed scripts"
fi

info "Done."

# --- Step 4: Generate CLAUDE.md from template ---
echo "[4/7] Generating CLAUDE.md..."
if [ -f "$TEMPLATES_DIR/CLAUDE.md.template" ]; then
  sed -e "s|{{NAME}}|$NAME|g" \
      -e "s|{{AGENT}}|$AGENT|g" \
      -e "s|{{DATE}}|$TODAY|g" \
      "$TEMPLATES_DIR/CLAUDE.md.template" > "$AGENT_DIR/CLAUDE.md"
  info "Generated CLAUDE.md for $NAME."
else
  warn "CLAUDE.md.template not found at $TEMPLATES_DIR. Skipping."
fi

# --- Step 5: Create skeleton files ---
echo "[5/7] Creating skeleton files..."

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

# --- Step 6: Link plugin for auto-discovery ---
echo "[6/7] Linking plugin..."
PLUGIN_LINK="$HOME/.claude/plugins/hexagon-${AGENT}"
mkdir -p "$HOME/.claude/plugins"

if [ -L "$PLUGIN_LINK" ]; then
  rm "$PLUGIN_LINK"
fi

ln -sf "$AGENT_DIR" "$PLUGIN_LINK"
info "Linked $AGENT_DIR -> $PLUGIN_LINK"

# --- Step 7: Verify ---
echo "[7/7] Verifying..."
MISSING=""
for f in CLAUDE.md todo.md me/me.md me/learnings.md teams.json .claude-plugin/plugin.json; do
  if [ ! -f "$AGENT_DIR/$f" ]; then
    MISSING="$MISSING  - $f\n"
  fi
done

if [ -n "$MISSING" ]; then
  warn "Some files are missing:"
  echo -e "$MISSING"
else
  info "All core files present."
fi

# --- Summary ---
echo ""
echo "========================================"
echo " Setup Complete!"
echo "========================================"
echo ""
echo "  Agent:     $AGENT_DIR"
echo "  Plugin:    ${AGENT}-agent v1.0.0"
echo "  Linked:    $PLUGIN_LINK"
echo ""
echo "  Components:"
echo "    Skills:   memory (search, index, health)"
echo "    Commands: /hex-startup, /hex-save, /hex-shutdown, /hex-sync, /hex-create-team, /hex-connect-team, /context-save"
echo "    Hooks:    transcript backup on every prompt + session end"
echo ""
echo "  Next steps:"
echo ""
echo "    cd \"$AGENT_DIR\" && claude"
echo ""
echo "  Then run /hex-startup. Your agent will ask 3 quick questions"
echo "  to get started, then you're off."
echo ""
