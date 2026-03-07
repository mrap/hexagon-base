#!/bin/bash
# upgrade.sh — Pull latest hexagon-base and upgrade local installation
#
# Upgrades: scripts, skills, commands, hooks, settings.json
# Preserves: memory.db, settings.local.json, user data, CLAUDE.md
#
# Usage:
#   upgrade.sh                  # Upgrade from configured repo
#   upgrade.sh --dry-run        # Show what would change without applying
#   upgrade.sh --repo URL       # Override repo URL
#   upgrade.sh --local PATH     # Use a local hexagon-base checkout

set -uo pipefail

# ─── Resolve paths ───────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLAUDE_DIR="$AGENT_DIR/.claude"
CACHE_DIR="$CLAUDE_DIR/.upgrade-cache"
CONFIG_FILE="$CLAUDE_DIR/upgrade.json"

# Colors
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# Defaults
DEFAULT_REPO="https://github.com/mrap/hexagon-base.git"
DRY_RUN=false
LOCAL_PATH=""
REPO_URL=""

# ─── Helpers ─────────────────────────────────────────────────────────────────
pass()   { echo -e "  [${GREEN}OK${RESET}] $1"; }
warn()   { echo -e "  [${YELLOW}WARN${RESET}] $1"; }
fail()   { echo -e "  [${RED}FAIL${RESET}] $1"; }
info()   { echo -e "  ${DIM}→${RESET} $1"; }
header() { echo -e "\n${BOLD}$1${RESET}"; }

# ─── Parse arguments ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)  DRY_RUN=true; shift ;;
    --repo)     REPO_URL="${2:-}"; shift 2 ;;
    --local)    LOCAL_PATH="${2:-}"; shift 2 ;;
    --help|-h)
      echo "Usage: upgrade.sh [--dry-run] [--repo URL] [--local PATH]"
      echo ""
      echo "Options:"
      echo "  --dry-run    Show what would change without applying"
      echo "  --repo URL   Override repo URL"
      echo "  --local PATH Use a local hexagon-base checkout"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ─── Load config ────────────────────────────────────────────────────────────
if [ -z "$REPO_URL" ] && [ -f "$CONFIG_FILE" ]; then
  REPO_URL=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('repo', ''))" 2>/dev/null || echo "")
fi
REPO_URL="${REPO_URL:-$DEFAULT_REPO}"

echo ""
echo "════════════════════════════════════════════════════"
echo " Hexagon Upgrade — $(date '+%Y-%m-%d %H:%M')"
echo "════════════════════════════════════════════════════"
if $DRY_RUN; then
  echo -e "  ${YELLOW}${BOLD}[DRY RUN]${RESET} No changes will be made."
fi
echo ""

# ─── Step 1: Get latest source ──────────────────────────────────────────────
header "1. Get Latest Source"

SOURCE_DIR=""

if [ -n "$LOCAL_PATH" ]; then
  # Use local checkout
  if [ ! -d "$LOCAL_PATH/dot-claude" ]; then
    fail "No dot-claude/ directory at $LOCAL_PATH"
    exit 1
  fi
  SOURCE_DIR="$LOCAL_PATH"
  pass "Using local checkout: $LOCAL_PATH"
else
  # Clone or pull from remote
  if [ -d "$CACHE_DIR/.git" ]; then
    info "Pulling latest from $REPO_URL"
    PULL_OUT=$(cd "$CACHE_DIR" && git pull --ff-only 2>&1) || {
      warn "Fast-forward pull failed. Re-cloning."
      rm -rf "$CACHE_DIR"
    }
    if [ -d "$CACHE_DIR/.git" ]; then
      if echo "$PULL_OUT" | grep -q "Already up to date"; then
        info "Already up to date"
      else
        info "$PULL_OUT"
      fi
    fi
  fi

  if [ ! -d "$CACHE_DIR/.git" ]; then
    info "Cloning $REPO_URL"
    git clone --depth 1 "$REPO_URL" "$CACHE_DIR" 2>&1 | while read -r line; do
      info "$line"
    done
    if [ ! -d "$CACHE_DIR/dot-claude" ]; then
      fail "Clone succeeded but no dot-claude/ found. Wrong repo?"
      exit 1
    fi
  fi

  SOURCE_DIR="$CACHE_DIR"
  pass "Source ready"
fi

# ─── Step 2: Detect what will change ────────────────────────────────────────
header "2. Detect Changes"

# Build list of files that would be updated
CHANGED=0
NEW=0
UNCHANGED=0
CHANGES_LOG=""

# Compare dot-claude/ contents against .claude/
while IFS= read -r src_file; do
  rel_path="${src_file#$SOURCE_DIR/dot-claude/}"

  # Skip files we preserve
  case "$rel_path" in
    settings.local.json) continue ;;
    __pycache__/*) continue ;;
  esac

  dst_file="$CLAUDE_DIR/$rel_path"

  if [ ! -f "$dst_file" ]; then
    NEW=$((NEW + 1))
    CHANGES_LOG="${CHANGES_LOG}  + ${rel_path}\n"
  elif ! diff -q "$src_file" "$dst_file" > /dev/null 2>&1; then
    CHANGED=$((CHANGED + 1))
    CHANGES_LOG="${CHANGES_LOG}  ~ ${rel_path}\n"
  else
    UNCHANGED=$((UNCHANGED + 1))
  fi
done < <(find "$SOURCE_DIR/dot-claude" -type f ! -path "*/__pycache__/*")

info "$CHANGED changed, $NEW new, $UNCHANGED unchanged"

if [ -n "$CHANGES_LOG" ]; then
  echo -e "$CHANGES_LOG"
fi

# Check CLAUDE.md template changes
TEMPLATE_CHANGED=false
if [ -f "$SOURCE_DIR/templates/CLAUDE.md.template" ]; then
  if [ -f "$CACHE_DIR/.last-template-hash" ]; then
    OLD_HASH=$(cat "$CACHE_DIR/.last-template-hash")
    NEW_HASH=$(sha256sum "$SOURCE_DIR/templates/CLAUDE.md.template" | cut -d' ' -f1)
    if [ "$OLD_HASH" != "$NEW_HASH" ]; then
      TEMPLATE_CHANGED=true
      info "CLAUDE.md template has changed"
    fi
  else
    TEMPLATE_CHANGED=true
  fi
fi

if [ "$CHANGED" -eq 0 ] && [ "$NEW" -eq 0 ] && [ "$TEMPLATE_CHANGED" = false ]; then
  pass "Everything is up to date. Nothing to do."
  exit 0
fi

# ─── Step 3: Apply changes ──────────────────────────────────────────────────
if $DRY_RUN; then
  header "3. Dry Run Complete"
  info "Run without --dry-run to apply changes."
  if $TEMPLATE_CHANGED; then
    info "CLAUDE.md template changed — agent will merge on next upgrade."
  fi
  exit 0
fi

header "3. Apply Changes"

# Backup changed files
if [ "$CHANGED" -gt 0 ]; then
  BACKUP_DIR="$CLAUDE_DIR/.upgrade-backup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUP_DIR"

  while IFS= read -r src_file; do
    rel_path="${src_file#$SOURCE_DIR/dot-claude/}"
    case "$rel_path" in
      settings.local.json|__pycache__/*) continue ;;
    esac
    dst_file="$CLAUDE_DIR/$rel_path"
    if [ -f "$dst_file" ] && ! diff -q "$src_file" "$dst_file" > /dev/null 2>&1; then
      backup_path="$BACKUP_DIR/$rel_path"
      mkdir -p "$(dirname "$backup_path")"
      cp "$dst_file" "$backup_path"
    fi
  done < <(find "$SOURCE_DIR/dot-claude" -type f ! -path "*/__pycache__/*")

  info "Backed up $CHANGED file(s) to ${BACKUP_DIR##*/}"
fi

# Copy files
rsync -a \
  --exclude='memory.db' \
  --exclude='memory.db-wal' \
  --exclude='memory.db-shm' \
  --exclude='settings.local.json' \
  --exclude='__pycache__' \
  --exclude='.upgrade-*' \
  "$SOURCE_DIR/dot-claude/" "$CLAUDE_DIR/"

# Make scripts executable
find "$CLAUDE_DIR" -name "*.sh" -type f -exec chmod +x {} +

pass "Applied $((CHANGED + NEW)) file(s)"

# Store template hash for next upgrade
if [ -f "$SOURCE_DIR/templates/CLAUDE.md.template" ]; then
  mkdir -p "$CACHE_DIR"
  sha256sum "$SOURCE_DIR/templates/CLAUDE.md.template" | cut -d' ' -f1 > "$CACHE_DIR/.last-template-hash"
fi

# ─── Step 4: Summary ────────────────────────────────────────────────────────
header "4. Summary"

echo -e "  Files updated:  $CHANGED"
echo -e "  Files added:    $NEW"

if $TEMPLATE_CHANGED; then
  echo ""
  echo -e "  ${YELLOW}CLAUDE.md template has changed.${RESET}"
  echo -e "  The agent will merge updates into your CLAUDE.md."
  echo -e "  Template saved at: $SOURCE_DIR/templates/CLAUDE.md.template"
fi

echo ""
echo -e "  ${GREEN}Upgrade complete.${RESET}"
echo ""
