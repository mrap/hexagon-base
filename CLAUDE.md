# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Installation (for users)

When a user asks to "install hexagon", "set up my agent", "bootstrap", or similar:

1. Ask: **"What would you like to name your agent?"** (becomes the folder name, e.g., "atlas", "friday")
2. Ask: **"Where do you want to install?"** (default: `~/hexagon`)
3. Run: `bash scripts/bootstrap.sh --agent "<name>" --path "<path>"`
4. After bootstrap completes, read the workspace path from its output and tell the user:
   - Exit this Claude session
   - Open a new session in their workspace: `cd <workspace-path> && claude`
   - Run `/hex-startup` to begin — the agent will ask 3 quick questions to get to know them

## What This Is

Hexagon Base is a seed repository that bootstraps a persistent, self-improving AI agent workspace. This repo is not the agent itself; it's the installer. Running `bash scripts/bootstrap.sh` creates a fully independent agent workspace at a user-chosen directory (default: `~/hexagon`).

The created workspace has no symlinks back to this repo. Everything is copied into the target directory.

## Architecture

### Bootstrap Flow

1. User asks to install/set up their agent
2. Claude asks for agent name and install location
3. `scripts/bootstrap.sh` creates the full workspace:
   - Copies `dot-claude/` into `.claude/` (commands, settings template)
   - Generates `.claude/settings.json` from template with hook paths
   - Copies tools (scripts, skills, hooks) into `tools/`
   - Generates `CLAUDE.md` from `templates/CLAUDE.md.template` with variable substitution (`{{NAME}}`, `{{AGENT}}`, `{{DATE}}`)
   - Creates skeleton files from templates (`me.md`, `todo.md`)

### Key Directories

- **`dot-claude/`** — Pre-built `.claude/` directory copied into workspace:
  - `commands/` — Slash command definitions (markdown files with YAML frontmatter)
  - `settings.json.template` — Settings template with `{{AGENT_DIR}}` placeholder for hook paths
- **`templates/`** — Templates with `{{VAR}}` placeholders, processed by `bootstrap.sh` via `sed`
- **`scripts/`** — Bootstrap script only. Not copied into agent workspace.
- **`plugin/`** — Everything that gets copied into the agent's `tools/` directory:
  - `hooks/` — Event hook scripts
  - `scripts/` — Runtime scripts (startup.sh, session.sh, parse_transcripts.py)
  - `skills/memory/` — Memory system (SQLite FTS5 indexer, search, health check)
- **`tests/`** — Eval suite (run_evals.sh, eval_wizard.sh)

### How It Works

Claude Code natively reads `.claude/commands/` for slash commands and `.claude/settings.json` for hooks. No plugin manifest or marketplace install needed — the user just runs `claude` in the workspace and everything works.

### Memory System (Python, stdlib only)

Three scripts in `plugin/skills/memory/scripts/`:
- `memory_index.py` — Indexes all `.md`/`.txt` files into SQLite FTS5, chunked by heading. Incremental by default.
- `memory_search.py` — BM25-ranked full-text search with file filtering, privacy mode, context display.
- `memory_health.py` — Checks core files exist, index freshness, duplicate detection.

All use Python 3.8+ standard library only (sqlite3, pathlib, etc). No external dependencies.

## Common Commands

```bash
# Test bootstrap (creates ephemeral workspace)
bash scripts/bootstrap.sh --agent testuser --name "Test User" --path /tmp/hexagon-test

# Validate the template line count (must stay under 600)
wc -l templates/CLAUDE.md.template

# Check Python script syntax
python3 -m py_compile plugin/skills/memory/scripts/memory_index.py
python3 -m py_compile plugin/skills/memory/scripts/memory_search.py
python3 -m py_compile plugin/skills/memory/scripts/memory_health.py
python3 -m py_compile plugin/scripts/parse_transcripts.py

# Check shell script syntax
bash -n scripts/bootstrap.sh
bash -n plugin/scripts/startup.sh
bash -n plugin/scripts/session.sh
bash -n plugin/hooks/scripts/backup_session.sh

# Test memory system after bootstrap
python3 /tmp/hexagon-test/testuser/tools/skills/memory/scripts/memory_index.py
python3 /tmp/hexagon-test/testuser/tools/skills/memory/scripts/memory_search.py "test query"
python3 /tmp/hexagon-test/testuser/tools/skills/memory/scripts/memory_health.py
```

## Template Variables

Only three variables are used across all templates:
- `{{NAME}}` — User's full name (auto-detected or provided via `--name`)
- `{{AGENT}}` — Agent folder name (e.g., "atlas")
- `{{DATE}}` — Today's date (YYYY-MM-DD)

## Key Constraints

- `CLAUDE.md.template` must stay under 600 lines (currently ~528)
- Python scripts must use only stdlib (no pip dependencies)
- Must work on both macOS and Linux (path detection, stat flags differ)
- Bootstrap must be idempotent for plugin components but refuse to overwrite an existing agent workspace
- The created workspace must be fully self-contained — no references back to this seed repo
