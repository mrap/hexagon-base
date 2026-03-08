#!/usr/bin/env bash
# hex-notify — send a push notification via ntfy.sh
# Usage: hex-notify "title" "message" [priority]
# Priority: 1 (min) to 5 (max), default 3
set -uo pipefail

CONFIG_FILE="${HOME}/.config/hex/notifications.yaml"

# --- Parse args ---
TITLE="${1:-}"
MESSAGE="${2:-}"
PRIORITY="${3:-3}"

if [[ -z "$TITLE" || -z "$MESSAGE" ]]; then
    echo "Usage: hex-notify <title> <message> [priority]" >&2
    exit 1
fi

if [[ "$PRIORITY" -lt 1 || "$PRIORITY" -gt 5 ]] 2>/dev/null; then
    echo "Priority must be 1-5, got: $PRIORITY" >&2
    exit 1
fi

# --- Read config ---
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: ntfy config not found at $CONFIG_FILE" >&2
    exit 1
fi

TOPIC=""
SERVER=""
while IFS= read -r line; do
    # Strip leading/trailing whitespace
    trimmed="${line#"${line%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"

    case "$trimmed" in
        topic:*)
            val="${trimmed#topic:}"
            val="${val#"${val%%[![:space:]]*}"}"
            val="${val%\"}"
            val="${val#\"}"
            TOPIC="$val"
            ;;
        server:*)
            val="${trimmed#server:}"
            val="${val#"${val%%[![:space:]]*}"}"
            val="${val%\"}"
            val="${val#\"}"
            val="${val%/}"
            SERVER="$val"
            ;;
    esac
done < "$CONFIG_FILE"

if [[ -z "$TOPIC" || -z "$SERVER" ]]; then
    echo "Error: ntfy config missing topic or server" >&2
    exit 1
fi

# --- Send notification ---
URL="${SERVER}/${TOPIC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Title: ${TITLE}" \
    -H "Priority: ${PRIORITY}" \
    -d "${MESSAGE}" \
    "$URL" 2>/dev/null) || true

if [[ "$HTTP_CODE" == "200" ]]; then
    exit 0
else
    echo "Error: ntfy returned HTTP $HTTP_CODE" >&2
    exit 1
fi
