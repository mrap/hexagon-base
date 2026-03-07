---
name: hex-startup
description: >
  Full session initialization. First-time users get onboarding.
  Returning users get context loading, action items, and daily landings.
---

# /hex-startup — Start Your Session

## Step 1: Run Startup Script

```bash
bash $AGENT_DIR/tools/scripts/startup.sh
```

This handles: environment detection, session registration, transcript parsing, memory index rebuild, health check, integration check, and pending improvement suggestions.

## Step 2: Check for First-Time Setup

Read `$AGENT_DIR/me/me.md`. If it still contains the placeholder text "Your name here", this is a first-time user. Run **Onboarding** (Step 2a). Otherwise, skip to **Returning User** (Step 2b).

### Step 2a: First-Time Onboarding (Phase 1)

Ask exactly these three questions. Nothing more.

1. "What's your name?"
2. "What do you do?" (role, one line)
3. "What are your top 3 priorities right now?"

Write answers to `$AGENT_DIR/me/me.md` immediately. Replace the placeholder text.

Then say: "You're set up. I'll learn more about how you work over the next few sessions. For now, let's get to work. What's on your mind?"

### Step 2b: Returning User

1. Read `$AGENT_DIR/todo.md` for current priorities
2. Read `$AGENT_DIR/me/learnings.md` for recent observations
3. Check `$AGENT_DIR/landings/` for today's landing targets (if any)
4. Check `$AGENT_DIR/evolution/suggestions.md` for pending improvement proposals
5. If today is a workday and no landings exist for today, propose 3-5 landing targets based on todo.md

Surface a brief summary: "Ready. Here's what needs attention today:" followed by top priorities, meetings to prep, overdue items, and any pending improvement suggestions.

## Step 3: Team Sync (if configured)

Check `$AGENT_DIR/teams.json`. If teams are configured, mention any unsynced updates. Don't auto-sync. Just surface: "Team updates available. Run /hex-sync when ready."
