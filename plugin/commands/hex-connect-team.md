---
name: hex-connect-team
description: >
  Connect to an existing team for shared project context.
---

# /hex-connect-team — Join a Team

## Steps

1. **Ask for the team path**: "What's the path to the team folder?" (This is a shared directory that other team members' agents can access.)

2. **Verify the path exists** and contains a `team.json` or similar team config file.

3. **Ask which projects to sync**: List the projects available in the team folder. Ask: "Which projects do you want to sync?" Allow selecting one, some, or all.

4. **Update teams.json**: Add the team to `$AGENT_DIR/teams.json` with:
   - Team name
   - Team path
   - Synced project names
   - Connected date

5. **Initial sync**: Pull shared project files for selected projects.

6. **Report**: "Connected to [team name]. Syncing [N] projects. Run /hex-sync anytime to update."
