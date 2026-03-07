---
name: hex-checkpoint
description: Checkpoint context and compact for a fresh start. Persists everything, then clears the window.
---

# /hex-checkpoint — Checkpoint and Continue

Persist all context from the current conversation, then compact for a fresh start in the same thread.

## Arguments

The user may pass a focus directive (what they want to work on next). Use it as the compact summary.

## Step 1: Scan for unpersisted context

Review the conversation for anything not yet written to files:

- Decisions made (write to `me/decisions/` or `projects/*/decisions/`)
- People mentioned (write to `people/*/profile.md`)
- Project updates (write to `projects/*/context.md`)
- New tasks or priority changes (update `todo.md`)
- Observations about the user (update `me/learnings.md`)
- Patterns noticed (update `evolution/observations.md`)

## Step 2: Write handoff file

Write a structured handoff to `raw/handoffs/YYYY-MM-DD-HHMMSS.md`:

```markdown
# Session Handoff — YYYY-MM-DD HH:MM

## What We Did
- (bullet list of accomplishments)

## Key Decisions
- (any decisions made with reasoning)

## Open Threads
- (anything in progress or unresolved)

## Next Focus
- (what the user wants to work on next)

## Files Modified This Session
- (list of files created or changed)
```

## Step 3: Update todo.md

Make sure todo.md reflects current state. Move completed items, add new ones discovered during the session.

## Step 4: Rebuild memory index

```bash
python3 $AGENT_DIR/.claude/skills/memory/scripts/memory_index.py
```

## Step 5: Compact

Tell the user: "Checkpointed. Compacting now."

Then trigger compact with a focused summary. The summary should include:
- The next focus area (from arguments or from the handoff)
- A pointer to the handoff file
- Key files to re-read after compact

Format the compact prompt as:
```
/compact [Next focus]. Handoff at raw/handoffs/[filename]. Re-read: todo.md, me/learnings.md, evolution/observations.md
```

## Step 6: After compact

After compact completes, immediately:
1. Read the handoff file
2. Read todo.md
3. Read me/learnings.md
4. Say: "Context restored. Ready to work on [next focus]."
