---
name: hexagon
description: >
  Bootstrap a personal AI agent workspace. Creates a persistent, self-improving
  agent that compounds over time. Use when the user says "set up my agent",
  "create an agent", "bootstrap hexagon", or runs /hexagon.
version: 1.0.0
---

# Hexagon — Bootstrap Your AI Agent

Set up a personal AI agent workspace that learns, improves, and compounds over time.

## Steps

### 1. Ask for the agent name

Ask the user:
> What would you like to name your agent? (This becomes the folder name. Examples: "atlas", "jarvis", "friday")

If the user doesn't have a preference, suggest a name based on their system username.

### 2. Ask for the install location

Ask the user:
> Where do you want to install your agent? (defaults to ~/hexagon)

### 3. Run the bootstrap script

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap.sh" --agent "<agent-name>" --path "<install-path>"
```

If the directory already exists, the script will refuse to continue. The user must remove it first or choose a different name.

This creates the full agent workspace at `<install-path>/<agent-name>/` with:
- CLAUDE.md (agent brain)
- me/me.md (personal context)
- todo.md (priorities)
- Memory system (searchable knowledge base)
- Improvement engine (evolution/ directory)
- Session management tools
- Slash commands (/hex-startup, /hex-save, /hex-shutdown, etc.)

### 4. Tell the user what's next

After bootstrap completes, tell the user:

> Your agent is ready! The `hex` command has been added to your shell.
>
> **Open a new terminal and run `hex`**
>
> This launches a tmux workspace with Claude Code and a live dashboard. Your agent will start up and ask 3 quick questions to get to know you.
>
> (No tmux? You can also run: `cd <install-path>/<agent-name> && claude`, then `/hex-startup`)
>
> Your agent gets smarter with every session. It learns how you work, spots patterns, and suggests improvements over time.
