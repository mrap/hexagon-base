#!/bin/bash
# Run this on your LOCAL machine to access your remote hex UI.
# Usage: hex-ui-local user@devserver [port]

set -uo pipefail

HOST="${1:?Usage: hex-ui-local user@hostname [port]}"
PORT="${2:-3141}"

echo "Tunneling port ${PORT} to ${HOST}..."
ssh -N -L "${PORT}:localhost:${PORT}" "$HOST" &
SSH_PID=$!
sleep 2

echo "Opening http://localhost:${PORT}"
open "http://localhost:${PORT}" 2>/dev/null || xdg-open "http://localhost:${PORT}" 2>/dev/null || echo "Open http://localhost:${PORT} in your browser"

echo "Press Ctrl+C to disconnect"
trap "kill $SSH_PID 2>/dev/null; exit 0" INT TERM
wait $SSH_PID
