---
name: hex-ui
description: >
  Launch the Hexagon web UI server. Opens a browser-based interface
  for your agent workspace.
---

Start the Hexagon web UI server.

## Steps

1. Check if the UI dependencies are installed: `pip show fastapi uvicorn jinja2`
2. If not installed: `pip install -r .claude/ui/requirements.txt`
3. Start the server: `python3 .claude/ui/app.py`
4. Print: "Hexagon UI running at http://localhost:3141"

## Notes

- The UI reads and writes the same workspace files as the CLI agent
- Changes made in the UI are immediately visible in Claude Code and vice versa
- Default port is 3141, configurable with `--port`
- Access from any device on the same network by using your machine's IP instead of localhost
