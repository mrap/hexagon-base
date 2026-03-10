---
name: imessage
description: Read, search, send, and watch iMessages via the imsg CLI. Use when the user asks about messages, wants to read conversations, send texts, check what someone said, or monitor incoming messages.
---

# iMessage Integration

Read and send iMessages via the `imsg` CLI tool. All data stays local. No network calls.

## When to Use

- User asks "what did [person] say about [topic]?"
- User asks to send a message or reply to someone
- User wants to check recent messages or a specific conversation
- User says "check my messages", "any new texts?", "message from..."
- User wants to monitor a conversation in real-time
- Preparing for a meeting and need context from message threads
- User asks about trip plans, logistics, or coordination happening over iMessage

## Commands

### List conversations

```bash
imsg chats --limit 20 --json
```

Returns JSON lines with: `id`, `identifier`, `service`, `name`, `last_message_at`.
Use `id` (the chat rowid) for all subsequent commands.

### Read message history

```bash
# Recent messages from a specific chat
imsg history --chat-id <ID> --limit 50 --json

# With attachments metadata
imsg history --chat-id <ID> --limit 50 --attachments --json

# Filter by date range
imsg history --chat-id <ID> --start 2026-03-01T00:00:00Z --end 2026-03-10T23:59:59Z --json

# Filter by participant in a group chat
imsg history --chat-id <ID> --participants "+15551234567" --json
```

Returns JSON lines with: `id`, `guid`, `chat_id`, `text`, `sender`, `is_from_me`, `created_at`, `reactions`, `attachments`, `destination_caller_id`.

### Search for messages

imsg does not have built-in text search. To find messages containing specific text:

```bash
# Get a large batch and filter with jq or grep
imsg history --chat-id <ID> --limit 500 --json | grep -i "search term"
```

Or to search across all recent messages from all chats, get recent chats first, then query each.

### Send a message

```bash
# Send by phone number or email
imsg send --to "+15551234567" --text "Your message here"

# Send to a known chat by ID
imsg send --chat-id <ID> --text "Your message here"

# Send with an attachment
imsg send --to "+15551234567" --text "Check this out" --file /path/to/file.jpg

# Force iMessage or SMS
imsg send --to "+15551234567" --text "Hello" --service imessage
imsg send --to "+15551234567" --text "Hello" --service sms
```

### Watch for new messages (real-time)

```bash
# Watch all new messages (JSON lines stream)
imsg watch --json

# Watch a specific conversation
imsg watch --chat-id <ID> --json

# Include reactions and attachments
imsg watch --chat-id <ID> --reactions --attachments --json
```

Watch streams JSON lines as messages arrive. Use `run_in_background` for the Bash tool.

### React to a message

```bash
# React to the most recent message in a chat
imsg react --chat-id <ID> --reaction love    # ❤️
imsg react --chat-id <ID> --reaction like    # 👍
imsg react --chat-id <ID> --reaction laugh   # 😂
imsg react --chat-id <ID> -r 🎉             # Custom emoji
```

Reactions: `love`, `like`, `dislike`, `laugh`, `emphasis`, `question`, or any single emoji.

## Contact Resolution

imsg uses phone numbers and emails as identifiers, not contact names. To find a person's chat:

1. List chats: `imsg chats --limit 50 --json`
2. Match by `name` (group chat name) or `identifier` (phone/email)
3. Use the `id` field for subsequent commands

To find a specific group chat, search by name in the chats list.

## Important Notes

- **Always use `--json` flag** for machine-readable output
- **Phone numbers must include country code** (e.g., `+1` for US)
- **Timestamps are ISO 8601 UTC** in JSON output
- **`is_from_me: true`** means you sent it, `false` means someone else did
- **Sender field** shows the phone number or email of who sent the message
- **Reactions** appear as nested objects on the message they react to
- **Before sending**, always confirm with the user: who, what message, which service

## Security

- imsg reads `~/Library/Messages/chat.db` (read-only for queries)
- Sends via AppleScript to Messages.app (injection-safe, args passed via argv)
- Zero network calls. All data stays on this machine.
- No telemetry. No external dependencies at runtime.
- Requires: Full Disk Access (Terminal), Automation permission (Messages.app)
