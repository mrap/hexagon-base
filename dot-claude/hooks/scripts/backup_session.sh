#!/bin/bash
# Backup current Claude Code session .jsonl to the agent's raw/transcripts/
# Called by hooks on UserPromptSubmit and Stop
# Works on both macOS and Linux

set -uo pipefail

PROJECTS_DIR="$HOME/.claude/projects"

# Resolve agent root from script location (tools/hooks/scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$SCRIPT_DIR" == */tools/hooks/scripts ]]; then
    AGENT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
elif [[ "$SCRIPT_DIR" == */hooks/scripts ]]; then
    AGENT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
else
    AGENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
BACKUP_DIR="$AGENT_DIR/raw/transcripts"

mkdir -p "$BACKUP_DIR"

# Find the most recently modified .jsonl across all project directories
if [[ "$OSTYPE" == "darwin"* ]]; then
    LATEST=$(find "$PROJECTS_DIR" -maxdepth 2 -name "*.jsonl" -exec stat -f '%m %N' {} \; 2>/dev/null \
        | sort -rn | head -1 | cut -d' ' -f2-)
else
    LATEST=$(find "$PROJECTS_DIR" -maxdepth 2 -name "*.jsonl" -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | head -1 | cut -d' ' -f2-)
fi

if [ -n "${LATEST:-}" ]; then
    FILENAME=$(basename "$LATEST")
    cp "$LATEST" "$BACKUP_DIR/$FILENAME" 2>/dev/null || true
fi
