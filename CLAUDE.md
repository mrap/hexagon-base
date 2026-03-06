# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Hexagon Base is a Claude Code **plugin** — a seed repository that bootstraps a persistent, self-improving AI agent workspace. This repo is not the agent itself; it's the installer. Running `/hexagon` (the SKILL.md) creates a fully independent agent workspace at a user-chosen directory (default: `~/hexagon`).

The created workspace has no symlinks back to this repo. Everything is copied into the target directory.

## Architecture

### Bootstrap Flow

1. User runs `/hexagon` in Claude Code (triggers SKILL.md)
2. SKILL.md prompts for agent name and install location
3. `scripts/bootstrap.sh` creates the full workspace:
   - Copies plugin components (skills, commands, hooks, scripts) into `tools/`
   - Generates `CLAUDE.md` from `templates/CLAUDE.md.template` with variable substitution (`{{NAME}}`, `{{AGENT}}`, `{{DATE}}`)
   - Creates skeleton files from templates (`me.md`, `todo.md`)
   - Creates `.claude-plugin/plugin.json` manifest for auto-discovery
   - Links the workspace to `~/.claude/plugins/` for Claude Code to find it

### Key Directories

- **`templates/`** — Templates with `{{VAR}}` placeholders, processed by `bootstrap.sh` via `sed`
- **`scripts/`** — Bootstrap script only. Not copied into agent workspace.
- **`plugin/`** — Everything that gets copied into the agent's `tools/` directory:
  - `commands/` — Slash command definitions (markdown files with YAML frontmatter)
  - `hooks/` — Event hooks (hooks.json + shell scripts)
  - `scripts/` — Runtime scripts (startup.sh, session.sh, parse_transcripts.py)
  - `skills/memory/` — Memory system (SQLite FTS5 indexer, search, health check)

### Plugin System

Claude Code plugins are directories with `.claude-plugin/plugin.json`. The manifest declares:
- `skills` — directories containing SKILL.md files
- `commands` — directories containing slash command `.md` files
- `hooks` — event handlers (UserPromptSubmit, Stop) that run shell scripts

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
