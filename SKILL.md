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

### 2. Run the bootstrap script

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap.sh" --agent "<agent-name>"
```

This creates the full agent workspace at `~/.hexagon/<agent-name>/` with:
- CLAUDE.md (agent brain)
- me/me.md (personal context)
- todo.md (priorities)
- Memory system (searchable knowledge base)
- Improvement engine (evolution/ directory)
- Session management tools
- Slash commands (/hex-startup, /hex-save, /hex-shutdown, etc.)

### 3. Tell the user what's next

After bootstrap completes, tell the user:

> Your agent is ready at `~/.hexagon/<agent-name>/`.
>
> To start your first session:
> 1. Open a new Claude Code session in that directory: `cd ~/.hexagon/<agent-name> && claude`
> 2. Run `/hex-startup` to begin
> 3. The agent will ask you 3 quick questions to get started
>
> Your agent gets smarter with every session. It learns how you work, spots patterns, and suggests improvements over time.
