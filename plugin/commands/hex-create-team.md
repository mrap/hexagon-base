---
name: hex-create-team
description: >
  Create a new team for shared project collaboration.
---

# /hex-create-team — Create a Team

## Steps

1. **Ask for team details**:
   - "What's the team name?" (e.g., "design-team", "project-alpha")
   - "Where should the shared folder live?" (Suggest a path like `~/teams/<team-name>` or a shared drive location)

2. **Create the team folder structure**:

```
<team-path>/
├── team.json           ← Team config (name, members, created date)
└── projects/           ← Shared project files
```

3. **Create team.json**:

```json
{
  "name": "<team-name>",
  "created": "<today>",
  "created_by": "<user>",
  "members": ["<user>"]
}
```

4. **Auto-connect**: Add this team to the creator's `$AGENT_DIR/teams.json`.

5. **Report**: "Team [name] created at [path]. Share this path with teammates so they can run /hex-connect-team to join."
