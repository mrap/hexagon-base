#!/bin/bash
# session-reflect.sh — Post-session reflection hook
# Extracts corrections, preferences, decisions, and friction from session transcripts.
# Runs as a Claude Code Stop hook after backup_session.sh.
#
# Flow:
#   1. Parse .jsonl transcripts to markdown (if needed)
#   2. Read today's transcript
#   3. Call claude -p to extract patterns
#   4. Save reflection to raw/reflections/YYYY-MM-DD.md
#
# Does NOT auto-append to learnings.md or evolution DB.
# Use promote-learnings.py separately for pattern promotion with human review.
#
# Part of the Hexagon system.
set -uo pipefail

# Resolve agent root from script location (.claude/scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$SCRIPT_DIR" == */.claude/scripts ]]; then
    AGENT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
else
    AGENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

# Use .claude/timezone if available, otherwise system default
TZ_FILE="$AGENT_DIR/.claude/timezone"
if [ -f "$TZ_FILE" ]; then
    AGENT_TZ="$(cat "$TZ_FILE" | tr -d '[:space:]')"
    TODAY="$(TZ="$AGENT_TZ" date +%Y-%m-%d)"
else
    TODAY="$(date +%Y-%m-%d)"
fi
TRANSCRIPT_DIR="$AGENT_DIR/raw/transcripts"
REFLECTIONS_DIR="$AGENT_DIR/raw/reflections"
LOG_FILE="$REFLECTIONS_DIR/.session-reflect.log"
MAX_TRANSCRIPT_BYTES=8000
MAX_USER_MESSAGES=100

mkdir -p "$REFLECTIONS_DIR"

# Log rotation: cap total log usage at ~200KB (current + one backup)
if [ -f "$LOG_FILE" ]; then
    LOG_SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$LOG_SIZE" -gt 102400 ]; then
        rm -f "${LOG_FILE}.old"
        mv "$LOG_FILE" "${LOG_FILE}.old"
    fi
fi

log() {
    echo "[session-reflect $(date +%H:%M:%S)] $*" >> "$LOG_FILE" 2>/dev/null
}

log "=== Starting reflection for $TODAY ==="

# Skip non-interactive sessions
# 1. BOI workers
if [ -n "${BOI_QUEUE_ID:-}" ] || [ -n "${BOI_WORKER:-}" ]; then
    log "BOI worker session, skipping."
    exit 0
fi
# 2. Subagents (Task tool spawns)
if [ -n "${CLAUDE_PARENT_SESSION_ID:-}" ]; then
    log "Subagent session, skipping."
    exit 0
fi
# 3. Non-interactive sessions (claude -p, headless)
if [ "${CLAUDE_NON_INTERACTIVE:-}" = "1" ] || [ -n "${CLAUDE_PROMPT:-}" ]; then
    log "Non-interactive session, skipping."
    exit 0
fi
# 4. Short sessions — check if transcript has enough user messages to be worth reflecting on
# We check this after finding the transcript (below), but gate on session env first
if [ -n "${CLAUDE_SESSION_ID:-}" ]; then
    # Find this session's .jsonl and check message count
    # Derive project sessions dir from cwd: /Users/me/myproject -> -Users-me-myproject
    _PROJECT_DIR_HASH=$(pwd | sed 's|/|-|g')
    SESSION_JSONL="$HOME/.claude/projects/${_PROJECT_DIR_HASH}/${CLAUDE_SESSION_ID}.jsonl"
    if [ -f "$SESSION_JSONL" ]; then
        MSG_COUNT=$(grep -c '"type":"human"' "$SESSION_JSONL" 2>/dev/null || echo 0)
        if [ "$MSG_COUNT" -lt 3 ]; then
            log "Short session ($MSG_COUNT user messages), skipping."
            exit 0
        fi
        log "Session has $MSG_COUNT user messages, proceeding."
    fi
fi

# Lockfile to prevent concurrent execution (multiple sessions ending at once)
LOCKFILE="$REFLECTIONS_DIR/.session-reflect.lock"
if [ -f "$LOCKFILE" ]; then
    LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$LOCKFILE" 2>/dev/null || echo 0) ))
    if [ "$LOCK_AGE" -lt 120 ]; then
        log "Another instance is running (lock age: ${LOCK_AGE}s), skipping."
        exit 0
    fi
    log "Stale lockfile (${LOCK_AGE}s old), removing."
    rm -f "$LOCKFILE"
fi
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

# Bail early if claude is not available
if ! command -v claude &>/dev/null; then
    log "claude CLI not found, skipping."
    exit 0
fi

# Step 1: Parse any new .jsonl transcripts to .md
if [ -f "$AGENT_DIR/.claude/scripts/parse_transcripts.py" ]; then
    python3 "$AGENT_DIR/.claude/scripts/parse_transcripts.py" >> "$LOG_FILE" 2>&1 || true
fi

# Step 2: Find today's transcript
TRANSCRIPT="$TRANSCRIPT_DIR/$TODAY.md"
if [ ! -f "$TRANSCRIPT" ]; then
    log "No transcript for $TODAY, skipping."
    exit 0
fi

# Step 3: Extract last N user messages (not tool outputs) to reduce input size
# User messages in the parsed markdown start with "> " after "**N. User" lines
TRANSCRIPT_CONTENT=$(python3 -c "
import sys
lines = open(sys.argv[1]).readlines()
user_msgs = []
in_user = False
current = []
for line in lines:
    if line.startswith('**') and '. User' in line:
        if current:
            user_msgs.append(''.join(current).strip())
        in_user = True
        current = [line]
    elif in_user and (line.startswith('**Assistant') or line.startswith('*Tools:')):
        if current:
            user_msgs.append(''.join(current).strip())
        in_user = False
        current = []
    elif in_user:
        current.append(line)
if current:
    user_msgs.append(''.join(current).strip())
# Take last N messages, cap total size
limit = int(sys.argv[2])
max_bytes = int(sys.argv[3])
msgs = user_msgs[-limit:]
result = '\n\n---\n\n'.join(msgs)
if len(result) > max_bytes:
    result = result[-max_bytes:]
print(result)
" "$TRANSCRIPT" "$MAX_USER_MESSAGES" "$MAX_TRANSCRIPT_BYTES" 2>/dev/null) || {
    log "Failed to extract user messages, falling back to tail"
    TRANSCRIPT_CONTENT="$(tail -c "$MAX_TRANSCRIPT_BYTES" "$TRANSCRIPT")"
}

if [ -z "$TRANSCRIPT_CONTENT" ]; then
    log "No user messages found in transcript, skipping."
    exit 0
fi

log "Extracted user messages (${#TRANSCRIPT_CONTENT} chars)"

# Step 4: Build extraction prompt
read -r -d '' EXTRACT_PROMPT << 'PROMPTEOF' || true
You are analyzing a Claude Code session transcript for a developer.

Extract the following categories. Be specific and concise — one line per item.

## Corrections
Things the user corrected the assistant on (wrong approach, bad assumption, style issue).
Format each as: - <what was corrected and the right approach>. (DATE_PLACEHOLDER)

## Preferences
Preferences the user stated or demonstrated (communication, tools, workflow, design).
Format each as: - <preference statement>. (DATE_PLACEHOLDER)

## Decisions
Key decisions the user made (architecture, strategy, priorities, trade-offs).
Format each as: - <decision and reasoning>. (DATE_PLACEHOLDER)

## Friction Points
Workflow friction observed (slow processes, broken tools, manual steps needing automation).
Format each as: - <description> [CATEGORY]
Valid categories: automation-candidate, bug-recurring, architecture-gap, skill-candidate

RULES:
- Only include items clearly stated or demonstrated, not inferred
- If a section has no entries, omit it entirely
- Output ONLY the markdown sections, nothing else
- Be concise — max 2 sentences per item
- Do not include system/hook messages or BOI worker output as user preferences
PROMPTEOF

# Replace date placeholder
EXTRACT_PROMPT="${EXTRACT_PROMPT//DATE_PLACEHOLDER/$TODAY}"

# Combine prompt with transcript
FULL_PROMPT="$EXTRACT_PROMPT

---
SESSION TRANSCRIPT:
$TRANSCRIPT_CONTENT"

# Step 5: Call claude -p with CLAUDE* env vars stripped (timeout 55s)
log "Calling claude -p for reflection (transcript: ${#TRANSCRIPT_CONTENT} chars)..."

# Write prompt to temp file to avoid argument length limits
PROMPT_TMP="$REFLECTIONS_DIR/.prompt.tmp"
printf '%s' "$FULL_PROMPT" > "$PROMPT_TMP"

# Build env command to strip all CLAUDE* vars
UNSET_ARGS=""
for var in $(env | grep '^CLAUDE' | cut -d= -f1); do
    UNSET_ARGS="$UNSET_ARGS -u $var"
done

RESPONSE=""
RESPONSE=$(env $UNSET_ARGS timeout 55 claude -p --model haiku --no-session-persistence < "$PROMPT_TMP" 2>/dev/null) || {
    EXIT_CODE=$?
    log "claude -p failed (exit: $EXIT_CODE)"
    rm -f "$PROMPT_TMP"
    exit 0
}
rm -f "$PROMPT_TMP"

if [ -z "$RESPONSE" ]; then
    log "Empty response from claude, skipping."
    exit 0
fi

RESPONSE_SIZE=${#RESPONSE}
log "Got reflection ($RESPONSE_SIZE chars)"

# Step 6: Save reflection atomically
REFLECTION_TMP="$REFLECTIONS_DIR/${TODAY}.md.tmp"
REFLECTION_FILE="$REFLECTIONS_DIR/${TODAY}.md"

# Append to daily file instead of overwriting
TIMESTAMP=$(date +%H:%M)
if [ -f "$REFLECTION_FILE" ]; then
    cat >> "$REFLECTION_FILE" << EOF

---

## Reflection @ $TIMESTAMP

$RESPONSE
EOF
else
    cat > "$REFLECTION_TMP" << EOF
# Session Reflections — $TODAY

_Auto-generated by session-reflect.sh_

## Reflection @ $TIMESTAMP

$RESPONSE
EOF
    mv "$REFLECTION_TMP" "$REFLECTION_FILE"
fi
log "Saved reflection to $REFLECTION_FILE"

log "=== Reflection complete. Saved to $REFLECTION_FILE ==="
