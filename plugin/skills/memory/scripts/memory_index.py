#!/usr/bin/env python3
"""
Memory Indexer — Indexes all markdown and text files into SQLite FTS5 for search.

Usage:
    python3 memory_index.py              # Incremental index (only changed files)
    python3 memory_index.py --full       # Full reindex
    python3 memory_index.py --stats      # Show index stats

Part of the Hexagon Base memory system.
"""

import os
import sys
import sqlite3
import re
from pathlib import Path
from datetime import datetime


def _find_root():
    """Walk up from script location to find the agent root (has CLAUDE.md or .claude-plugin/)."""
    d = Path(__file__).resolve().parent
    for _ in range(6):
        if (d / "CLAUDE.md").exists() or (d / ".claude-plugin").exists():
            return d
        d = d.parent
    return Path(__file__).resolve().parent.parent


AGENT_ROOT = _find_root()
DB_PATH = AGENT_ROOT / "tools" / "memory.db"

# Directories to index (relative to AGENT_ROOT)
INDEX_DIRS = [
    ".",            # Root files (todo.md, etc.)
    "me",           # Personal context, learnings
    "projects",     # Project docs
    "people",       # Relationship profiles
    "raw",          # Transcripts, messages, calendar data
    "evolution",    # Improvement engine files
    "landings",     # Daily landing targets
]

# Files/dirs to skip
SKIP_PATTERNS = [
    ".claude-plugin",
    ".claude",
    ".sessions",
    "tools/memory.db",
    "tools/scripts",
    "tools/skills",
    "tools/hooks",
    "tools/commands",
    "tools/templates",
    "node_modules",
    ".git",
]

# Chunking config
MAX_CHUNK_WORDS = 400
OVERLAP_WORDS = 80


def should_skip(path: Path) -> bool:
    """Check if a file should be skipped."""
    rel = str(path.relative_to(AGENT_ROOT))
    for pattern in SKIP_PATTERNS:
        if rel.startswith(pattern) or f"/{pattern}" in rel:
            return True
    return False


def chunk_by_heading(content: str, source_path: str) -> list:
    """Split markdown content into chunks by heading."""
    lines = content.split("\n")
    chunks = []
    current_heading = "(top)"
    current_lines = []

    for line in lines:
        heading_match = re.match(r"^(#{1,4})\s+(.+)$", line)
        if heading_match:
            if current_lines:
                text = "\n".join(current_lines).strip()
                if text:
                    chunks.append({"heading": current_heading, "content": text})
            current_heading = heading_match.group(2).strip()
            current_lines = [line]
        else:
            current_lines.append(line)

    if current_lines:
        text = "\n".join(current_lines).strip()
        if text:
            chunks.append({"heading": current_heading, "content": text})

    # Split large chunks further
    final_chunks = []
    for chunk in chunks:
        words = chunk["content"].split()
        if len(words) <= MAX_CHUNK_WORDS:
            final_chunks.append(chunk)
        else:
            i = 0
            sub_idx = 0
            while i < len(words):
                end = min(i + MAX_CHUNK_WORDS, len(words))
                sub_content = " ".join(words[i:end])
                final_chunks.append({
                    "heading": chunk["heading"] + (f" (part {sub_idx + 1})" if sub_idx > 0 else ""),
                    "content": sub_content,
                })
                sub_idx += 1
                i += MAX_CHUNK_WORDS - OVERLAP_WORDS

    return final_chunks


def init_db(conn: sqlite3.Connection):
    """Create tables if they don't exist."""
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT UNIQUE NOT NULL,
            mtime REAL NOT NULL,
            indexed_at TEXT NOT NULL,
            chunk_count INTEGER DEFAULT 0
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS chunks USING fts5(
            file_id,
            source_path,
            heading,
            chunk_index,
            content,
            tokenize='porter unicode61'
        );
    """)
    conn.commit()


def get_indexable_files() -> list:
    """Find all markdown and text files to index."""
    files = []
    for index_dir in INDEX_DIRS:
        dir_path = AGENT_ROOT / index_dir
        if not dir_path.exists():
            continue
        if index_dir == ".":
            for f in dir_path.glob("*.md"):
                if not should_skip(f):
                    files.append(f)
        else:
            for f in dir_path.rglob("*.md"):
                if not should_skip(f):
                    files.append(f)
            for f in dir_path.rglob("*.txt"):
                if not should_skip(f):
                    files.append(f)
    return files


def index_file(conn: sqlite3.Connection, filepath: Path) -> int:
    """Index a single file. Returns number of chunks created."""
    rel_path = str(filepath.relative_to(AGENT_ROOT))
    mtime = filepath.stat().st_mtime

    try:
        content = filepath.read_text(encoding="utf-8", errors="replace")
    except Exception as e:
        print(f"  SKIP {rel_path}: {e}")
        return 0

    if not content.strip():
        return 0

    chunks = chunk_by_heading(content, rel_path)

    # Remove old chunks for this file
    row = conn.execute("SELECT id FROM files WHERE path = ?", (rel_path,)).fetchone()
    if row:
        conn.execute("DELETE FROM chunks WHERE file_id = ?", (str(row[0]),))
        conn.execute("DELETE FROM files WHERE id = ?", (row[0],))

    # Insert file record
    conn.execute(
        "INSERT INTO files (path, mtime, indexed_at, chunk_count) VALUES (?, ?, ?, ?)",
        (rel_path, mtime, datetime.now().isoformat(), len(chunks))
    )
    file_id = conn.execute("SELECT last_insert_rowid()").fetchone()[0]

    # Insert chunks
    for i, chunk in enumerate(chunks):
        conn.execute(
            "INSERT INTO chunks (file_id, source_path, heading, chunk_index, content) VALUES (?, ?, ?, ?, ?)",
            (str(file_id), rel_path, chunk["heading"], str(i), chunk["content"])
        )

    return len(chunks)


def run_index(full: bool = False):
    """Run the indexer."""
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(DB_PATH))
    conn.execute("PRAGMA journal_mode=WAL")
    init_db(conn)

    files = get_indexable_files()
    print(f"Found {len(files)} files to check")

    indexed = 0
    skipped = 0
    total_chunks = 0

    for filepath in files:
        rel_path = str(filepath.relative_to(AGENT_ROOT))
        mtime = filepath.stat().st_mtime

        if not full:
            row = conn.execute(
                "SELECT mtime FROM files WHERE path = ?", (rel_path,)
            ).fetchone()
            if row and abs(row[0] - mtime) < 0.01:
                skipped += 1
                continue

        chunks = index_file(conn, filepath)
        if chunks > 0:
            indexed += 1
            total_chunks += chunks
            print(f"  Indexed: {rel_path} ({chunks} chunks)")

    # Clean up files that no longer exist
    all_paths = {str(f.relative_to(AGENT_ROOT)) for f in files}
    db_paths = [row[0] for row in conn.execute("SELECT path FROM files").fetchall()]
    removed = 0
    for db_path in db_paths:
        if db_path not in all_paths:
            row = conn.execute("SELECT id FROM files WHERE path = ?", (db_path,)).fetchone()
            if row:
                conn.execute("DELETE FROM chunks WHERE file_id = ?", (str(row[0]),))
                conn.execute("DELETE FROM files WHERE id = ?", (row[0],))
                removed += 1
                print(f"  Removed: {db_path}")

    conn.commit()
    conn.close()

    print(f"\nDone: {indexed} indexed, {skipped} unchanged, {removed} removed, {total_chunks} new chunks")


def show_stats():
    """Show index statistics."""
    if not DB_PATH.exists():
        print("No index found. Run without --stats to create one.")
        return

    conn = sqlite3.connect(str(DB_PATH))

    file_count = conn.execute("SELECT COUNT(*) FROM files").fetchone()[0]
    chunk_count = conn.execute("SELECT COUNT(*) FROM chunks").fetchone()[0]

    print(f"Database: {DB_PATH}")
    print(f"Size: {DB_PATH.stat().st_size / 1024:.1f} KB")
    print(f"Files indexed: {file_count}")
    print(f"Total chunks: {chunk_count}")
    print()

    print("By directory:")
    rows = conn.execute("""
        SELECT
            CASE
                WHEN source_path LIKE '%/%' THEN substr(source_path, 1, instr(source_path, '/') - 1)
                ELSE '(root)'
            END as dir,
            COUNT(DISTINCT source_path) as files,
            COUNT(*) as chunks
        FROM chunks
        GROUP BY dir
        ORDER BY chunks DESC
    """).fetchall()
    for dir_name, files, chunks in rows:
        print(f"  {dir_name}: {files} files, {chunks} chunks")

    conn.close()


if __name__ == "__main__":
    if "--stats" in sys.argv:
        show_stats()
    elif "--full" in sys.argv:
        print("Full reindex...")
        run_index(full=True)
    else:
        print("Incremental index...")
        run_index(full=False)
