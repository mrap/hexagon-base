---
name: hex-sync
description: >
  Sync with connected teams. Pull shared updates and push local updates
  for all configured teams.
---

# /hex-sync — Team Sync

## Steps

1. **Read teams.json**: Load `$AGENT_DIR/teams.json` to get connected teams.

If no teams are configured, say: "No teams connected. Run /hex-connect-team to join one."

2. **For each connected team**, sync shared project files:
   - **Pull**: Read shared files from the team path. Compare with local project files. If the shared version is newer, update the local copy.
   - **Push**: If local project files are newer than shared versions, update the shared copy.

3. **Report** what changed:

```
Team sync complete:
- project-alpha: pulled 2 updates, pushed 1 update
- project-beta: no changes
```

## Privacy Rules

Never sync files from:
- `$AGENT_DIR/me/decisions/`
- `$AGENT_DIR/me/learnings.md`
- `$AGENT_DIR/people/` (unless explicitly shared)

Only sync project-level files: context.md, decisions/, meetings/.
