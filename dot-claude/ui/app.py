"""Hexagon Web UI — FastAPI + HTMX server for agent workspaces."""

import argparse
import asyncio
import html as html_mod
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import markdown as md_lib

from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from starlette.responses import StreamingResponse

# ─── Workspace detection ─────────────────────────────────────────────────────


def find_workspace(start: Path | None = None) -> Path:
    """Walk up from start to find directory containing CLAUDE.md."""
    candidate = start or Path(__file__).resolve().parent
    while candidate != candidate.parent:
        if (candidate / "CLAUDE.md").exists():
            return candidate
        candidate = candidate.parent
    return Path.home() / "hexagon"


# ─── Data readers ────────────────────────────────────────────────────────────


def read_landings(ws: Path) -> list[dict]:
    """Read today's landings file and parse into structured items."""
    today = datetime.now().strftime("%Y-%m-%d")
    landings_dir = ws / "landings"
    landings_file = landings_dir / f"{today}.md"

    if not landings_file.exists():
        # Also try alternate naming conventions
        alt_file = landings_dir / f"{today}_daily.md"
        if alt_file.exists():
            landings_file = alt_file
        else:
            return []

    text = landings_file.read_text(encoding="utf-8")
    items = []

    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            continue

        # Detect checkbox lines: - [x] done, - [ ] pending, - [~] in progress
        m = re.match(r"^[-*]\s*\[([xX ]|~)\]\s*(.*)", stripped)
        if m:
            marker = m.group(1).lower()
            label = m.group(2).strip()
            if marker == "x":
                status = "done"
            elif marker == "~":
                status = "in_progress"
            else:
                status = "pending"
            items.append({"label": label, "status": status})
        elif stripped.startswith(("- ", "* ")):
            # Plain list items treated as pending
            label = stripped[2:].strip()
            if label:
                items.append({"label": label, "status": "pending"})

    return items


def read_captures(ws: Path, limit: int = 5) -> list[dict]:
    """Read recent captures from raw/captures/ directory."""
    captures_dir = ws / "raw" / "captures"
    if not captures_dir.exists():
        return []

    files = sorted(
        captures_dir.glob("*.md"), key=lambda f: f.stat().st_mtime, reverse=True
    )

    captures = []
    for f in files[:limit]:
        text = f.read_text(encoding="utf-8")
        # Strip YAML frontmatter if present
        content = text
        if text.startswith("---"):
            parts = text.split("---", 2)
            if len(parts) >= 3:
                content = parts[2].strip()

        # First non-empty line as preview
        preview = ""
        for line in content.splitlines():
            line = line.strip()
            if line:
                preview = line
                break

        mtime = datetime.fromtimestamp(f.stat().st_mtime)
        captures.append(
            {
                "preview": preview[:120],
                "filename": f.name,
                "timestamp": mtime,
                "relative_time": _relative_time(mtime),
            }
        )

    return captures


def read_todos(ws: Path) -> list[str]:
    """Read todo.md and extract items from the Now/Priority section."""
    todo_file = ws / "todo.md"
    if not todo_file.exists():
        return []

    text = todo_file.read_text(encoding="utf-8")
    items = []
    in_priority = False

    for line in text.splitlines():
        stripped = line.strip().lower()

        # Detect priority / now sections
        if stripped in (
            "## now",
            "## priority",
            "# now",
            "# priority",
            "## must do",
            "# must do",
        ):
            in_priority = True
            continue

        # Another heading ends the section
        if in_priority and stripped.startswith("#"):
            break

        if in_priority:
            clean = line.strip()
            # List items
            m = re.match(r"^[-*]\s*\[[ xX~]\]\s*(.*)", clean)
            if m:
                items.append(m.group(1).strip())
            elif clean.startswith(("- ", "* ")):
                items.append(clean[2:].strip())

    # If no priority section found, grab all list items
    if not items:
        for line in text.splitlines():
            clean = line.strip()
            if clean.startswith(("- ", "* ")):
                label = clean[2:].strip()
                if label:
                    items.append(label)

    return items[:10]


def _relative_time(dt: datetime) -> str:
    """Return human-readable relative time string."""
    now = datetime.now()
    diff = now - dt
    seconds = int(diff.total_seconds())

    if seconds < 60:
        return "just now"
    elif seconds < 3600:
        m = seconds // 60
        return f"{m} min ago"
    elif seconds < 86400:
        h = seconds // 3600
        return f"{h} hour{'s' if h > 1 else ''} ago"
    elif seconds < 172800:
        return "yesterday"
    else:
        d = seconds // 86400
        return f"{d} days ago"


# ─── Projects & People readers ──────────────────────────────────────────────


def read_projects(ws: Path) -> list[dict]:
    """List all projects from {workspace}/projects/ directory."""
    projects_dir = ws / "projects"
    if not projects_dir.exists():
        return []

    projects = []
    for d in sorted(projects_dir.iterdir()):
        if not d.is_dir():
            continue
        name = d.name
        description = ""
        context_file = d / "context.md"
        if context_file.exists():
            lines = context_file.read_text(
                encoding="utf-8", errors="replace"
            ).splitlines()
            # First 2 non-empty, non-heading lines as description
            desc_lines = []
            for line in lines:
                stripped = line.strip()
                if stripped and not stripped.startswith("#"):
                    desc_lines.append(stripped)
                    if len(desc_lines) >= 2:
                        break
            description = " ".join(desc_lines)[:200]

        projects.append({"name": name, "dir": str(d), "description": description})

    return projects


def read_project_detail(ws: Path, project_name: str) -> dict:
    """Read full project details: context.md, decisions, meetings."""
    project_dir = ws / "projects" / project_name
    if not project_dir.is_dir():
        return {"name": project_name, "context": "", "decisions": [], "meetings": []}

    context = ""
    context_file = project_dir / "context.md"
    if context_file.exists():
        context = context_file.read_text(encoding="utf-8", errors="replace")

    decisions = []
    decisions_dir = project_dir / "decisions"
    if decisions_dir.is_dir():
        for f in sorted(decisions_dir.glob("*.md"), reverse=True):
            text = f.read_text(encoding="utf-8", errors="replace")
            first_line = ""
            for line in text.splitlines():
                stripped = line.strip().lstrip("#").strip()
                if stripped:
                    first_line = stripped
                    break
            decisions.append({"file": f.name, "title": first_line or f.stem})

    meetings = []
    meetings_dir = project_dir / "meetings"
    if meetings_dir.is_dir():
        for f in sorted(meetings_dir.glob("*.md"), reverse=True)[:5]:
            first_line = ""
            text = f.read_text(encoding="utf-8", errors="replace")
            for line in text.splitlines():
                stripped = line.strip().lstrip("#").strip()
                if stripped:
                    first_line = stripped
                    break
            meetings.append({"file": f.name, "title": first_line or f.stem})

    return {
        "name": project_name,
        "context": context,
        "decisions": decisions,
        "meetings": meetings,
    }


def read_people(ws: Path) -> list[dict]:
    """List all people from {workspace}/people/ directory."""
    people_dir = ws / "people"
    if not people_dir.exists():
        return []

    people = []
    for d in sorted(people_dir.iterdir()):
        if not d.is_dir():
            continue
        name = d.name
        role = ""
        profile_file = d / "profile.md"
        if profile_file.exists():
            text = profile_file.read_text(encoding="utf-8", errors="replace")
            # Look for role/title line
            for line in text.splitlines():
                stripped = line.strip()
                if stripped.startswith("#"):
                    continue
                low = stripped.lower()
                if any(kw in low for kw in ["role:", "title:", "position:"]):
                    role = stripped.split(":", 1)[1].strip() if ":" in stripped else ""
                    break
                elif stripped and not role:
                    # First non-empty non-heading line as fallback
                    role = stripped[:100]

        people.append({"name": name, "role": role})

    return people


def read_person_detail(ws: Path, person_name: str) -> dict:
    """Read full person profile."""
    person_dir = ws / "people" / person_name
    if not person_dir.is_dir():
        return {"name": person_name, "profile": ""}

    profile = ""
    profile_file = person_dir / "profile.md"
    if profile_file.exists():
        profile = profile_file.read_text(encoding="utf-8", errors="replace")

    return {"name": person_name, "profile": profile}


# ─── File browser ────────────────────────────────────────────────────────────

# Patterns to exclude from file browser
_EXCLUDE_NAMES = {".git", "__pycache__", ".sessions", "node_modules", ".venv", ".mypy_cache", ".pytest_cache", ".ruff_cache"}
_EXCLUDE_PATHS = {".claude/memory.db"}
_BINARY_EXTENSIONS = {".pyc", ".pyo", ".so", ".dylib", ".dll", ".exe", ".bin", ".db", ".sqlite", ".sqlite3", ".jpg", ".jpeg", ".png", ".gif", ".ico", ".bmp", ".tiff", ".webp", ".mp3", ".mp4", ".wav", ".avi", ".mov", ".zip", ".gz", ".tar", ".bz2", ".xz", ".7z", ".rar", ".woff", ".woff2", ".ttf", ".eot", ".pdf"}


def list_directory(ws: Path, rel_path: str = "") -> list[dict]:
    """List contents of a directory relative to workspace root.

    Returns a sorted list of dicts with keys: name, rel_path, is_dir, ext.
    Directories come first, then files, both sorted alphabetically.
    """
    target = ws / rel_path if rel_path else ws
    if not target.is_dir() or not str(target.resolve()).startswith(str(ws.resolve())):
        return []

    entries = []
    try:
        for item in target.iterdir():
            name = item.name
            item_rel = str(item.relative_to(ws))

            # Skip excluded names and hidden files in root
            if name in _EXCLUDE_NAMES:
                continue
            if item_rel in _EXCLUDE_PATHS:
                continue
            # Skip hidden files/dirs (dotfiles) except at root level for known ones
            if name.startswith(".") and name not in (".claude",):
                continue

            is_dir = item.is_dir()
            ext = item.suffix.lower() if not is_dir else ""

            # Skip binary files
            if not is_dir and ext in _BINARY_EXTENSIONS:
                continue

            entries.append({
                "name": name,
                "rel_path": item_rel,
                "is_dir": is_dir,
                "ext": ext,
            })
    except PermissionError:
        return []

    # Sort: directories first, then files, alphabetically
    entries.sort(key=lambda e: (not e["is_dir"], e["name"].lower()))
    return entries


def search_files(ws: Path, query: str, limit: int = 50) -> list[dict]:
    """Recursively search the workspace for files matching query in name or path.

    Returns a flat list of matching files sorted by relevance (name match first, then path match).
    """
    if not query or len(query.strip()) < 2:
        return []

    query = query.strip().lower()
    name_matches = []
    path_matches = []

    def walk(directory: Path, rel_prefix: str = ""):
        try:
            entries = sorted(directory.iterdir(), key=lambda p: p.name.lower())
        except (PermissionError, OSError):
            return

        for item in entries:
            name = item.name
            item_rel = f"{rel_prefix}/{name}".lstrip("/") if rel_prefix else name

            if name in _EXCLUDE_NAMES:
                continue
            if item_rel in _EXCLUDE_PATHS:
                continue
            if name.startswith(".") and name not in (".claude",):
                continue

            is_dir = item.is_dir()
            ext = item.suffix.lower() if not is_dir else ""

            if is_dir:
                walk(item, item_rel)
                continue

            if ext in _BINARY_EXTENSIONS:
                continue

            name_lower = name.lower()
            path_lower = item_rel.lower()

            if query in name_lower:
                name_matches.append({
                    "name": name,
                    "rel_path": item_rel,
                    "is_dir": False,
                    "ext": ext,
                })
            elif query in path_lower:
                path_matches.append({
                    "name": name,
                    "rel_path": item_rel,
                    "is_dir": False,
                    "ext": ext,
                })

            if len(name_matches) + len(path_matches) >= limit:
                return

    walk(ws)
    return (name_matches + path_matches)[:limit]


_CODE_EXTENSIONS = {".py", ".sh", ".js", ".ts", ".jsx", ".tsx", ".css", ".html", ".yml", ".yaml", ".toml", ".cfg", ".ini", ".rb", ".rs", ".go", ".java", ".c", ".h", ".cpp", ".hpp"}

_LANG_MAP = {
    ".py": "python", ".sh": "bash", ".js": "javascript", ".ts": "typescript",
    ".jsx": "javascript", ".tsx": "typescript", ".css": "css", ".html": "html",
    ".yml": "yaml", ".yaml": "yaml", ".toml": "toml", ".rb": "ruby",
    ".rs": "rust", ".go": "go", ".java": "java", ".c": "c", ".h": "c",
    ".cpp": "cpp", ".hpp": "cpp",
}


# ─── Syntax highlighting ─────────────────────────────────────────────────────

_KW = {k: set(v.split()) for k, v in {
    "python": "False None True and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield",
    "javascript": "async await break case catch class const continue default delete do else export extends false finally for from function if import in instanceof let new null of return super switch this throw true try typeof undefined var void while yield",
    "typescript": "abstract any async await boolean break case catch class const continue declare default delete do else enum export extends false finally for from function if implements import in instanceof interface let namespace new null number of private protected public readonly return static string super switch this throw true try type typeof undefined var void while yield",
    "go": "break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var true false nil iota",
    "rust": "as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self static struct super trait true type unsafe use where while",
    "bash": "case do done elif else esac fi for function if in select then until while return exit export local declare",
    "c": "auto break case char const continue default do double else enum extern float for goto if int long register return short signed sizeof static struct switch typedef union unsigned void volatile while",
    "cpp": "auto break case catch char class const continue default delete do double else enum explicit extern false float for friend goto if inline int long mutable namespace new nullptr operator private protected public return short signed sizeof static struct switch template this throw true try typedef typename union unsigned using virtual void volatile while",
    "java": "abstract assert boolean break byte case catch char class continue default do double else enum extends false final finally float for if implements import instanceof int interface long native new null package private protected public return short static super switch synchronized this throw throws transient true try void volatile while",
    "ruby": "alias and begin break case class def do else elsif end ensure false for if in module next nil not or redo rescue retry return self super then true undef unless until when while yield",
    "json": "true false null",
    "yaml": "true false null",
    "toml": "true false",
}.items()}

_HASH_CMT = {"python", "bash", "yaml", "toml", "ruby"}
_SLASH_CMT = {"javascript", "typescript", "go", "rust", "c", "cpp", "java"}
_BLOCK_CMT = {"javascript", "typescript", "go", "rust", "c", "cpp", "java", "css"}
_HL_CACHE: dict = {}


def tokenize_code(raw: str, language: str) -> str:
    """Regex-based syntax highlighting. Returns HTML with <span class='tok-*'> wrappers."""
    if not language or language not in _KW:
        return html_mod.escape(raw)

    if language not in _HL_CACHE:
        rules: list[tuple[str, str]] = []
        if language in _BLOCK_CMT:
            rules.append((r'/\*[\s\S]*?\*/', 'comment'))
        if language == 'html':
            rules.append((r'<!--[\s\S]*?-->', 'comment'))
        if language in _HASH_CMT:
            rules.append((r'#[^\n]*', 'comment'))
        elif language in _SLASH_CMT:
            rules.append((r'//[^\n]*', 'comment'))
        if language == 'python':
            rules.append((r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'', 'string'))
        if language in ('javascript', 'typescript'):
            rules.append((r'`(?:[^`\\]|\\.)*`', 'string'))
        rules.append((r'"(?:[^"\\\n]|\\.)*"|\'(?:[^\'\\\n]|\\.)*\'', 'string'))
        rules.append((r'\b(?:0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][+-]?\d+)?)\b', 'number'))
        kw = _KW.get(language)
        if kw:
            alt = '|'.join(re.escape(k) for k in sorted(kw, key=len, reverse=True))
            rules.append((rf'\b(?:{alt})\b', 'keyword'))
        if rules:
            combined = '|'.join(f'({p})' for p, _ in rules)
            _HL_CACHE[language] = (re.compile(combined, re.MULTILINE), [t for _, t in rules])
        else:
            _HL_CACHE[language] = None

    cached = _HL_CACHE[language]
    if not cached:
        return html_mod.escape(raw)

    regex, types = cached
    parts: list[str] = []
    last = 0
    for m in regex.finditer(raw):
        if m.start() > last:
            parts.append(html_mod.escape(raw[last:m.start()]))
        tok = ''
        for i, t in enumerate(types, 1):
            if m.group(i) is not None:
                tok = t
                break
        escaped = html_mod.escape(m.group())
        parts.append(f'<span class="tok-{tok}">{escaped}</span>' if tok else escaped)
        last = m.end()
    if last < len(raw):
        parts.append(html_mod.escape(raw[last:]))
    return ''.join(parts)


def read_file_content(ws: Path, rel_path: str) -> dict:
    """Read a file and return rendered content with metadata.

    Returns dict with keys: name, rel_path, breadcrumbs, render_type, content, language.
    render_type is one of: markdown, json, code, text, binary.
    """
    target = (ws / rel_path).resolve()
    if not str(target).startswith(str(ws.resolve())) or not target.is_file():
        return {"name": "", "rel_path": rel_path, "breadcrumbs": [], "render_type": "error", "content": "File not found.", "language": ""}

    ext = target.suffix.lower()
    name = target.name

    # Build breadcrumbs
    parts = Path(rel_path).parts
    breadcrumbs = []
    for i, part in enumerate(parts[:-1]):
        breadcrumbs.append({"name": part, "path": "/".join(parts[:i+1]), "is_dir": True})
    breadcrumbs.append({"name": name, "path": rel_path, "is_dir": False})

    # Check if binary
    if ext in _BINARY_EXTENSIONS:
        return {"name": name, "rel_path": rel_path, "breadcrumbs": breadcrumbs, "render_type": "binary", "content": "Binary file — cannot display.", "language": ""}

    # Try to read as text
    try:
        raw = target.read_text(encoding="utf-8", errors="strict")
    except (UnicodeDecodeError, ValueError):
        return {"name": name, "rel_path": rel_path, "breadcrumbs": breadcrumbs, "render_type": "binary", "content": "Binary file — cannot display.", "language": ""}
    except OSError:
        return {"name": name, "rel_path": rel_path, "breadcrumbs": breadcrumbs, "render_type": "error", "content": "Could not read file.", "language": ""}

    # Render based on type
    if ext == ".md":
        rendered = md_lib.markdown(
            raw,
            extensions=["tables", "fenced_code", "nl2br", "sane_lists"],
        )
        return {"name": name, "rel_path": rel_path, "breadcrumbs": breadcrumbs, "render_type": "markdown", "content": rendered, "language": ""}

    if ext == ".json":
        try:
            parsed = json.loads(raw)
            pretty = json.dumps(parsed, indent=2, ensure_ascii=False)
        except json.JSONDecodeError:
            pretty = raw
        return {"name": name, "rel_path": rel_path, "breadcrumbs": breadcrumbs, "render_type": "json", "content": tokenize_code(pretty, "json"), "language": "json"}

    if ext in _CODE_EXTENSIONS:
        lang = _LANG_MAP.get(ext, "")
        return {"name": name, "rel_path": rel_path, "breadcrumbs": breadcrumbs, "render_type": "code", "content": tokenize_code(raw, lang), "language": lang}

    if ext == ".txt":
        return {"name": name, "rel_path": rel_path, "breadcrumbs": breadcrumbs, "render_type": "text", "content": html_mod.escape(raw), "language": ""}

    # Fallback: try to display as plain text
    return {"name": name, "rel_path": rel_path, "breadcrumbs": breadcrumbs, "render_type": "text", "content": html_mod.escape(raw), "language": ""}


# ─── Memory search ──────────────────────────────────────────────────────────


_ICON_MAP = {
    "projects": "&#x1F4C1;",
    "people": "&#x1F464;",
    "me": "&#x1F4DD;",
    "raw": "&#x1F4E5;",
    "landings": "&#x1F3AF;",
}


def _file_icon(rel: str) -> str:
    """Return an icon based on the top-level directory of a relative path."""
    top = rel.split("/")[0] if "/" in rel else ""
    return _ICON_MAP.get(top, "&#x1F4C4;")


def _find_section_heading(lines: list[str], line_idx: int) -> str:
    """Walk backwards from line_idx to find the nearest markdown heading."""
    for i in range(line_idx, -1, -1):
        stripped = lines[i].strip()
        if stripped.startswith("#"):
            return stripped.lstrip("#").strip()
    return ""


def _highlight_query(text: str, query: str) -> str:
    """Wrap occurrences of query in <mark> tags (case-insensitive)."""
    escaped_q = re.escape(query)
    return re.sub(
        f"({escaped_q})",
        r'<mark class="search-highlight">\1</mark>',
        html_mod.escape(text),
        flags=re.IGNORECASE,
    )


def search_memory(ws: Path, query: str, limit: int = 20) -> list[dict]:
    """Search all markdown files in the workspace for query matches."""
    if not query or len(query.strip()) < 2:
        return []

    query = query.strip()
    pattern = re.compile(re.escape(query), re.IGNORECASE)
    results = []

    # Directories to search (skip .claude internals, raw/captures is low signal)
    search_dirs = ["projects", "people", "me"]
    # Also search top-level markdown files
    for md in ws.glob("*.md"):
        if md.is_file():
            search_dirs.append(md.name)

    files_to_search: list[Path] = []
    for d in search_dirs:
        target = ws / d
        if target.is_file() and target.suffix == ".md":
            files_to_search.append(target)
        elif target.is_dir():
            for md_file in target.rglob("*.md"):
                files_to_search.append(md_file)

    for filepath in files_to_search:
        try:
            text = filepath.read_text(encoding="utf-8", errors="replace")
        except (OSError, PermissionError):
            continue

        lines = text.splitlines()
        for idx, line in enumerate(lines):
            if pattern.search(line):
                rel = str(filepath.relative_to(ws))
                heading = _find_section_heading(lines, idx)

                # Build a snippet: the matching line + 1 line of context after
                snippet_lines = [line.strip()]
                if idx + 1 < len(lines) and lines[idx + 1].strip():
                    snippet_lines.append(lines[idx + 1].strip())
                snippet = " ".join(snippet_lines)[:200]

                results.append(
                    {
                        "file": rel,
                        "heading": heading,
                        "snippet": snippet,
                        "snippet_html": _highlight_query(snippet, query),
                        "icon": _file_icon(rel),
                    }
                )

                if len(results) >= limit:
                    return results

    return results


# ─── Formatting helpers ──────────────────────────────────────────────────────


def _format_inline(s: str) -> str:
    """Apply inline formatting (backticks, bold, newlines) to text outside <pre> blocks."""
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    s = s.replace("\n", "<br>")
    return s


# ─── App factory ─────────────────────────────────────────────────────────────


def create_app(workspace: Path | None = None) -> FastAPI:
    """Factory: build the FastAPI app wired to a workspace path."""
    ws = workspace or find_workspace()

    app = FastAPI(title="Hexagon UI")

    ui_dir = Path(__file__).resolve().parent
    app.mount("/static", StaticFiles(directory=ui_dir / "static"), name="static")

    templates = Jinja2Templates(directory=ui_dir / "templates")

    # Inject workspace path into every template context
    @app.middleware("http")
    async def add_workspace(request: Request, call_next):
        request.state.workspace = ws
        return await call_next(request)

    # ─── Page routes ───────────────────────────────────────────────────

    @app.get("/")
    async def index():
        return RedirectResponse(url="/dashboard")

    @app.get("/dashboard")
    async def dashboard(request: Request):
        return templates.TemplateResponse(
            "dashboard.html",
            {
                "request": request,
                "page": "dashboard",
                "workspace": str(ws),
            },
        )

    @app.get("/capture")
    async def capture_page(request: Request):
        return templates.TemplateResponse(
            "capture.html",
            {
                "request": request,
                "page": "capture",
                "workspace": str(ws),
            },
        )

    @app.get("/projects")
    async def projects(request: Request):
        return templates.TemplateResponse(
            "projects.html",
            {
                "request": request,
                "page": "projects",
                "workspace": str(ws),
            },
        )

    @app.get("/people")
    async def people(request: Request):
        return templates.TemplateResponse(
            "people.html",
            {
                "request": request,
                "page": "people",
                "workspace": str(ws),
            },
        )

    @app.get("/memory")
    async def memory(request: Request):
        return templates.TemplateResponse(
            "memory.html",
            {
                "request": request,
                "page": "memory",
                "workspace": str(ws),
            },
        )

    @app.get("/chat")
    async def chat(request: Request):
        return templates.TemplateResponse(
            "chat.html",
            {
                "request": request,
                "page": "chat",
                "workspace": str(ws),
            },
        )

    @app.get("/files")
    async def files_page(request: Request):
        return templates.TemplateResponse(
            "files.html",
            {
                "request": request,
                "page": "files",
                "workspace": str(ws),
            },
        )

    # ─── API routes (HTMX partials) ───────────────────────────────────

    @app.get("/api/files/tree")
    async def api_files_tree(request: Request, path: str = ""):
        """Return HTMX partial with directory listing."""
        entries = list_directory(ws, path)
        return templates.TemplateResponse(
            "partials/file_tree.html",
            {"request": request, "entries": entries, "parent_path": path},
        )

    @app.get("/api/files/search")
    async def api_files_search(request: Request, q: str = ""):
        """Return HTMX partial with file search results."""
        results = search_files(ws, q)
        return templates.TemplateResponse(
            "partials/file_search_results.html",
            {"request": request, "results": results, "query": q},
        )

    @app.get("/files/{file_path:path}")
    async def file_view(request: Request, file_path: str):
        """Render a single file with type-appropriate formatting."""
        file_data = read_file_content(ws, file_path)
        return templates.TemplateResponse(
            "file_view.html",
            {
                "request": request,
                "page": "files",
                "workspace": str(ws),
                "file": file_data,
            },
        )

    @app.get("/api/landings")
    async def api_landings(request: Request):
        items = read_landings(ws)
        return templates.TemplateResponse(
            "partials/landings.html",
            {"request": request, "items": items},
        )

    @app.get("/api/captures")
    async def api_captures(request: Request):
        captures = read_captures(ws)
        return templates.TemplateResponse(
            "partials/captures.html",
            {"request": request, "captures": captures},
        )

    @app.get("/api/todos")
    async def api_todos(request: Request):
        items = read_todos(ws)
        return templates.TemplateResponse(
            "partials/todos.html",
            {"request": request, "items": items},
        )

    @app.post("/api/capture")
    async def api_capture(request: Request, text: str = Form(...)):
        """Save a quick capture to raw/captures/ with YAML frontmatter."""
        captures_dir = ws / "raw" / "captures"
        captures_dir.mkdir(parents=True, exist_ok=True)

        now = datetime.now(timezone.utc)
        timestamp = now.strftime("%Y%m%d_%H%M%S")
        filename = f"{timestamp}.md"
        filepath = captures_dir / filename

        content = (
            f"---\ncaptured: {now.isoformat()}\nsource: hex-ui\n---\n\n{text.strip()}\n"
        )

        # Atomic write: write to tmp, then rename
        tmp_path = filepath.with_suffix(".tmp")
        tmp_path.write_text(content, encoding="utf-8")
        tmp_path.rename(filepath)

        return templates.TemplateResponse(
            "partials/capture_confirmation.html",
            {"request": request},
        )

    @app.get("/api/memory/search")
    async def api_memory_search(request: Request, q: str = ""):
        """Search workspace memory and return HTMX partial with results."""
        results = search_memory(ws, q)
        return templates.TemplateResponse(
            "partials/memory_results.html",
            {"request": request, "results": results, "query": q},
        )

    # ─── Projects API ──────────────────────────────────────────────────

    @app.get("/api/projects")
    async def api_projects(request: Request):
        """Return HTMX partial with project list."""
        projects = read_projects(ws)
        return templates.TemplateResponse(
            "partials/project_list.html",
            {"request": request, "projects": projects},
        )

    @app.get("/api/projects/{project_name}")
    async def api_project_detail(request: Request, project_name: str):
        """Return HTMX partial with expanded project detail."""
        detail = read_project_detail(ws, project_name)
        return templates.TemplateResponse(
            "partials/project_detail.html",
            {"request": request, "project": detail},
        )

    @app.get("/api/projects/{project_name}/edit")
    async def api_project_edit(request: Request, project_name: str):
        """Return HTMX partial with editable textarea for context.md."""
        detail = read_project_detail(ws, project_name)
        return templates.TemplateResponse(
            "partials/project_edit.html",
            {"request": request, "project": detail},
        )

    @app.post("/api/projects/{project_name}/save")
    async def api_project_save(
        request: Request, project_name: str, content: str = Form(...)
    ):
        """Save edited context.md back to disk."""
        project_dir = ws / "projects" / project_name
        if not project_dir.is_dir():
            return HTMLResponse("Project not found", status_code=404)

        context_file = project_dir / "context.md"
        tmp_path = context_file.with_suffix(".tmp")
        tmp_path.write_text(content, encoding="utf-8")
        tmp_path.rename(context_file)

        detail = read_project_detail(ws, project_name)
        return templates.TemplateResponse(
            "partials/project_detail.html",
            {"request": request, "project": detail},
        )

    # ─── People API ────────────────────────────────────────────────────

    @app.get("/api/people")
    async def api_people(request: Request):
        """Return HTMX partial with people list."""
        people = read_people(ws)
        return templates.TemplateResponse(
            "partials/people_list.html",
            {"request": request, "people": people},
        )

    @app.get("/api/people/{person_name}")
    async def api_person_detail(request: Request, person_name: str):
        """Return HTMX partial with expanded person profile."""
        detail = read_person_detail(ws, person_name)
        return templates.TemplateResponse(
            "partials/person_detail.html",
            {"request": request, "person": detail},
        )

    @app.get("/api/people/{person_name}/edit")
    async def api_person_edit(request: Request, person_name: str):
        """Return HTMX partial with editable textarea for profile.md."""
        detail = read_person_detail(ws, person_name)
        return templates.TemplateResponse(
            "partials/person_edit.html",
            {"request": request, "person": detail},
        )

    @app.post("/api/people/{person_name}/save")
    async def api_person_save(
        request: Request, person_name: str, content: str = Form(...)
    ):
        """Save edited profile.md back to disk."""
        person_dir = ws / "people" / person_name
        if not person_dir.is_dir():
            return HTMLResponse("Person not found", status_code=404)

        profile_file = person_dir / "profile.md"
        tmp_path = profile_file.with_suffix(".tmp")
        tmp_path.write_text(content, encoding="utf-8")
        tmp_path.rename(profile_file)

        detail = read_person_detail(ws, person_name)
        return templates.TemplateResponse(
            "partials/person_detail.html",
            {"request": request, "person": detail},
        )

    @app.get("/api/landings/stream")
    async def landings_stream(request: Request):
        """SSE endpoint that pushes landing updates when the file changes."""

        async def event_generator():
            last_mtime = 0.0
            today = datetime.now().strftime("%Y-%m-%d")
            landings_file = ws / "landings" / f"{today}.md"

            while True:
                if await request.is_disconnected():
                    break

                current_mtime = 0.0
                if landings_file.exists():
                    current_mtime = landings_file.stat().st_mtime

                if current_mtime != last_mtime:
                    last_mtime = current_mtime
                    items = read_landings(ws)
                    # Render the partial inline
                    html_parts = []
                    for item in items:
                        if item["status"] == "done":
                            icon = "&#x2705;"
                        elif item["status"] == "in_progress":
                            icon = "&#x1F504;"
                        else:
                            icon = "&#x2B1C;"
                        html_parts.append(
                            f'<div class="landing-item landing-{item["status"]}">'
                            f'<span class="landing-icon">{icon}</span>'
                            f'<span class="landing-label">{item["label"]}</span>'
                            "</div>"
                        )
                    html = (
                        "".join(html_parts)
                        if html_parts
                        else '<p class="placeholder-text">No landings for today.</p>'
                    )
                    # SSE format: data lines, then blank line
                    yield f"data: {html}\n\n"

                await asyncio.sleep(2)

        return StreamingResponse(
            event_generator(),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
            },
        )

    # ─── Chat API ─────────────────────────────────────────────────────

    @app.post("/api/chat/stream")
    async def api_chat_stream(request: Request, message: str = Form(...)):
        """Stream a chat response via SSE using claude CLI streaming output."""
        message = message.strip()
        if not message:
            async def empty_gen():
                yield 'data: {"error": "Please type a message."}\n\n'
            return StreamingResponse(empty_gen(), media_type="text/event-stream")

        claude_cmd = shutil.which("claude") or shutil.which("cgo")
        if not claude_cmd:
            async def no_cli_gen():
                yield 'data: {"error": "Claude CLI not found. Install Claude Code to enable chat."}\n\n'
            return StreamingResponse(no_cli_gen(), media_type="text/event-stream")

        prompt = (
            f"You are a personal AI agent for a hexagon workspace at {ws}. "
            f"The workspace contains projects, people, landings, captures, and todos. "
            f"Be concise, direct, and helpful. "
            f"User says: {message}"
        )

        env = {k: v for k, v in os.environ.items() if not k.startswith("CLAUDE")}

        async def stream_generator():
            proc = None
            try:
                proc = await asyncio.create_subprocess_exec(
                    claude_cmd, "-p",
                    "--output-format", "stream-json",
                    "--verbose",
                    "--include-partial-messages",
                    prompt,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                    cwd=str(ws),
                    env=env,
                )

                deadline = asyncio.get_event_loop().time() + 120  # 120s timeout

                while True:
                    # Check client disconnect
                    if await request.is_disconnected():
                        proc.kill()
                        break

                    # Check timeout
                    if asyncio.get_event_loop().time() > deadline:
                        proc.kill()
                        yield 'data: {"error": "Request timed out."}\n\n'
                        break

                    try:
                        line_bytes = await asyncio.wait_for(
                            proc.stdout.readline(), timeout=0.5
                        )
                    except asyncio.TimeoutError:
                        # No data yet — check if process exited
                        if proc.returncode is not None:
                            break
                        continue

                    if not line_bytes:
                        # EOF — process finished
                        break

                    line = line_bytes.decode("utf-8", errors="replace").strip()
                    if not line:
                        continue

                    try:
                        data = json.loads(line)
                        # NDJSON format: {"type": "stream_event", "event": {"type": "content_block_delta", ...}}
                        event = None
                        if data.get("type") == "stream_event":
                            event = data.get("event", {})
                        elif data.get("type") == "content_block_delta":
                            # Fallback: handle unwrapped format
                            event = data

                        if event and event.get("type") == "content_block_delta":
                            delta = event.get("delta", {})
                            if delta.get("type") == "text_delta":
                                text = delta.get("text", "")
                                if text:
                                    chunk = json.dumps({"t": text})
                                    yield f"data: {chunk}\n\n"
                    except json.JSONDecodeError:
                        continue

                # Wait for process to finish and check for errors
                if proc.returncode is None:
                    await proc.wait()
                if proc.returncode and proc.returncode != 0:
                    stderr_out = await proc.stderr.read()
                    if stderr_out:
                        err_text = stderr_out.decode("utf-8", errors="replace").strip()[:200]
                        yield f'data: {json.dumps({"error": err_text})}\n\n'

                yield 'data: {"done": true}\n\n'

            except FileNotFoundError:
                yield 'data: {"error": "Claude CLI not found."}\n\n'
            except Exception as exc:
                yield f'data: {json.dumps({"error": str(exc)[:200]})}\n\n'
            finally:
                if proc and proc.returncode is None:
                    proc.kill()
                    await proc.wait()

        return StreamingResponse(
            stream_generator(),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
                "X-Accel-Buffering": "no",
            },
        )

    @app.post("/api/chat")
    async def api_chat(request: Request, message: str = Form(...)):
        """Send a message to the agent and return the response."""
        message = message.strip()
        if not message:
            return templates.TemplateResponse(
                "partials/chat_response.html",
                {"request": request, "response": "Please type a message."},
            )

        # Check if claude CLI is available
        claude_cmd = shutil.which("claude") or shutil.which("cgo")
        if not claude_cmd:
            return templates.TemplateResponse(
                "partials/chat_response.html",
                {
                    "request": request,
                    "response": "Claude CLI not found. Install Claude Code to enable chat.",
                },
            )

        # Build prompt with workspace context
        prompt = (
            f"You are a personal AI agent for a hexagon workspace at {ws}. "
            f"The workspace contains projects, people, landings, captures, and todos. "
            f"Be concise, direct, and helpful. "
            f"User says: {message}"
        )

        try:
            env = {k: v for k, v in os.environ.items() if not k.startswith("CLAUDE")}
            result = subprocess.run(
                [claude_cmd, "-p", prompt],
                capture_output=True,
                text=True,
                timeout=120,
                cwd=str(ws),
                env=env,
            )
            response_text = result.stdout.strip() if result.stdout else ""
            if not response_text and result.stderr:
                response_text = f"Error: {result.stderr.strip()[:200]}"
            if not response_text:
                response_text = "No response received. The agent may be unavailable."
        except subprocess.TimeoutExpired:
            response_text = "Request timed out. Try a simpler question."
        except FileNotFoundError:
            response_text = "Claude CLI not found. Install Claude Code to enable chat."
        except Exception as exc:
            response_text = f"Error: {str(exc)[:200]}"

        # Escape HTML in response, then convert markdown-like formatting
        safe_response = html_mod.escape(response_text)
        # Convert triple-backtick fenced code blocks to <pre><code>
        # (must run BEFORE single-backtick conversion)
        safe_response = re.sub(
            r"```\w*\n(.*?)```",
            lambda m: "<pre><code>" + m.group(1) + "</code></pre>",
            safe_response,
            flags=re.DOTALL,
        )
        # Apply inline formatting only OUTSIDE <pre> blocks
        parts = re.split(r"(<pre><code>.*?</code></pre>)", safe_response, flags=re.DOTALL)
        safe_response = "".join(
            part if part.startswith("<pre>") else _format_inline(part)
            for part in parts
        )

        return templates.TemplateResponse(
            "partials/chat_response.html",
            {"request": request, "response": safe_response},
        )

    return app


# ─── CLI entry point ─────────────────────────────────────────────────────────


def main():
    parser = argparse.ArgumentParser(description="Hexagon Web UI server")
    parser.add_argument(
        "--port", type=int, default=3141, help="Port to serve on (default: 3141)"
    )
    parser.add_argument(
        "--host", default="127.0.0.1", help="Host to bind (default: 127.0.0.1)"
    )
    parser.add_argument(
        "--workspace",
        type=str,
        default=None,
        help="Workspace path (auto-detected if omitted)",
    )
    parser.add_argument(
        "--tunnel",
        action="store_true",
        help="Print SSH tunnel instructions for remote access",
    )
    args = parser.parse_args()

    ws = Path(args.workspace) if args.workspace else find_workspace()
    if not ws.exists():
        print(f"Error: workspace not found at {ws}", file=sys.stderr)
        sys.exit(1)

    print(f"Hexagon UI serving workspace: {ws}")
    print(f"Open http://{args.host}:{args.port}")

    if args.tunnel or os.environ.get("SSH_CONNECTION") or os.environ.get("SSH_TTY"):
        import socket

        hostname = socket.getfqdn()
        user = os.environ.get("USER", "you")
        print()
        print("=" * 59)
        print("  Hexagon UI is running on this remote server.")
        print()
        print("  To access from your local machine, open a NEW terminal")
        print("  and run:")
        print()
        print(f"    ssh -L {args.port}:localhost:{args.port} {user}@{hostname}")
        print()
        print(f"  Then open: http://localhost:{args.port}")
        print("=" * 59)
        print()

    import uvicorn

    app = create_app(workspace=ws)
    uvicorn.run(app, host=args.host, port=args.port, log_level="info")


if __name__ == "__main__":
    main()
