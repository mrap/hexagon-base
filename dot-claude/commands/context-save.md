---
name: context-save
description: >
  Persist unsaved context from the current conversation to files.
  Scans for decisions, people info, project updates, and action items
  that haven't been written yet.
---

# /context-save — Persist Unsaved Context

## Steps

1. **Scan the conversation** for any notable context that hasn't been written to files:
   - Person info (names, roles, org relationships) -> `$AGENT_DIR/people/{name}/profile.md`
   - Decisions (technical, strategic, process) -> `$AGENT_DIR/projects/{project}/decisions/` or `$AGENT_DIR/me/decisions/`
   - Project status updates -> `$AGENT_DIR/projects/{project}/context.md`
   - New action items or deadlines -> `$AGENT_DIR/todo.md`
   - Observations about the user -> `$AGENT_DIR/me/learnings.md`

2. **Write to the correct locations** immediately. Use Edit (not Write) for existing files to avoid overwriting other sessions' changes.

3. **Report** what was saved. Format:

```
Context saved:
- Updated people/alice/profile.md (new role info)
- Added 2 items to todo.md
- Created projects/api-redesign/decisions/caching-strategy-2024-03-15.md
```

If nothing needs saving: "All context already persisted. Nothing new to save."
