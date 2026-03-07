---
name: hex-shutdown
description: >
  Clean session close. Persists unsaved context, updates learnings,
  saves transcripts, rebuilds memory index, and deregisters the session.
---

# /hex-shutdown — Close Session

## Steps

1. **Final distill pass**: Scan the current conversation for any context that hasn't been written to files yet. Check for:
   - Decisions made but not logged to decisions/
   - Person info mentioned but not in people/
   - Project updates not written to projects/
   - Action items not in todo.md
   Write anything found to the correct location.

2. **Update learnings**: Review the session for observations about the user's work style, communication patterns, or preferences. Append new observations to `$AGENT_DIR/me/learnings.md` with today's date.

3. **Save transcript**:

```bash
python3 $AGENT_DIR/tools/scripts/parse_transcripts.py
```

4. **Rebuild memory index**:

```bash
python3 $AGENT_DIR/tools/skills/memory/scripts/memory_index.py
```

5. **Deregister session**:

```bash
bash $AGENT_DIR/tools/scripts/session.sh stop
```

6. **Report**: "Session closed. [Summary of what was persisted]."
