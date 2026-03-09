#!/usr/bin/env python3
"""hex-bot — Telegram bot for hexagon workspace.

stdlib-only implementation using Telegram Bot API via urllib.
Features: BOI control, Claude chat, capture, outbound notifications.

Usage:
    python3 hex-bot.py          # Run bot (long-polling)
    python3 hex-bot.py --test   # Dry-run self-test (no network)
"""

import json
import logging
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Any, Optional

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [hex-bot] %(levelname)s %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("hex-bot")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
HEX_DIR = Path(__file__).resolve().parents[2]  # …/hex
CONFIG_PATH = Path.home() / ".config" / "hex" / "telegram.yaml"
CAPTURES_DIR = HEX_DIR / "raw" / "captures"
BOI_CMD = os.environ.get("BOI_CMD", f"bash {Path.home()}/.boi/src/boi.sh")
POLL_TIMEOUT = 30  # seconds for long-polling


def _parse_yaml_simple(path: Path) -> dict:
    """Minimal YAML parser for flat key: value files (no nested structures)."""
    data: dict[str, Any] = {}
    if not path.exists():
        return data
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if ":" not in line:
                continue
            key, _, val = line.partition(":")
            key = key.strip()
            val = val.strip().strip('"').strip("'")
            # Handle env var references like ${VAR}
            env_match = re.match(r"^\$\{(\w+)\}$", val)
            if env_match:
                val = os.environ.get(env_match.group(1), "")
            # Handle list values like [123, 456]
            if val.startswith("[") and val.endswith("]"):
                inner = val[1:-1]
                data[key] = [x.strip().strip('"').strip("'") for x in inner.split(",") if x.strip()]
            else:
                data[key] = val
    return data


def load_config() -> dict:
    """Load config from yaml + env vars. Env vars take precedence."""
    cfg = _parse_yaml_simple(CONFIG_PATH)
    cfg["bot_token"] = os.environ.get("HEX_BOT_TOKEN", cfg.get("bot_token", ""))
    raw_ids = os.environ.get("HEX_ALLOWED_USER_IDS", "")
    if raw_ids:
        cfg["allowed_user_ids"] = [x.strip() for x in raw_ids.split(",") if x.strip()]
    elif "allowed_user_ids" not in cfg:
        cfg["allowed_user_ids"] = []
    cfg["chat_id"] = os.environ.get("HEX_CHAT_ID", cfg.get("chat_id", ""))
    return cfg


# ---------------------------------------------------------------------------
# Telegram Bot API (stdlib urllib)
# ---------------------------------------------------------------------------
class TelegramAPI:
    """Minimal Telegram Bot API client using urllib."""

    BASE = "https://api.telegram.org/bot{token}/{method}"

    def __init__(self, token: str):
        if not token:
            raise ValueError("Bot token is required. Set HEX_BOT_TOKEN env var.")
        self.token = token

    def _url(self, method: str) -> str:
        return self.BASE.format(token=self.token, method=method)

    def call(self, method: str, data: Optional[dict] = None, timeout: int = 60) -> dict:
        """Call a Telegram Bot API method. Returns the parsed JSON response."""
        url = self._url(method)
        payload = json.dumps(data or {}).encode("utf-8")
        req = urllib.request.Request(
            url,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                body = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            body_text = e.read().decode("utf-8", errors="replace")
            log.error("Telegram API %s returned %s: %s", method, e.code, body_text)
            return {"ok": False, "error_code": e.code, "description": body_text}
        except urllib.error.URLError as e:
            log.error("Telegram API %s network error: %s", method, e.reason)
            return {"ok": False, "description": str(e.reason)}
        return body

    def send_message(
        self,
        chat_id: str | int,
        text: str,
        parse_mode: str = "Markdown",
        reply_markup: Optional[dict] = None,
    ) -> dict:
        data: dict[str, Any] = {"chat_id": chat_id, "text": text, "parse_mode": parse_mode}
        if reply_markup:
            data["reply_markup"] = reply_markup
        return self.call("sendMessage", data)

    def edit_message(
        self,
        chat_id: str | int,
        message_id: int,
        text: str,
        parse_mode: str = "Markdown",
        reply_markup: Optional[dict] = None,
    ) -> dict:
        data: dict[str, Any] = {
            "chat_id": chat_id,
            "message_id": message_id,
            "text": text,
            "parse_mode": parse_mode,
        }
        if reply_markup:
            data["reply_markup"] = reply_markup
        return self.call("editMessageText", data)

    def answer_callback(self, callback_query_id: str, text: str = "") -> dict:
        return self.call("answerCallbackQuery", {"callback_query_id": callback_query_id, "text": text})

    def get_updates(self, offset: Optional[int] = None, timeout: int = POLL_TIMEOUT) -> list:
        data: dict[str, Any] = {"timeout": timeout, "allowed_updates": ["message", "callback_query"]}
        if offset is not None:
            data["offset"] = offset
        result = self.call("getUpdates", data, timeout=timeout + 10)
        if result.get("ok"):
            return result.get("result", [])
        return []


# ---------------------------------------------------------------------------
# Capture helper
# ---------------------------------------------------------------------------
def save_capture(text: str, source: str = "telegram") -> Path:
    """Save a capture in the standard hex format. Returns the file path."""
    CAPTURES_DIR.mkdir(parents=True, exist_ok=True)
    now = datetime.now()
    ts = now.strftime("%Y-%m-%dT%H:%M:%S")
    filename = now.strftime("%Y-%m-%d_%H-%M-%S") + ".md"
    outfile = CAPTURES_DIR / filename
    tmpfile = outfile.with_suffix(".md.tmp")
    content = f"---\ncaptured: {ts}\nsource: {source}\n---\n\n{text}\n"
    tmpfile.write_text(content)
    tmpfile.rename(outfile)
    return outfile


# ---------------------------------------------------------------------------
# Claude chat helper
# ---------------------------------------------------------------------------
def run_claude(prompt: str, timeout_sec: int = 120) -> str:
    """Run claude -p with the given prompt. Strips CLAUDE* env vars."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("CLAUDE")}
    env["PATH"] = os.environ.get("PATH", "/usr/bin:/bin")
    try:
        result = subprocess.run(
            ["claude", "-p", prompt],
            capture_output=True,
            text=True,
            timeout=timeout_sec,
            env=env,
            cwd=str(HEX_DIR),
        )
        output = result.stdout.strip()
        if not output and result.stderr:
            output = f"(error) {result.stderr.strip()[:500]}"
        return output or "(no response)"
    except subprocess.TimeoutExpired:
        return "(timed out after {}s)".format(timeout_sec)
    except FileNotFoundError:
        return "(claude command not found)"
    except Exception as e:
        return f"(error: {e})"


# ---------------------------------------------------------------------------
# BOI command helpers
# ---------------------------------------------------------------------------
def run_boi(args: str, timeout_sec: int = 30) -> str:
    """Run a boi subcommand and return output."""
    parts = BOI_CMD.split() + args.split()
    env = {k: v for k, v in os.environ.items() if not k.startswith("CLAUDE")}
    env["PATH"] = os.environ.get("PATH", "/usr/bin:/bin")
    try:
        result = subprocess.run(
            parts,
            capture_output=True,
            text=True,
            timeout=timeout_sec,
            env=env,
        )
        return (result.stdout + result.stderr).strip() or "(no output)"
    except Exception as e:
        return f"(error: {e})"


def format_boi_status(raw: str) -> str:
    """Add emoji formatting to boi status output."""
    lines = raw.split("\n")
    formatted = []
    for line in lines:
        if "RUNNING" in line.upper():
            formatted.append("🔄 " + line)
        elif "DONE" in line.upper() or "COMPLETED" in line.upper():
            formatted.append("✅ " + line)
        elif "FAILED" in line.upper() or "ERROR" in line.upper():
            formatted.append("❌ " + line)
        elif "PENDING" in line.upper():
            formatted.append("⏳ " + line)
        elif "CANCELLED" in line.upper() or "CANCELED" in line.upper():
            formatted.append("🚫 " + line)
        else:
            formatted.append(line)
    return "\n".join(formatted)


# ---------------------------------------------------------------------------
# Notification export (for other scripts to import)
# ---------------------------------------------------------------------------
_notification_api: Optional[TelegramAPI] = None
_notification_chat_id: Optional[str] = None


def send_notification(title: str, body: str, priority: int = 3) -> bool:
    """Send a notification to the configured Telegram chat.

    Can be imported by other scripts:
        from hex_bot import send_notification
        send_notification("Build done", "All tests passed")

    Falls back to ntfy.sh if Telegram fails.
    Returns True on success.
    """
    # Try Telegram first
    tg_ok = _send_telegram_notification(title, body)
    if tg_ok:
        return True

    # Fallback: ntfy.sh
    return _send_ntfy_notification(title, body, priority)


def _send_telegram_notification(title: str, body: str) -> bool:
    """Send via Telegram Bot API."""
    cfg = load_config()
    token = cfg.get("bot_token", "")
    chat_id = cfg.get("chat_id", "")
    if not token or not chat_id:
        return False
    try:
        api = TelegramAPI(token)
        text = f"*{_escape_md(title)}*\n{_escape_md(body)}"
        result = api.send_message(chat_id, text)
        return result.get("ok", False)
    except Exception as e:
        log.warning("Telegram notification failed: %s", e)
        return False


def _send_ntfy_notification(title: str, body: str, priority: int = 3) -> bool:
    """Fallback: send via hex-notify.sh (ntfy.sh)."""
    notify_script = HEX_DIR / ".claude" / "scripts" / "hex-notify.sh"
    if not notify_script.exists():
        log.warning("ntfy fallback: hex-notify.sh not found")
        return False
    try:
        result = subprocess.run(
            ["bash", str(notify_script), title, body, str(priority)],
            capture_output=True,
            text=True,
            timeout=15,
        )
        return result.returncode == 0
    except Exception as e:
        log.warning("ntfy fallback failed: %s", e)
        return False


def _escape_md(text: str) -> str:
    """Escape Markdown special chars for Telegram."""
    for ch in r"_*[]()~`>#+-=|{}.!":
        text = text.replace(ch, "\\" + ch)
    return text


# ---------------------------------------------------------------------------
# Message handlers
# ---------------------------------------------------------------------------
class HexBot:
    """Telegram bot for hexagon workspace."""

    def __init__(self, api: TelegramAPI, allowed_ids: list[str], chat_id: str = ""):
        self.api = api
        self.allowed_ids = set(str(uid) for uid in allowed_ids)
        self.chat_id = chat_id
        self._pending_dispatch: dict[int, str] = {}  # user_id -> spec_text
        self._pending_cancel: dict[int, str] = {}  # user_id -> queue_id

    def is_authorized(self, user_id: int) -> bool:
        return str(user_id) in self.allowed_ids

    def _persist_chat_id(self, chat_id: str | int) -> None:
        """Save chat_id to config for outbound notifications."""
        self.chat_id = str(chat_id)
        CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
        if CONFIG_PATH.exists():
            content = CONFIG_PATH.read_text()
            if "chat_id:" in content:
                content = re.sub(r"chat_id:.*", f"chat_id: {self.chat_id}", content)
            else:
                content += f"\nchat_id: {self.chat_id}\n"
        else:
            content = f"chat_id: {self.chat_id}\n"
        tmp = CONFIG_PATH.with_suffix(".yaml.tmp")
        tmp.write_text(content)
        tmp.rename(CONFIG_PATH)

    def handle_update(self, update: dict) -> None:
        """Route an update to the appropriate handler."""
        if "callback_query" in update:
            self._handle_callback(update["callback_query"])
            return
        msg = update.get("message")
        if not msg:
            return
        user = msg.get("from", {})
        user_id = user.get("id", 0)
        chat_id = msg.get("chat", {}).get("id", 0)
        text = msg.get("text", "").strip()

        # Auth check — silent drop
        if not self.is_authorized(user_id):
            log.info("Unauthorized user %s dropped", user_id)
            return

        # Persist chat_id on first authorized message
        if not self.chat_id:
            self._persist_chat_id(chat_id)

        if not text:
            return

        # Route commands
        if text.startswith("/"):
            self._handle_command(chat_id, user_id, text)
        else:
            self._handle_freetext(chat_id, text)

    def _handle_command(self, chat_id: int, user_id: int, text: str) -> None:
        parts = text.split(maxsplit=1)
        cmd = parts[0].lower().split("@")[0]  # strip @botname
        args = parts[1] if len(parts) > 1 else ""

        if cmd == "/start":
            self.api.send_message(chat_id, "Hex bot ready. Send me anything or use /status, /dispatch, /log, /cancel.")
        elif cmd == "/status":
            self._cmd_status(chat_id)
        elif cmd == "/dispatch":
            self._cmd_dispatch(chat_id, user_id, args)
        elif cmd == "/log":
            self._cmd_log(chat_id, args)
        elif cmd == "/cancel":
            self._cmd_cancel(chat_id, user_id, args)
        elif cmd == "/help":
            self.api.send_message(
                chat_id,
                "*Hex Bot Commands*\n"
                "/status — BOI queue status\n"
                "/dispatch <spec> — Dispatch a BOI spec\n"
                "/log <id> — View last 50 lines of a spec log\n"
                "/cancel <id> — Cancel a running spec\n"
                "Free text — Chat with Claude",
            )
        else:
            self.api.send_message(chat_id, f"Unknown command: {cmd}. Try /help")

    def _cmd_status(self, chat_id: int) -> None:
        raw = run_boi("status")
        formatted = format_boi_status(raw)
        markup = {
            "inline_keyboard": [[{"text": "🔄 Refresh", "callback_data": "refresh_status"}]]
        }
        self.api.send_message(chat_id, f"```\n{formatted}\n```", reply_markup=markup)

    def _cmd_dispatch(self, chat_id: int, user_id: int, args: str) -> None:
        if not args:
            self.api.send_message(chat_id, "Usage: /dispatch <spec description>")
            return
        self._pending_dispatch[user_id] = args
        markup = {
            "inline_keyboard": [
                [
                    {"text": "✅ Confirm", "callback_data": f"dispatch_confirm_{user_id}"},
                    {"text": "❌ Cancel", "callback_data": f"dispatch_cancel_{user_id}"},
                ]
            ]
        }
        preview = args[:200] + ("..." if len(args) > 200 else "")
        self.api.send_message(chat_id, f"Dispatch this spec?\n\n`{preview}`", reply_markup=markup)

    def _cmd_log(self, chat_id: int, args: str) -> None:
        queue_id = args.strip()
        if not queue_id:
            self.api.send_message(chat_id, "Usage: /log <queue-id>")
            return
        raw = run_boi(f"log {queue_id}")
        # Truncate to last 50 lines
        lines = raw.split("\n")
        if len(lines) > 50:
            lines = lines[-50:]
            raw = "...(truncated)...\n" + "\n".join(lines)
        else:
            raw = "\n".join(lines)
        # Telegram message limit is 4096 chars
        if len(raw) > 3900:
            raw = raw[-3900:]
        self.api.send_message(chat_id, f"```\n{raw}\n```")

    def _cmd_cancel(self, chat_id: int, user_id: int, args: str) -> None:
        queue_id = args.strip()
        if not queue_id:
            self.api.send_message(chat_id, "Usage: /cancel <queue-id>")
            return
        self._pending_cancel[user_id] = queue_id
        markup = {
            "inline_keyboard": [
                [
                    {"text": "✅ Confirm Cancel", "callback_data": f"cancel_confirm_{user_id}"},
                    {"text": "❌ Keep Running", "callback_data": f"cancel_abort_{user_id}"},
                ]
            ]
        }
        self.api.send_message(chat_id, f"Cancel spec `{queue_id}`?", reply_markup=markup)

    def _handle_callback(self, cb: dict) -> None:
        cb_id = cb.get("id", "")
        data = cb.get("data", "")
        msg = cb.get("message", {})
        chat_id = msg.get("chat", {}).get("id", 0)
        user = cb.get("from", {})
        user_id = user.get("id", 0)

        if not self.is_authorized(user_id):
            self.api.answer_callback(cb_id, "Unauthorized")
            return

        if data == "refresh_status":
            self.api.answer_callback(cb_id, "Refreshing...")
            raw = run_boi("status")
            formatted = format_boi_status(raw)
            markup = {
                "inline_keyboard": [[{"text": "🔄 Refresh", "callback_data": "refresh_status"}]]
            }
            self.api.edit_message(chat_id, msg.get("message_id", 0), f"```\n{formatted}\n```", reply_markup=markup)

        elif data.startswith("dispatch_confirm_"):
            spec_text = self._pending_dispatch.pop(user_id, None)
            if spec_text:
                self.api.answer_callback(cb_id, "Dispatching...")
                result = run_boi(f"dispatch {spec_text}")
                self.api.edit_message(chat_id, msg.get("message_id", 0), f"Dispatched.\n```\n{result[:3000]}\n```")
            else:
                self.api.answer_callback(cb_id, "No pending dispatch")

        elif data.startswith("dispatch_cancel_"):
            self._pending_dispatch.pop(user_id, None)
            self.api.answer_callback(cb_id, "Cancelled")
            self.api.edit_message(chat_id, msg.get("message_id", 0), "Dispatch cancelled.")

        elif data.startswith("cancel_confirm_"):
            queue_id = self._pending_cancel.pop(user_id, None)
            if queue_id:
                self.api.answer_callback(cb_id, "Cancelling...")
                result = run_boi(f"cancel {queue_id}")
                self.api.edit_message(chat_id, msg.get("message_id", 0), f"Cancel result:\n```\n{result[:3000]}\n```")
            else:
                self.api.answer_callback(cb_id, "No pending cancel")

        elif data.startswith("cancel_abort_"):
            self._pending_cancel.pop(user_id, None)
            self.api.answer_callback(cb_id, "Kept running")
            self.api.edit_message(chat_id, msg.get("message_id", 0), "Cancel aborted. Spec continues running.")

        # --- BOI completion notification callbacks ---
        elif data.startswith("boi_results_"):
            queue_id = data[len("boi_results_"):]
            self.api.answer_callback(cb_id, "Loading results...")
            self._boi_view_results(chat_id, msg.get("message_id", 0), queue_id)

        elif data.startswith("boi_log_"):
            queue_id = data[len("boi_log_"):]
            self.api.answer_callback(cb_id, "Loading log...")
            self._boi_view_log(chat_id, msg.get("message_id", 0), queue_id)

        elif data.startswith("boi_redispatch_"):
            queue_id = data[len("boi_redispatch_"):]
            self.api.answer_callback(cb_id, "Re-dispatching...")
            self._boi_redispatch(chat_id, msg.get("message_id", 0), queue_id)

        elif data.startswith("boi_archive_"):
            queue_id = data[len("boi_archive_"):]
            self.api.answer_callback(cb_id, "Archived")
            self.api.edit_message(
                chat_id, msg.get("message_id", 0),
                msg.get("text", "") + "\n\n_Archived._",
                parse_mode="",
            )

        # --- Learning promotion callbacks ---
        elif data.startswith("promote_approve_"):
            candidate_id = data[len("promote_approve_"):]
            self.api.answer_callback(cb_id, "Approving...")
            self._promote_approve(chat_id, msg.get("message_id", 0), candidate_id)

        elif data.startswith("promote_dismiss_"):
            candidate_id = data[len("promote_dismiss_"):]
            self.api.answer_callback(cb_id, "Dismissed")
            self._promote_dismiss(chat_id, msg.get("message_id", 0), candidate_id)

        # --- Meeting prep callbacks ---
        elif data.startswith("mprep_"):
            event_id = data[len("mprep_"):]
            self.api.answer_callback(cb_id, "Loading prep...")
            self._view_meeting_prep(chat_id, event_id)

        else:
            self.api.answer_callback(cb_id, "Unknown action")

    # --- Learning promotion helpers ---

    def _load_pending_promotions(self) -> dict:
        """Load pending promotions from JSON file."""
        pending_file = HEX_DIR / "evolution" / ".pending-promotions.json"
        if not pending_file.exists():
            return {"candidates": [], "processed_clusters": []}
        try:
            return json.loads(pending_file.read_text())
        except (json.JSONDecodeError, OSError):
            return {"candidates": [], "processed_clusters": []}

    def _save_pending_promotions(self, data: dict) -> None:
        """Save pending promotions atomically."""
        pending_file = HEX_DIR / "evolution" / ".pending-promotions.json"
        pending_file.parent.mkdir(parents=True, exist_ok=True)
        tmp = pending_file.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(data, indent=2))
        tmp.rename(pending_file)

    def _promote_approve(self, chat_id: int, message_id: int, candidate_id: str) -> None:
        """Approve a standing order candidate and append to CLAUDE.md."""
        pending = self._load_pending_promotions()
        candidate = None
        for c in pending.get("candidates", []):
            if c["id"] == candidate_id:
                candidate = c
                break

        if not candidate:
            self.api.send_message(chat_id, "Candidate not found or already processed.", parse_mode="")
            return

        if candidate.get("status") != "pending":
            self.api.send_message(chat_id, f"Candidate already {candidate.get('status', 'processed')}.", parse_mode="")
            return

        rule_text = candidate["rule"]
        today = datetime.now().strftime("%Y-%m-%d")

        claude_md = HEX_DIR / "CLAUDE.md"
        if not claude_md.exists():
            self.api.send_message(chat_id, "CLAUDE.md not found.", parse_mode="")
            return

        content = claude_md.read_text()
        lines = content.split("\n")

        # Find the standing orders table: last row matching | N | in the section
        in_standing_orders = False
        last_order_idx = -1
        last_order_num = 0

        for i, line in enumerate(lines):
            if line.strip() == "## Standing Orders":
                in_standing_orders = True
            elif line.startswith("## ") and in_standing_orders:
                break
            if in_standing_orders:
                match = re.match(r"\|\s*(\d+)\s*\|", line)
                if match:
                    num = int(match.group(1))
                    if num > last_order_num:
                        last_order_num = num
                        last_order_idx = i

        if last_order_idx < 0:
            self.api.send_message(chat_id, "Could not find standing orders table in CLAUDE.md.", parse_mode="")
            return

        new_num = last_order_num + 1
        new_row = f"| {new_num} | **{rule_text}** | {today} |"
        lines.insert(last_order_idx + 1, new_row)

        # Write atomically
        tmp = claude_md.with_suffix(".md.tmp")
        tmp.write_text("\n".join(lines))
        tmp.rename(claude_md)

        # Update candidate status
        candidate["status"] = "approved"
        self._save_pending_promotions(pending)

        self.api.edit_message(
            chat_id, message_id,
            f"Standing order #{new_num} added:\n\n{rule_text}",
            parse_mode="",
        )
        log.info("Promoted standing order #%d: %s", new_num, rule_text[:60])

    def _promote_dismiss(self, chat_id: int, message_id: int, candidate_id: str) -> None:
        """Dismiss a standing order candidate."""
        pending = self._load_pending_promotions()
        for c in pending.get("candidates", []):
            if c["id"] == candidate_id:
                c["status"] = "dismissed"
                break
        self._save_pending_promotions(pending)

        self.api.edit_message(
            chat_id, message_id,
            "Dismissed. Won't suggest again.",
            parse_mode="",
        )
        log.info("Dismissed candidate: %s", candidate_id)

    # --- BOI completion notification helpers ---

    def _boi_read_queue_entry(self, queue_id: str) -> dict:
        """Read the queue JSON entry for a given queue_id."""
        queue_json = Path.home() / ".boi" / "queue" / f"{queue_id}.json"
        if not queue_json.exists():
            return {}
        try:
            return json.loads(queue_json.read_text())
        except (json.JSONDecodeError, OSError):
            return {}

    def _boi_view_results(self, chat_id: int, message_id: int, queue_id: str) -> None:
        """Show spec results summary for a completed BOI spec."""
        entry = self._boi_read_queue_entry(queue_id)
        spec_path = entry.get("spec_path", "")

        if not spec_path or not Path(spec_path).exists():
            self.api.send_message(chat_id, f"Spec file not found for `{queue_id}`.", parse_mode="")
            return

        # Read spec and show DONE/PENDING summary
        try:
            content = Path(spec_path).read_text()
        except OSError:
            self.api.send_message(chat_id, f"Could not read spec for `{queue_id}`.", parse_mode="")
            return

        # Extract task lines (### t-N: ...\nSTATUS)
        lines = content.split("\n")
        tasks = []
        for i, line in enumerate(lines):
            if line.startswith("### t-") and ":" in line:
                status = lines[i + 1].strip() if i + 1 < len(lines) else "?"
                task_name = line.split(":", 1)[1].strip() if ":" in line else line
                if status == "DONE":
                    tasks.append(f"  ✅ {task_name}")
                elif status == "PENDING":
                    tasks.append(f"  ⏳ {task_name}")
                elif status == "SKIPPED":
                    tasks.append(f"  ⏭ {task_name}")
                else:
                    tasks.append(f"  ❓ {task_name} ({status})")

        summary = "\n".join(tasks) if tasks else "(no tasks found)"
        info = (
            f"Results for {queue_id}\n"
            f"Status: {entry.get('status', '?')}\n"
            f"Tasks: {entry.get('tasks_done', 0)}/{entry.get('tasks_total', 0)}\n"
            f"Iterations: {entry.get('iteration', 0)}\n\n"
            f"{summary}"
        )

        # Truncate for Telegram limit
        if len(info) > 3900:
            info = info[:3900] + "\n...(truncated)"

        self.api.send_message(chat_id, info, parse_mode="")

    def _boi_view_log(self, chat_id: int, message_id: int, queue_id: str) -> None:
        """Show recent log output for a BOI spec."""
        raw = run_boi(f"log {queue_id}")
        lines = raw.split("\n")
        if len(lines) > 50:
            lines = lines[-50:]
            raw = "...(truncated)...\n" + "\n".join(lines)
        else:
            raw = "\n".join(lines)
        if len(raw) > 3900:
            raw = raw[-3900:]
        self.api.send_message(chat_id, f"```\n{raw}\n```")

    def _boi_redispatch(self, chat_id: int, message_id: int, queue_id: str) -> None:
        """Re-dispatch a failed BOI spec."""
        entry = self._boi_read_queue_entry(queue_id)
        spec_path = entry.get("original_spec_path", "") or entry.get("spec_path", "")
        if not spec_path:
            self.api.send_message(chat_id, f"No spec path found for `{queue_id}`.", parse_mode="")
            return
        result = run_boi(f"dispatch {spec_path}")
        if len(result) > 3900:
            result = result[:3900] + "\n...(truncated)"
        self.api.send_message(chat_id, f"Re-dispatched:\n```\n{result}\n```")

    # --- Meeting prep helpers ---

    def _view_meeting_prep(self, chat_id: int, event_id: str) -> None:
        """Show meeting prep doc content for a given event ID."""
        prep_done = HEX_DIR / "raw" / "meeting-prep" / ".prepped-today.json"
        if not prep_done.exists():
            self.api.send_message(chat_id, "No meeting preps available today.", parse_mode="")
            return
        try:
            data = json.loads(prep_done.read_text())
        except (json.JSONDecodeError, OSError):
            self.api.send_message(chat_id, "Could not read prep data.", parse_mode="")
            return

        filepath = data.get("preps", {}).get(event_id, "")
        if not filepath or not Path(filepath).exists():
            self.api.send_message(chat_id, f"Prep doc not found for event.", parse_mode="")
            return

        try:
            content = Path(filepath).read_text()
        except OSError:
            self.api.send_message(chat_id, "Could not read prep doc.", parse_mode="")
            return

        if len(content) > 3900:
            content = content[:3900] + "\n...(truncated)"
        self.api.send_message(chat_id, content, parse_mode="")

    def _handle_freetext(self, chat_id: int, text: str) -> None:
        """Handle free-text: save capture + send to Claude."""
        # Save capture
        save_capture(text, source="telegram")

        # Send thinking indicator
        thinking = self.api.send_message(chat_id, "_Thinking..._")
        thinking_msg_id = thinking.get("result", {}).get("message_id")

        # Get Claude response
        response = run_claude(text)

        # Edit the thinking message with the response
        if thinking_msg_id:
            # Truncate if needed (Telegram limit 4096)
            if len(response) > 3900:
                response = response[:3900] + "\n...(truncated)"
            self.api.edit_message(chat_id, thinking_msg_id, response, parse_mode="")
        else:
            self.api.send_message(chat_id, response, parse_mode="")


# ---------------------------------------------------------------------------
# PID file management
# ---------------------------------------------------------------------------
PID_FILE = Path.home() / ".config" / "hex" / "bot.pid"


def write_pid() -> None:
    """Write current PID to file (called from daemon wrapper)."""
    PID_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = PID_FILE.with_suffix(".tmp")
    tmp.write_text(str(os.getpid()) + "\n")
    tmp.rename(PID_FILE)


def cleanup_pid() -> None:
    """Remove PID file on exit."""
    try:
        PID_FILE.unlink(missing_ok=True)
    except OSError:
        pass


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
def run_bot() -> None:
    """Start the bot with long-polling."""
    cfg = load_config()
    token = cfg["bot_token"]
    if not token:
        log.error("No bot token. Set HEX_BOT_TOKEN env var.")
        sys.exit(1)

    allowed = cfg.get("allowed_user_ids", [])
    if not allowed:
        log.warning("No allowed user IDs configured. Set HEX_ALLOWED_USER_IDS.")

    api = TelegramAPI(token)
    bot = HexBot(api, allowed, cfg.get("chat_id", ""))

    # Set module-level vars for send_notification
    global _notification_api, _notification_chat_id
    _notification_api = api
    _notification_chat_id = cfg.get("chat_id", "")

    # Verify token
    me = api.call("getMe")
    if not me.get("ok"):
        log.error("Failed to connect: %s", me.get("description", "unknown error"))
        sys.exit(1)
    bot_name = me.get("result", {}).get("username", "unknown")

    # Write PID file and register cleanup
    write_pid()
    import atexit
    atexit.register(cleanup_pid)
    import signal as _sig
    _sig.signal(_sig.SIGTERM, lambda *_: sys.exit(0))

    log.info("Bot @%s started. Long-polling...", bot_name)

    offset = None
    while True:
        try:
            updates = api.get_updates(offset=offset)
            for upd in updates:
                offset = upd["update_id"] + 1
                try:
                    bot.handle_update(upd)
                except Exception:
                    log.exception("Error handling update %s", upd.get("update_id"))
        except KeyboardInterrupt:
            log.info("Shutting down.")
            break
        except Exception:
            log.exception("Polling error, retrying in 5s...")
            time.sleep(5)


# ---------------------------------------------------------------------------
# Self-test (--test flag)
# ---------------------------------------------------------------------------
def self_test() -> None:
    """Quick dry-run to verify code loads and basic logic works."""
    print("=== hex-bot self-test ===")

    # Config parsing
    cfg = load_config()
    print(f"  Config loaded: token={'set' if cfg.get('bot_token') else 'NOT SET'}, "
          f"allowed_ids={cfg.get('allowed_user_ids', [])}")

    # Capture test
    test_file = save_capture("self-test capture", source="test")
    assert test_file.exists(), "Capture file not created"
    test_file.unlink()  # cleanup
    print(f"  Capture: OK (wrote and cleaned up)")

    # Auth test
    bot = HexBot(TelegramAPI.__new__(TelegramAPI), ["12345"], "")
    assert bot.is_authorized(12345), "Auth should pass"
    assert not bot.is_authorized(99999), "Auth should fail"
    print(f"  Auth: OK")

    # BOI format test
    test_output = "q-001  RUNNING  my-spec\nq-002  DONE  other-spec"
    formatted = format_boi_status(test_output)
    assert "🔄" in formatted, "Should have running emoji"
    assert "✅" in formatted, "Should have done emoji"
    print(f"  BOI format: OK")

    print("=== All tests passed ===")


if __name__ == "__main__":
    if "--test" in sys.argv:
        self_test()
    else:
        run_bot()
