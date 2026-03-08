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

    # ─── API routes (HTMX partials) ───────────────────────────────────

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
        # Convert backtick code blocks to <code>
        safe_response = re.sub(r"`([^`]+)`", r"<code>\1</code>", safe_response)
        # Convert **bold** to <strong>
        safe_response = re.sub(
            r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", safe_response
        )
        # Convert newlines to <br>
        safe_response = safe_response.replace("\n", "<br>")

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
