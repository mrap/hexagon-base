# Quick Capture Research — Hexagon Base

*Research for t-1 of q-014 (BOI spec)*
*Date: 2026-03-07*

---

## Source Files Reviewed

| # | File | Key Findings |
|---|------|-------------|
| 1 | `~/hive/tools/commands/context-save.md` | Hive's `/context-save` scans the conversation for unsaved context and routes to canonical files. Runs inside a Claude session (needs LLM). |
| 2 | `~/hive/CLAUDE.md` | "Context Persistence" section: agent persists after every message, not just on save. Decision logging rule requires Date/Context/Decision/Reasoning/Impact. Distillation protocol runs after gchat pulls, every 5 turns, and on session end. |
| 3 | `~/hive/me/learnings.md` | "Catches when tools are over-engineered. Quick capture should be a pure shell script, not a Claude session. Principle: use the leanest tool for the job." This is from mrap's own feedback. |
| 4 | `~/hive/raw/transcripts/` | Session transcripts exist as .jsonl and daily .md files. These are auto-backed via hooks. |
| 5 | `~/gdrive/hexagon-base/dot-claude/commands/` | 10 commands exist: context-save, hex-checkpoint, hex-connect-team, hex-context-sync, hex-create-team, hex-save, hex-shutdown, hex-startup, hex-sync, hex-upgrade. No capture command yet. |
| 6 | `~/gdrive/hexagon-base/templates/CLAUDE.md.template` | Has "Persist After Every Message" standing order. Context-save already exists as a command. No capture-specific flow. File index shows `raw/` directory with transcripts, messages, calendar, docs subdirs. No `raw/captures/` yet. |
| 7 | `~/hive/projects/hexagon/user-story-evals.md` | S1 (Quick capture, reminder): User types a reminder, system creates task + links person + fires reminder. S2 (Quick capture, context dump): User describes meeting outcome, system routes to person profile + project context. Both require instant acknowledgment. |

---

## What Worked in Hive's Capture Patterns

### Strengths
1. **Context-save is comprehensive.** Scans conversation for decisions, people info, project updates, action items, observations. Routes each to the right canonical file. This pattern should carry over to triage.
2. **Persist-after-every-message standing order.** The agent doesn't wait for a save command. It persists inline. This is good for in-session context but doesn't help when the user is outside a Claude session.
3. **Decision logging with structure.** Date/Context/Decision/Reasoning/Impact. Forces quality over speed when the destination is a decision record.
4. **File-per-concern routing.** People go to `people/`, projects go to `projects/`, decisions to `decisions/`. Clear routing table.

### Weaknesses / Gaps
1. **No out-of-session capture.** Hive's context persistence only works inside a Claude session. If the user thinks of something while commuting or in a meeting, there's no way to dump it without opening Claude.
2. **Context-save is reactive.** The user has to run `/context-save` or the agent runs it on shutdown. Things fall through the cracks between sessions.
3. **No raw capture format.** Everything goes directly to canonical files. There's no "inbox" or staging area for unprocessed thoughts.

---

## What the User Experience Should Look Like

### For a first-time agent user (never used AI agents before)

The capture UX must be zero-learning-curve:

1. **One command.** `hex-capture "thought"` or just `hex-capture` and type.
2. **No configuration.** The command just works after bootstrap.
3. **No decisions.** The user doesn't have to categorize, tag, or route. They dump text and walk away.
4. **Instant confirmation.** "Captured. Will triage on next session startup." Done. Sub-second.
5. **No Claude session needed.** Pure shell. Works from phone SSH, terminal, anywhere.
6. **Compound on startup.** Next time they open a session, the agent has already processed the capture. The user sees: "Triaged 3 captures since last session." Magic.

### Mental model for the user
"I dump things into hex-capture. My agent sorts them out next time we talk."

This is the inbox model: capture is fast and dumb, triage is slow and smart.

---

## Simplest Possible Implementation

### Capture (shell script, no LLM)
- Accept text from args, stdin, or $EDITOR
- Save to `raw/captures/YYYY-MM-DD_HH-MM-SS.md` with YAML frontmatter (timestamp, source)
- Print confirmation
- Exit

### Triage (slash command, needs LLM)
- Read all untriaged files in `raw/captures/`
- For each: determine type, destination, action needed
- Route to canonical files (todo.md, people/, projects/, me/learnings.md)
- Mark as triaged in frontmatter
- Print summary

### Integration
- Startup flow checks for untriaged captures and runs triage automatically
- Bootstrap creates `raw/captures/` and shows alias instructions
- Upgrade script adds capture to existing workspaces

---

## Design Decisions

| Decision | Choice | Reasoning |
|----------|--------|-----------|
| Capture format | YAML frontmatter + raw text | Simplest format that supports metadata without parsing overhead |
| Triage timing | On startup, not on capture | Capture must be LLM-free for zero-friction. Triage needs LLM for routing. |
| Filename pattern | `YYYY-MM-DD_HH-MM-SS.md` | Sortable, unique, human-readable |
| Triaged marker | `triaged: true` in frontmatter | Simple boolean. Don't delete captures (audit trail). |
| Conservative routing | Ask user when unsure | Better to ask than to route incorrectly. Trust builds with accuracy. |
| Workspace detection | Walk up from script location | Script lives in `.claude/scripts/`, can find workspace root by going up 3 levels. More portable than hardcoded paths. |

---

## Risks

1. **Frontmatter parsing in shell.** The triage command needs to check `triaged: true`. A simple grep handles this.
2. **Large capture backlog.** If user captures 50 things between sessions, triage could be slow. Mitigate: process in batch, summarize results.
3. **Ambiguous routing.** "Jake approved the budget" touches person (Jake), project (budget), and decision. The triage LLM needs clear routing rules and should err toward asking.

---

## References

- Hive context-save: `~/hive/tools/commands/context-save.md`
- Hive CLAUDE.md (Context Persistence section): `~/hive/CLAUDE.md` lines 263-289
- Hive learnings (quick capture observation): `~/hive/me/learnings.md` line ~12
- Hexagon user story evals (S1, S2): `~/hive/projects/hexagon/user-story-evals.md` lines 11-29
- Hexagon CLAUDE.md template (file index, routing table): `~/gdrive/hexagon-base/templates/CLAUDE.md.template` lines 254-268
