#!/usr/bin/env python3
"""
Evolution Database — Track workflow friction, improvements, and changes.

Usage:
    python3 evolution_db.py add "title" --category automation-candidate --impact "description"
    python3 evolution_db.py occur ID "what happened"
    python3 evolution_db.py list [--status open] [--category X] [--sort occurrences]
    python3 evolution_db.py get ID
    python3 evolution_db.py update ID --status resolved --notes "fixed by..."
    python3 evolution_db.py change ID --type skill "description"
    python3 evolution_db.py export

Part of the Hexagon evolution engine.
"""

import os
import sys
import sqlite3
import argparse
import time
from pathlib import Path
from datetime import datetime, timezone


def _find_root():
    """Walk up from script location to find the agent root."""
    d = Path(__file__).resolve().parent
    for _ in range(6):
        if (d / "CLAUDE.md").exists():
            return d
        d = d.parent
    return Path(__file__).resolve().parent.parent


AGENT_ROOT = Path(os.environ.get("AGENT_DIR", str(_find_root())))
DB_PATH = Path(os.environ.get("EVOLUTION_DB", str(AGENT_ROOT / ".claude" / "memory.db")))

VALID_CATEGORIES = [
    "automation-candidate",
    "bug-recurring",
    "architecture-gap",
    "skill-candidate",
    "architecture-exploration",
]
VALID_STATUSES = ["open", "suggested", "in-progress", "resolved", "wont-fix"]
VALID_CHANGE_TYPES = ["standing-order", "template", "skill", "bug-fix", "process"]


def init_evolution_tables(conn):
    """Create evolution tables if they don't exist."""
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS evolution_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            category TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'open',
            impact TEXT,
            notes TEXT,
            occurrence_count INTEGER DEFAULT 0,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            resolved_at INTEGER
        );

        CREATE TABLE IF NOT EXISTS evolution_occurrences (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id INTEGER NOT NULL,
            observed_at INTEGER NOT NULL,
            context TEXT NOT NULL,
            FOREIGN KEY (item_id) REFERENCES evolution_items(id)
        );

        CREATE TABLE IF NOT EXISTS evolution_changes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id INTEGER,
            change_type TEXT NOT NULL,
            description TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            FOREIGN KEY (item_id) REFERENCES evolution_items(id)
        );
    """)
    conn.commit()


def get_conn():
    """Get a database connection with evolution tables initialized."""
    conn = sqlite3.connect(str(DB_PATH))
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    init_evolution_tables(conn)
    return conn


def cmd_add(args):
    """Add a new friction item with an initial occurrence."""
    now = int(time.time())
    today = int(time.time())

    conn = get_conn()
    conn.execute(
        """INSERT INTO evolution_items
           (title, category, status, impact, notes, occurrence_count, created_at, updated_at)
           VALUES (?, ?, 'open', ?, ?, 1, ?, ?)""",
        (args.title, args.category, args.impact, args.notes, now, now),
    )
    item_id = conn.execute("SELECT last_insert_rowid()").fetchone()[0]

    context = args.context or f"First observed: {args.title}"
    conn.execute(
        """INSERT INTO evolution_occurrences (item_id, observed_at, context)
           VALUES (?, ?, ?)""",
        (item_id, today, context),
    )
    conn.commit()
    conn.close()
    print(f"Added item #{item_id}: {args.title}")


def cmd_occur(args):
    """Add an occurrence to an existing item."""
    today = int(time.time())
    now = int(time.time())

    conn = get_conn()
    row = conn.execute(
        "SELECT id, title FROM evolution_items WHERE id = ?", (args.id,)
    ).fetchone()
    if not row:
        print(f"Item #{args.id} not found.")
        conn.close()
        sys.exit(1)

    conn.execute(
        """INSERT INTO evolution_occurrences (item_id, observed_at, context)
           VALUES (?, ?, ?)""",
        (args.id, today, args.context),
    )
    conn.execute(
        """UPDATE evolution_items
           SET occurrence_count = occurrence_count + 1, updated_at = ?
           WHERE id = ?""",
        (now, args.id),
    )
    conn.commit()

    count = conn.execute(
        "SELECT occurrence_count FROM evolution_items WHERE id = ?", (args.id,)
    ).fetchone()[0]
    conn.close()
    print(f"Occurrence added to #{args.id}: {row[1]} (total: {count})")


def cmd_list(args):
    """List evolution items."""
    conn = get_conn()
    sql = "SELECT id, title, category, status, occurrence_count, impact FROM evolution_items WHERE 1=1"
    params = []

    if args.ready:
        sql += " AND occurrence_count >= 3 AND status = 'open'"
    if args.status:
        sql += " AND status = ?"
        params.append(args.status)
    if args.category:
        sql += " AND category = ?"
        params.append(args.category)

    if args.sort == "occurrences":
        sql += " ORDER BY occurrence_count DESC"
    elif args.sort == "recent":
        sql += " ORDER BY updated_at DESC"
    else:
        sql += " ORDER BY id"

    rows = conn.execute(sql, params).fetchall()
    conn.close()

    if not rows:
        print("No items found.")
        return

    print(f"\n{'ID':>4}  {'Occ':>3}  {'Status':<12}  {'Category':<24}  Title")
    print(f"{'':->4}  {'':->3}  {'':->12}  {'':->24}  {'':->30}")
    for row in rows:
        id_, title, cat, status, occ, impact = row
        print(f"{id_:>4}  {occ:>3}  {status:<12}  {cat:<24}  {title}")


def cmd_get(args):
    """Get full details of a single item."""
    conn = get_conn()
    item = conn.execute(
        "SELECT * FROM evolution_items WHERE id = ?", (args.id,)
    ).fetchone()
    if not item:
        print(f"Item #{args.id} not found.")
        conn.close()
        sys.exit(1)

    cols = [d[0] for d in conn.execute("SELECT * FROM evolution_items LIMIT 0").description]
    print(f"\n--- Item #{item[0]} ---")
    for col, val in zip(cols, item):
        if val is not None:
            print(f"  {col}: {val}")

    occs = conn.execute(
        "SELECT observed_at, context FROM evolution_occurrences WHERE item_id = ? ORDER BY observed_at",
        (args.id,),
    ).fetchall()
    if occs:
        print(f"\n  Occurrences ({len(occs)}):")
        for obs_date, ctx in occs:
            print(f"    - {obs_date}: {ctx}")

    changes = conn.execute(
        "SELECT change_type, description, created_at FROM evolution_changes WHERE item_id = ? ORDER BY created_at",
        (args.id,),
    ).fetchall()
    if changes:
        print(f"\n  Changes ({len(changes)}):")
        for ctype, desc, cat in changes:
            print(f"    - [{ctype}] {desc} ({cat[:10]})")

    conn.close()


def cmd_update(args):
    """Update an existing item."""
    now = int(time.time())
    conn = get_conn()

    row = conn.execute(
        "SELECT id FROM evolution_items WHERE id = ?", (args.id,)
    ).fetchone()
    if not row:
        print(f"Item #{args.id} not found.")
        conn.close()
        sys.exit(1)

    updates = ["updated_at = ?"]
    params = [now]

    if args.status:
        updates.append("status = ?")
        params.append(args.status)
        if args.status == "resolved":
            updates.append("resolved_at = ?")
            params.append(now)
    if args.notes:
        updates.append("notes = ?")
        params.append(args.notes)
    if args.impact:
        updates.append("impact = ?")
        params.append(args.impact)
    if args.title:
        updates.append("title = ?")
        params.append(args.title)

    params.append(args.id)
    conn.execute(
        f"UPDATE evolution_items SET {', '.join(updates)} WHERE id = ?", params
    )
    conn.commit()
    conn.close()
    print(f"Updated item #{args.id}")


def cmd_change(args):
    """Log a change/improvement."""
    now = int(time.time())
    conn = get_conn()

    if args.item_id:
        row = conn.execute(
            "SELECT id FROM evolution_items WHERE id = ?", (args.item_id,)
        ).fetchone()
        if not row:
            print(f"Item #{args.item_id} not found.")
            conn.close()
            sys.exit(1)

    conn.execute(
        """INSERT INTO evolution_changes (item_id, change_type, description, created_at)
           VALUES (?, ?, ?, ?)""",
        (args.item_id, args.type, args.description, now),
    )
    conn.commit()
    conn.close()
    label = f" (linked to #{args.item_id})" if args.item_id else ""
    print(f"Change logged: [{args.type}] {args.description}{label}")


def _ts_to_date(ts):
    """Convert unix timestamp to YYYY-MM-DD string."""
    if ts is None:
        return ""
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%d")


def cmd_export(args):
    """Export database to markdown files."""
    conn = get_conn()
    evo_dir = AGENT_ROOT / "evolution"
    evo_dir.mkdir(exist_ok=True)

    # Export observations.md
    items = conn.execute(
        "SELECT * FROM evolution_items ORDER BY occurrence_count DESC, id"
    ).fetchall()
    cols = [d[0] for d in conn.execute("SELECT * FROM evolution_items LIMIT 0").description]

    lines = [
        "# Workflow Friction\n",
        "_Auto-generated from evolution database. Do not edit directly._\n",
    ]

    for item in items:
        item_dict = dict(zip(cols, item))
        item_id = item_dict["id"]
        status_marker = " [RESOLVED]" if item_dict["status"] == "resolved" else ""
        lines.append(f"## {item_dict['title']}{status_marker}")
        lines.append(f"**Category:** {item_dict['category']}")
        lines.append(f"**Status:** {item_dict['status']}")
        lines.append(f"**Occurrences:** {item_dict['occurrence_count']}")

        occs = conn.execute(
            "SELECT observed_at, context FROM evolution_occurrences WHERE item_id = ? ORDER BY observed_at",
            (item_id,),
        ).fetchall()
        if occs:
            lines.append("**Log:**")
            for obs_ts, ctx in occs:
                lines.append(f"- {_ts_to_date(obs_ts)}: {ctx}")

        if item_dict["impact"]:
            lines.append(f"\n**Impact:** {item_dict['impact']}")
        if item_dict["notes"]:
            lines.append(f"**Notes:** {item_dict['notes']}")
        lines.append("")

    (evo_dir / "observations.md").write_text("\n".join(lines))

    # Export changelog.md
    changes = conn.execute(
        """SELECT c.change_type, c.description, c.created_at, i.title
           FROM evolution_changes c
           LEFT JOIN evolution_items i ON c.item_id = i.id
           ORDER BY c.created_at DESC"""
    ).fetchall()

    ch_lines = [
        "# Changelog\n",
        "_Auto-generated from evolution database. Do not edit directly._\n",
    ]
    if changes:
        for ctype, desc, created_ts, item_title in changes:
            ref = f" (re: {item_title})" if item_title else ""
            ch_lines.append(f"- **[{ctype}]** {desc}{ref} ({_ts_to_date(created_ts)})")
    else:
        ch_lines.append("_No changes recorded yet._")

    (evo_dir / "changelog.md").write_text("\n".join(ch_lines))

    conn.close()
    print(f"Exported to {evo_dir}/observations.md and changelog.md")


def main():
    parser = argparse.ArgumentParser(description="Evolution database CLI")
    sub = parser.add_subparsers(dest="command")

    # add
    p_add = sub.add_parser("add", help="Add a new friction item")
    p_add.add_argument("title", help="Short title")
    p_add.add_argument("--category", required=True, choices=VALID_CATEGORIES)
    p_add.add_argument("--impact", default=None, help="Impact description")
    p_add.add_argument("--notes", default=None, help="Notes or fix path")
    p_add.add_argument("--context", default=None, help="Context for first occurrence")

    # occur
    p_occ = sub.add_parser("occur", help="Add occurrence to existing item")
    p_occ.add_argument("id", type=int, help="Item ID")
    p_occ.add_argument("context", help="What happened")

    # list
    p_list = sub.add_parser("list", help="List items")
    p_list.add_argument("--ready", action="store_true", help="Show only items with 3+ occurrences that are still open")
    p_list.add_argument("--status", choices=VALID_STATUSES)
    p_list.add_argument("--category", choices=VALID_CATEGORIES)
    p_list.add_argument("--sort", choices=["occurrences", "recent", "id"], default="id")

    # get
    p_get = sub.add_parser("get", help="Get full item details")
    p_get.add_argument("id", type=int, help="Item ID")

    # update
    p_upd = sub.add_parser("update", help="Update an item")
    p_upd.add_argument("id", type=int, help="Item ID")
    p_upd.add_argument("--status", choices=VALID_STATUSES)
    p_upd.add_argument("--notes", help="Update notes")
    p_upd.add_argument("--impact", help="Update impact")
    p_upd.add_argument("--title", help="Update title")

    # change
    p_chg = sub.add_parser("change", help="Log a change/improvement")
    p_chg.add_argument("--item-id", type=int, default=None, help="Link to item")
    p_chg.add_argument("--type", required=True, choices=VALID_CHANGE_TYPES)
    p_chg.add_argument("description", help="What changed")

    # export
    sub.add_parser("export", help="Export to markdown")

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)

    cmds = {
        "add": cmd_add,
        "occur": cmd_occur,
        "list": cmd_list,
        "get": cmd_get,
        "update": cmd_update,
        "change": cmd_change,
        "export": cmd_export,
    }
    cmds[args.command](args)


if __name__ == "__main__":
    main()
