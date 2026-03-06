#!/usr/bin/env python3
"""
Memory Search — Search across all indexed files using FTS5.

Usage:
    python3 memory_search.py "query terms"
    python3 memory_search.py --top 5 "exact phrase"
    python3 memory_search.py --file people "name"
    python3 memory_search.py --context 3 "keyword"
    python3 memory_search.py --compact "keyword"
    python3 memory_search.py --private "sensitive"

Part of the Hexagon Base memory system.
"""

import sys
import sqlite3
import argparse
import re
from pathlib import Path


def _find_root():
    """Walk up from script location to find the agent root."""
    d = Path(__file__).resolve().parent
    for _ in range(6):
        if (d / "CLAUDE.md").exists() or (d / ".claude-plugin").exists():
            return d
        d = d.parent
    return Path(__file__).resolve().parent.parent


AGENT_ROOT = _find_root()
DB_PATH = AGENT_ROOT / "tools" / "memory.db"


def truncate(text: str, max_chars: int = 300) -> str:
    """Truncate text to max_chars, ending at a word boundary."""
    if len(text) <= max_chars:
        return text
    truncated = text[:max_chars].rsplit(" ", 1)[0]
    return truncated + "..."


def highlight_terms(text: str, query: str) -> str:
    """Bold matching terms in output (using ANSI codes)."""
    terms = query.lower().split()
    result = text
    for term in terms:
        pattern = re.compile(re.escape(term), re.IGNORECASE)
        result = pattern.sub(lambda m: f"\033[1;33m{m.group()}\033[0m", result)
    return result


def search(query: str, top_n: int = 10, file_filter: str = None) -> list:
    """Search the FTS5 index."""
    if not DB_PATH.exists():
        print("No index found. Run memory_index.py first.")
        sys.exit(1)

    conn = sqlite3.connect(str(DB_PATH))
    fts_query = query.strip()

    sql = """
        SELECT
            source_path,
            heading,
            chunk_index,
            content,
            bm25(chunks) as score
        FROM chunks
        WHERE chunks MATCH ?
    """
    params = [fts_query]

    if file_filter:
        sql += " AND source_path LIKE ?"
        params.append(f"%{file_filter}%")

    sql += " ORDER BY score LIMIT ?"
    params.append(top_n)

    try:
        rows = conn.execute(sql, params).fetchall()
    except sqlite3.OperationalError as e:
        terms = fts_query.split()
        if len(terms) > 1:
            fts_query = " OR ".join(terms)
            params[0] = fts_query
            try:
                rows = conn.execute(sql, params).fetchall()
            except sqlite3.OperationalError:
                print(f"Search error: {e}")
                conn.close()
                return []
        else:
            print(f"Search error: {e}")
            conn.close()
            return []

    conn.close()
    return rows


def main():
    parser = argparse.ArgumentParser(description="Search memory files")
    parser.add_argument("query", nargs="+", help="Search query")
    parser.add_argument("--top", type=int, default=10, help="Number of results")
    parser.add_argument("--file", type=str, default=None, help="Filter by file path pattern")
    parser.add_argument("--compact", action="store_true", help="Compact output")
    parser.add_argument("--context", type=int, default=None, help="Show N lines of context around match")
    parser.add_argument("--private", action="store_true", help="Exclude sensitive paths (me/, people/, raw/)")
    args = parser.parse_args()

    query = " ".join(args.query)
    results = search(query, top_n=args.top, file_filter=args.file)

    # Privacy mode: filter out sensitive paths
    if args.private:
        sensitive_prefixes = ("me/", "people/", "raw/")
        results = [r for r in results if not any(r[0].startswith(p) for p in sensitive_prefixes)]

    if not results:
        print(f"No results for: {query}")
        return

    print(f"\n{'='*60}")
    print(f" Memory Search: \"{query}\" — {len(results)} results")
    print(f"{'='*60}\n")

    for i, (source_path, heading, chunk_idx, content, score) in enumerate(results):
        if args.compact:
            snippet = truncate(content.replace("\n", " "), 100)
            print(f"  [{i+1}] {source_path} > {heading}  (score: {score:.2f})")
            print(f"      {snippet}")
            print()
        else:
            print(f"--- Result {i+1} ---")
            print(f"  File:    {source_path}")
            print(f"  Section: {heading}")
            print(f"  Score:   {score:.2f}")
            print(f"  Content:")
            if args.context is not None:
                lines = content.split("\n")
                query_terms = query.lower().split()
                matching_indices = set()
                for idx, line in enumerate(lines):
                    if any(term in line.lower() for term in query_terms):
                        for j in range(max(0, idx - args.context),
                                       min(len(lines), idx + args.context + 1)):
                            matching_indices.add(j)
                if matching_indices:
                    prev_idx = -2
                    for idx in sorted(matching_indices):
                        if idx > prev_idx + 1:
                            print(f"    ...")
                        print(f"    {highlight_terms(lines[idx], query)}")
                        prev_idx = idx
                else:
                    snippet = truncate(content, 500)
                    for line in snippet.split("\n"):
                        print(f"    {line}")
            else:
                snippet = truncate(content, 500)
                for line in snippet.split("\n"):
                    print(f"    {line}")
            print()

    if len(results) == args.top:
        print(f"(Showing top {args.top}. Use --top N to see more.)")


if __name__ == "__main__":
    main()
