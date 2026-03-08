#!/bin/bash
# Detect remote environment and print SSH tunnel instructions.
# Sourced by ui.sh after server start to guide users on remote access.

set -uo pipefail

PORT="${1:-3141}"

is_remote() {
  # SSH_CONNECTION is set by sshd on remote sessions
  if [ -n "${SSH_CONNECTION:-}" ]; then
    return 0
  fi
  # SSH_TTY is another indicator
  if [ -n "${SSH_TTY:-}" ]; then
    return 0
  fi
  return 1
}

print_tunnel_instructions() {
  local port="$1"
  local hostname
  local user

  hostname="$(hostname -f 2>/dev/null || hostname)"
  user="$(whoami)"

  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo "  Hexagon UI is running on this remote server."
  echo ""
  echo "  To access from your local machine, open a NEW terminal"
  echo "  and run:"
  echo ""
  echo "    ssh -L ${port}:localhost:${port} ${user}@${hostname}"
  echo ""
  echo "  Then open: http://localhost:${port}"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
}

# Main: if sourced, export the function. If run directly, print instructions.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if is_remote; then
    print_tunnel_instructions "$PORT"
  else
    echo "Running locally. Open http://localhost:${PORT}"
  fi
fi
