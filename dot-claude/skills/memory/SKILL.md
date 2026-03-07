---
name: memory
description: >
  Searchable memory system for the hexagon agent. Indexes all markdown and text
  files into a local SQLite database with full-text search. Use when you need to
  recall past context, decisions, people details, or project history.
version: 1.0.0
---

# Memory System

Persistent, searchable memory stored locally as a SQLite full-text search index.

## When to Use

- Before answering questions about past context, decisions, or people
- When the user asks "do you remember..." or "what did we decide about..."
- When you need to find information across multiple files
- Standing order: **search memory before guessing**

## How to Search

```bash
python3 $AGENT_DIR/.claude/skills/memory/scripts/memory_search.py "query terms"
```

### Options

| Flag | What it does | Example |
|------|-------------|---------|
| `--top N` | Return top N results (default: 10) | `--top 5 "meeting"` |
| `--file PAT` | Filter by file path | `--file people "alice"` |
| `--compact` | One line per result | `--compact "project status"` |
| `--context N` | Show N lines around match | `--context 3 "decision"` |
| `--private` | Exclude me/, people/, raw/ | `--private "keyword"` |

## How to Rebuild

```bash
python3 $AGENT_DIR/.claude/skills/memory/scripts/memory_index.py           # Incremental
python3 $AGENT_DIR/.claude/skills/memory/scripts/memory_index.py --full     # Full reindex
python3 $AGENT_DIR/.claude/skills/memory/scripts/memory_index.py --stats    # Show stats
```

## Health Check

```bash
python3 $AGENT_DIR/.claude/skills/memory/scripts/memory_health.py
python3 $AGENT_DIR/.claude/skills/memory/scripts/memory_health.py --quiet
```

Checks: core files exist, index is fresh, no duplicate people, evolution directory healthy.

## How It Works

- All `.md` and `.txt` files in the agent directory are indexed
- Files are split by markdown heading into searchable chunks
- Uses BM25 ranking (relevance scoring) for search results
- Index updates are incremental (only changed files)
- Database uses WAL mode for safe concurrent reads across sessions
