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

Claude reads the project instructions and walks you through setup — asks for an agent name and where to install (defaults to `~/hexagon`). It creates a fully self-contained workspace.

> **Alternative:** Run the bootstrap directly: `bash scripts/bootstrap.sh`

### 2. Start your first session

```bash
cd ~/hexagon/<agent-name>
claude
```

Run `/hex-startup` to begin. The agent will ask you 3 quick questions, then you're off.

## What It Creates

The installer creates this workspace:

```
~/hexagon/<agent-name>/
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
├── raw/                   ← Unprocessed input (transcripts, messages, docs).
├── landings/              ← Daily outcome targets.
└── tools/                 ← Scripts, skills, commands, hooks.
```

## Architecture

Hexagon Base is a Claude Code **plugin**. Plugins are directories with a `.claude-plugin/plugin.json` manifest that tells Claude Code what capabilities are available.

When Claude Code opens a directory with a plugin, it automatically loads:

- **Skills** — Capabilities the agent can use (like the memory search system)
- **Commands** — Slash commands you can type (like `/hex-startup`)
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
| `/context-save` | Persist any unsaved context from the current conversation to files. |
| `/hex-sync` | Sync with connected teams. Pull shared updates, push local updates. |
| `/hex-create-team` | Create a new team for collaboration. |
| `/hex-connect-team` | Join an existing team. |

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
