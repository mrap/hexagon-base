#!/usr/bin/env python3
"""BOI queue watcher — polls ~/.boi/queue/ for spec completions and sends ntfy push notifications."""

import json
import logging
import os
import pathlib
import re
import signal
import sys
import time
import urllib.request
import urllib.error

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
CONFIG_DIR = pathlib.Path.home() / ".config" / "hex"
NTFY_CONFIG = CONFIG_DIR / "notifications.yaml"
NOTIFIED_DB = CONFIG_DIR / "notified.json"
LOG_FILE = CONFIG_DIR / "watcher.log"
PID_FILE = CONFIG_DIR / "watcher.pid"
QUEUE_DIR = pathlib.Path.home() / ".boi" / "queue"

POLL_INTERVAL = 30  # seconds

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stderr),
    ],
)
log = logging.getLogger("hex-watcher")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def parse_ntfy_config() -> dict:
    """Parse the simple YAML config without PyYAML."""
    if not NTFY_CONFIG.exists():
        log.error("ntfy config not found at %s", NTFY_CONFIG)
        sys.exit(1)

    text = NTFY_CONFIG.read_text()
    topic = server = None
    for line in text.splitlines():
        line = line.strip()
        m = re.match(r'topic:\s*"?([^"]+)"?', line)
        if m:
            topic = m.group(1).strip()
        m = re.match(r'server:\s*"?([^"]+)"?', line)
        if m:
            server = m.group(1).strip().rstrip("/")
    if not topic or not server:
        log.error("ntfy config missing topic or server")
        sys.exit(1)
    return {"topic": topic, "server": server}


def load_notified() -> dict:
    """Load the set of already-notified spec IDs with their statuses."""
    if not NOTIFIED_DB.exists():
        return {}
    try:
        return json.loads(NOTIFIED_DB.read_text())
    except (json.JSONDecodeError, OSError):
        return {}


def save_notified(data: dict) -> None:
    """Atomically save the notified DB."""
    tmp = NOTIFIED_DB.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n")
    tmp.rename(NOTIFIED_DB)


def send_ntfy(cfg: dict, title: str, message: str, priority: int = 3, tags: str = "") -> bool:
    """POST a notification to ntfy.sh. Returns True on success."""
    url = f"{cfg['server']}/{cfg['topic']}"
    headers = {
        "Title": title,
        "Priority": str(priority),
    }
    if tags:
        headers["Tags"] = tags

    req = urllib.request.Request(
        url,
        data=message.encode("utf-8"),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            log.info("ntfy sent (%d): %s — %s", resp.status, title, message)
            return True
    except (urllib.error.URLError, OSError) as exc:
        log.warning("ntfy send failed: %s", exc)
        return False


def extract_spec_title(spec_path: str) -> str:
    """Read the first markdown heading from a spec file."""
    try:
        p = pathlib.Path(spec_path)
        if p.exists():
            for line in p.read_text().splitlines():
                if line.startswith("# "):
                    return line[2:].strip()
    except OSError:
        pass
    return ""


def scan_queue(cfg: dict, notified: dict) -> dict:
    """Scan all q-*.json files in the queue directory. Returns updated notified dict."""
    if not QUEUE_DIR.is_dir():
        return notified

    changed = False
    for entry in QUEUE_DIR.iterdir():
        if not entry.name.endswith(".json") or not entry.name.startswith("q-"):
            continue
        # Skip iteration/telemetry JSON files — only look at the main q-NNN.json
        if ".iteration-" in entry.name or ".telemetry" in entry.name:
            continue

        try:
            data = json.loads(entry.read_text())
        except (json.JSONDecodeError, OSError) as exc:
            log.debug("Skipping %s: %s", entry.name, exc)
            continue

        spec_id = data.get("id", entry.stem)
        status = data.get("status", "")

        if status not in ("completed", "failed"):
            continue

        # Already notified for this status?
        if notified.get(spec_id) == status:
            continue

        # Build notification
        tasks_done = data.get("tasks_done", "?")
        tasks_total = data.get("tasks_total", "?")
        iteration = data.get("iteration", "?")
        spec_path = data.get("spec_path", "")
        title_text = extract_spec_title(spec_path) or spec_id

        if status == "completed":
            title = f"BOI: {title_text}"
            message = f"Completed ({tasks_done}/{tasks_total} tasks, {iteration} iterations)"
            tags = "white_check_mark"
            priority = 3
        else:
            message = f"Failed at iteration {iteration} ({tasks_done}/{tasks_total} tasks done)"
            title = f"BOI: {title_text}"
            tags = "x"
            priority = 4  # higher priority for failures

        if send_ntfy(cfg, title, message, priority=priority, tags=tags):
            notified[spec_id] = status
            changed = True
            log.info("Notified: %s -> %s", spec_id, status)

    if changed:
        save_notified(notified)

    return notified


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

_running = True


def _handle_signal(signum, _frame):
    global _running
    log.info("Received signal %d, shutting down", signum)
    _running = False


def write_pid():
    """Write PID file atomically."""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    tmp = PID_FILE.with_suffix(".tmp")
    tmp.write_text(str(os.getpid()) + "\n")
    tmp.rename(PID_FILE)


def remove_pid():
    try:
        PID_FILE.unlink(missing_ok=True)
    except OSError:
        pass


def main():
    global _running

    CONFIG_DIR.mkdir(parents=True, exist_ok=True)

    signal.signal(signal.SIGTERM, _handle_signal)
    signal.signal(signal.SIGINT, _handle_signal)

    cfg = parse_ntfy_config()
    log.info("hex-watcher starting — polling %s every %ds", QUEUE_DIR, POLL_INTERVAL)
    log.info("ntfy topic: %s/%s", cfg["server"], cfg["topic"])

    write_pid()

    try:
        notified = load_notified()
        while _running:
            notified = scan_queue(cfg, notified)
            # Sleep in small increments so we respond to signals quickly
            for _ in range(POLL_INTERVAL * 2):
                if not _running:
                    break
                time.sleep(0.5)
    finally:
        remove_pid()
        log.info("hex-watcher stopped")


if __name__ == "__main__":
    main()
