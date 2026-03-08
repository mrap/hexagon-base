# Hexagon Base

**Your personal AI agent that gets smarter over time.**

Hexagon Base is an open-source framework for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that turns it into a persistent, self-improving AI agent. It remembers your context across sessions, learns how you work, and actively suggests improvements to your workflow.

## What Makes This Different

Most AI tools start from scratch every conversation. Hexagon is different:

- **It remembers.** Every session builds on the last. Context, decisions, and preferences persist in local files.
- **It learns.** The agent observes how you work, what you care about, and how you communicate. It gets better at serving you over time.
- **It improves itself.** When the agent notices a repeated pattern (same question, same manual step), it proposes an automation. You approve it, and the system evolves.

Three principles: **Compound. Anticipate. Evolve.**

## Quick Start

### 1. Bootstrap your agent

```bash
git clone https://github.com/mrap/hexagon-base.git
cd hexagon-base
claude
```

Then just say:

```
install hexagon
```

Claude reads the project instructions and walks you through setup — asks for an agent name and where to install (defaults to `~/hexagon`). It creates a fully self-contained workspace and installs the `hex` shell command automatically.

> **Alternative:** Run the bootstrap directly: `bash scripts/bootstrap.sh`

### 2. Launch your workspace

Open a new terminal, then:

```bash
hex
```

This opens a tmux workspace with Claude Code on the left, a live landings dashboard on the top-right, and a quick capture pane on the bottom-right. Type a thought into the capture pane and hit enter to save it instantly. Your agent starts up and asks 3 quick questions, then you're off.

```
┌──────────────────────────┬────────────────────┐
│                          │                    │
│     Claude Code          │  Landings Dash     │
│     (main pane)          │  (auto-refresh)    │
│                          │                    │
│                          ├────────────────────┤
│                          │ 💡 Quick Capture   │
│                          │ > _                │
└──────────────────────────┴────────────────────┘
```

> **No tmux?** Just `cd ~/<agent-name> && claude` works too.

## What It Creates

The installer creates this workspace:

```
~/<agent-name>/
├── CLAUDE.md              ← The agent's brain. All protocols and behaviors.
├── todo.md                ← Your priorities and action items.
├── teams.json             ← Connected teams (for collaboration).
│
├── me/                    ← About you.
│   ├── me.md              ← Who you are, what you do, your goals.
│   ├── learnings.md       ← What the agent observes about you over time.
│   └── decisions/         ← Private decision records.
│
├── projects/              ← One folder per project.
│   └── {project}/
│       ├── context.md     ← Project summary and key facts.
│       ├── decisions/     ← Decisions with reasoning.
│       ├── meetings/      ← Meeting notes and prep.
│       └── drafts/        ← Draft communications.
│
├── people/                ← One folder per person you work with.
│   └── {name}/
│       └── profile.md     ← What you know about them.
│
├── evolution/             ← The improvement engine.
│   ├── observations.md    ← Patterns the agent has noticed.
│   ├── suggestions.md     ← Proposed improvements (pending your approval).
│   ├── changelog.md       ← Improvements that have been implemented.
│   └── metrics.md         ← Impact tracking.
│
├── raw/                   ← Unprocessed input (transcripts, messages, docs, captures).
├── landings/              ← Daily outcome targets.
└── .claude/               ← Scripts, skills, commands, hooks.
```

## Web UI

Don't want to use the terminal? Run the web UI instead:

```bash
hex-ui
```

This starts a browser-based interface at `http://localhost:3141` with:

- **Dashboard** — Today's landings, recent captures, open todos (auto-refreshes)
- **Quick Capture** — Dump thoughts from any device with a browser
- **Memory Search** — Search your agent's entire knowledge base
- **Projects & People** — View and edit project context and people profiles
- **Agent Chat** — Talk to Claude through the browser

The UI reads and writes the same workspace files as the CLI. Changes sync instantly between browser and terminal.

Works on phone, tablet, desktop. Dark mode by default.

> Requires Python 3.8+ and three pip packages: `fastapi`, `uvicorn`, `jinja2`. Installed automatically on first launch.

### Remote Access (VM / Devserver)

If your workspace runs on a remote machine (devserver, VM, OD), the UI auto-detects this and prints a copy-pasteable SSH tunnel command:

```bash
hex-ui   # on the remote machine — prints tunnel instructions automatically
```

Then on your **local machine**, tunnel the port:

```bash
ssh -L 3141:localhost:3141 you@your-server
```

Open http://localhost:3141 in your local browser.

**Helper script** (run on your local machine):

```bash
./dot-claude/scripts/hex-ui-local.sh you@your-server
```

This opens the SSH tunnel and launches your browser in one step. Press Ctrl+C to disconnect.

> **Flags:** `hex-ui --host 0.0.0.0` binds to all interfaces (use with caution). `hex-ui --tunnel` prints the SSH tunnel command without starting the server.

## Architecture

Hexagon Base bootstraps a self-contained workspace. Claude Code natively reads `.claude/commands/` for slash commands and `.claude/settings.json` for hooks — no plugin manifest needed.

The workspace includes:

- **Commands** — Slash commands you can type (like `/hex-startup`)
- **Skills** — Capabilities the agent can use (like the memory search system)
- **Hooks** — Scripts that run automatically on events (like backing up transcripts)

Everything runs locally. No external services required. No API keys to configure. Your data stays on your machine.

### Memory System

The agent has persistent, searchable memory powered by SQLite full-text search:

- All `.md` and `.txt` files are indexed into a local database
- Files are split by heading so each chunk is individually searchable
- The index updates incrementally (only changed files are re-indexed)
- The agent searches memory before answering questions about past context

### Improvement Engine

The agent actively watches for workflow inefficiencies:

1. **Observe** — Notices repeated patterns, corrections, and friction points
2. **Record** — Logs patterns with frequency counts in `evolution/observations.md`
3. **Suggest** — When a pattern appears 3+ times, proposes an improvement
4. **Implement** — After your approval, builds the improvement (new rule, template, or skill)
5. **Track** — Records impact in `evolution/changelog.md` and `evolution/metrics.md`

The system literally gets smarter the more you use it.

## Commands

| Command | What It Does |
|---------|-------------|
| `/hex-startup` | Start a session. Loads context, checks memory, surfaces action items. On first run, walks through onboarding. |
| `/hex-save` | Save current session. Parses transcripts, rebuilds memory index. |
| `/hex-shutdown` | Close session cleanly. Persists unsaved context, updates learnings, deregisters session. |
| `/hex-upgrade` | Pull latest from hexagon-base. Upgrades scripts, skills, commands, hooks. Preserves your data. |
| `/hex-ui` | Launch the web UI. Browser-based dashboard, capture, memory search, projects, people, and chat. |
| `/context-save` | Persist any unsaved context from the current conversation to files. |
| `/hex-sync` | Sync with connected teams. Pull shared updates, push local updates. |
| `/hex-create-team` | Create a new team for collaboration. |
| `/hex-connect-team` | Join an existing team. |

## Upgrading

### New installs

New installs get `/hex-upgrade` automatically. Just run it:

```
/hex-upgrade
```

### Existing installs

If your hexagon was installed before `/hex-upgrade` existed, run this one-time bootstrap from inside your agent directory:

```bash
git clone --depth 1 https://github.com/mrap/hexagon-base.git /tmp/hexagon-upgrade && \
  cp /tmp/hexagon-upgrade/dot-claude/scripts/upgrade.sh .claude/scripts/upgrade.sh && \
  cp /tmp/hexagon-upgrade/dot-claude/commands/hex-upgrade.md .claude/commands/hex-upgrade.md && \
  chmod +x .claude/scripts/upgrade.sh && \
  rm -rf /tmp/hexagon-upgrade && \
  echo "Done. Run /hex-upgrade to pull the latest."
```

After that, `/hex-upgrade` handles everything going forward.

## Philosophy

Hexagon is built on the belief that AI agents should **compound over time**, not start fresh every conversation.

- **Compound.** Every session builds on the last. Context accumulates. Patterns emerge. The agent gets better.
- **Anticipate.** Don't wait to be asked. Surface risks, spot opportunities, recommend actions. Produce artifacts, not just suggestions.
- **Evolve.** Actively improve the system itself. When a pattern is repeated, build an automation. When a protocol is missing, propose one.

This isn't a chatbot. It's a persistent partner that learns your work, your style, and your goals, then actively helps you get better at what you do.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- Python 3.8+ (for memory system, uses only standard library)
- macOS or Linux

## Contributing

Hexagon Base is open source. Contributions welcome.

## License

MIT
