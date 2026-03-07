#!/usr/bin/env python3
"""
Memory Health Check — Detect stale files, missing core files, and gaps.

Usage:
    python3 memory_health.py          # Run all checks
    python3 memory_health.py --quiet  # Only show warnings and failures

Part of the Hexagon Base memory system.
"""

import os
import sys
import sqlite3
import argparse
from datetime import datetime, timedelta
from pathlib import Path


def _find_root():
    """Walk up from script location to find the agent root."""
    d = Path(__file__).resolve().parent
    for _ in range(6):
        if (d / "CLAUDE.md").exists():
            return d
        d = d.parent
    return Path(__file__).resolve().parent.parent


AGENT_ROOT = _find_root()
DB_PATH = AGENT_ROOT / ".claude" / "memory.db"

PASS = "\033[32mPASS\033[0m"
WARN = "\033[33mWARN\033[0m"
FAIL = "\033[31mFAIL\033[0m"


def check_core_files():
    """Check that essential files exist."""
    required = ["CLAUDE.md", "todo.md", "me/me.md", "me/learnings.md", "teams.json"]
    missing = [f for f in required if not (AGENT_ROOT / f).exists()]
    if missing:
        return FAIL, f"Missing core files: {', '.join(missing)}"
    return PASS, f"All {len(required)} core files present"


def check_evolution_directory():
    """Check if the improvement engine has been active."""
    evo_dir = AGENT_ROOT / "evolution"
    if not evo_dir.exists():
        return WARN, "evolution/ directory does not exist"

    expected = ["observations.md", "suggestions.md", "changelog.md", "metrics.md"]
    missing = [f for f in expected if not (evo_dir / f).exists()]
    if missing:
        return WARN, f"Missing evolution files: {', '.join(missing)}"

    # Check if observations have been written (not just the template header)
    obs_file = evo_dir / "observations.md"
    if obs_file.exists():
        content = obs_file.read_text(encoding="utf-8", errors="replace")
        lines = [l for l in content.strip().split("\n") if l.strip() and not l.startswith("#") and not l.startswith("_")]
        if not lines:
            return PASS, "Evolution files present (no observations recorded yet)"

    return PASS, "Evolution directory healthy"


def check_duplicate_people():
    """Check for duplicate people files."""
    people_dir = AGENT_ROOT / "people"
    if not people_dir.exists():
        return PASS, "No people directory yet"

    names = {}
    for d in people_dir.iterdir():
        if d.is_dir():
            base = d.name.split("-")[0].lower()
            names.setdefault(base, []).append(d.name)

    duplicates = {k: v for k, v in names.items() if len(v) > 1}
    if duplicates:
        dup_list = "; ".join(f"{k}: {', '.join(v)}" for k, v in duplicates.items())
        return WARN, f"Possible duplicate people: {dup_list}"
    return PASS, f"No duplicates ({len(names)} people)"


def check_stale_files():
    """Check if key files have been updated recently."""
    cutoff = datetime.now() - timedelta(hours=48)
    stale = []
    for fname in ["todo.md", "me/learnings.md"]:
        fpath = AGENT_ROOT / fname
        if fpath.exists():
            mtime = datetime.fromtimestamp(fpath.stat().st_mtime)
            if mtime < cutoff:
                stale.append(f"{fname} (last modified {mtime.strftime('%Y-%m-%d %H:%M')})")

    if stale:
        return WARN, f"Stale files (not updated in 48h): {', '.join(stale)}"
    return PASS, "Key files are fresh (updated within 48h)"


def check_index_freshness():
    """Check if memory.db is newer than the most recent .md file."""
    if not DB_PATH.exists():
        return FAIL, "memory.db does not exist. Run memory_index.py."

    db_mtime = DB_PATH.stat().st_mtime

    latest_md = 0
    latest_file = ""
    skip_dirs = {".claude", ".sessions", "node_modules", ".git"}
    for root, dirs, files in os.walk(str(AGENT_ROOT)):
        dirs[:] = [d for d in dirs if d not in skip_dirs]
        for f in files:
            if f.endswith(".md") or f.endswith(".txt"):
                fpath = os.path.join(root, f)
                mt = os.path.getmtime(fpath)
                if mt > latest_md:
                    latest_md = mt
                    latest_file = fpath

    if latest_md > db_mtime:
        rel_path = os.path.relpath(latest_file, str(AGENT_ROOT))
        age = int((latest_md - db_mtime) / 60)
        return WARN, f"Index is stale. {rel_path} is {age}min newer than memory.db. Run memory_index.py."
    return PASS, "memory.db is up to date"


def check_index_stats():
    """Show index size stats."""
    if not DB_PATH.exists():
        return WARN, "No database"

    conn = sqlite3.connect(str(DB_PATH))
    try:
        files = conn.execute("SELECT COUNT(*) FROM files").fetchone()[0]
        chunks = conn.execute("SELECT COUNT(*) FROM chunks").fetchone()[0]
        size_kb = DB_PATH.stat().st_size / 1024
        return PASS, f"Index: {files} files, {chunks} chunks, {size_kb:.0f} KB"
    except Exception as e:
        return WARN, f"Could not read index stats: {e}"
    finally:
        conn.close()


def main():
    parser = argparse.ArgumentParser(description="Memory health check")
    parser.add_argument("--quiet", action="store_true", help="Only show warnings and failures")
    args = parser.parse_args()

    checks = [
        ("Core files", check_core_files),
        ("Evolution directory", check_evolution_directory),
        ("Duplicate people", check_duplicate_people),
        ("File freshness", check_stale_files),
        ("Index freshness", check_index_freshness),
        ("Index stats", check_index_stats),
    ]

    print(f"\n{'='*60}")
    print(f" Memory Health Check — {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    print(f"{'='*60}\n")

    warnings = 0
    failures = 0

    for name, check_fn in checks:
        status, message = check_fn()
        if status == WARN:
            warnings += 1
        elif status == FAIL:
            failures += 1

        if not args.quiet or status != PASS:
            print(f"  [{status}] {name}: {message}")

    print(f"\n{'─'*60}")
    if failures:
        print(f"  {failures} failure(s), {warnings} warning(s)")
    elif warnings:
        print(f"  All checks passed with {warnings} warning(s)")
    else:
        print(f"  All checks passed")
    print()


if __name__ == "__main__":
    main()
