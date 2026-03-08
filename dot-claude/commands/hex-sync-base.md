# /hex-sync-base -- Sync local fixes to hexagon-base
# sync-safe

Compare local hex against hexagon-base and push improvements upstream.

## Steps

1. **Detect AGENT_DIR and BASE_DIR**
   - AGENT_DIR: walk up from script to find CLAUDE.md
   - BASE_DIR: `~/github.com/mrap/hexagon-base`

2. **Diff shared files**
   Compare these directories between hex and hexagon-base:
   - `dot-claude/scripts/` vs `.claude/scripts/`
   - `dot-claude/skills/` vs `.claude/skills/`
   - `dot-claude/commands/` vs `.claude/commands/`
   - `CLAUDE.md` (root)

   For each file that exists in both locations, diff them.
   For files only in hex, flag as "new, consider adding."
   For files only in hexagon-base, flag as "missing locally, may need pull."

3. **Classify each diff**
   For each changed file, determine:
   - **Push upstream**: Generic improvement that benefits all hexagon users
   - **Local only**: user-specific customization (personal data, preferences)
   - **Needs work**: Change is valuable but needs generalization before pushing (e.g., hardcoded timezone)

   Present a table to the user with the classification and a one-line summary of each change.

4. **Apply approved changes**
   For each file the user approves:
   - Copy the file to the corresponding location in hexagon-base
   - Note: hex uses `.claude/` but hexagon-base uses `dot-claude/` (renamed during install)

5. **Commit and push hexagon-base**
   - Stage changed files in hexagon-base
   - Create a commit with a descriptive message
   - Push to origin

6. **Update CLAUDE.md if needed**
   For CLAUDE.md changes that are generic (new standing orders, protocol updates), apply them to the hexagon-base CLAUDE.md. Skip user-specific content (project references, personal evolution items).

## Path Mapping

| hex location | hexagon-base location |
|-------------|----------------------|
| `.claude/scripts/` | `dot-claude/scripts/` |
| `.claude/skills/` | `dot-claude/skills/` |
| `.claude/commands/` | `dot-claude/commands/` |
| `.claude/hooks/` | `dot-claude/hooks/` |
| `CLAUDE.md` | `CLAUDE.md` |

## Guards

Three layers prevent personal data from leaking:

1. **Path allowlist** (`sync-guard.sh check-path`): Only approved paths can be synced. Deny by default.
2. **Content scanner** (`sync-guard.sh scan-file`): Before copying, scan each file for personal data (names, emails, personal file references). Block if anything matches.
3. **Pre-commit hook**: hexagon-base has a pre-commit hook that runs `sync-guard.sh scan-all` as the last line of defense.

**Before copying any file**, run:
```bash
bash $AGENT_DIR/.claude/scripts/sync-guard.sh check-path "dot-claude/scripts/foo.sh"
bash $AGENT_DIR/.claude/scripts/sync-guard.sh scan-file /path/to/file
```

If either check fails, DO NOT copy the file. Surface the issue to the user.

## Rules

- Run sync-guard.sh on every file before copying. No exceptions.
- Never push personal data (me/, people/, projects/, landings/, evolution/, todo.md)
- Never push settings.json (contains personal hooks and statusline config)
- Always diff before copying. Show the diff to the user.
- Commit to hexagon-base with a clear message about what changed and why.
- After pushing, verify the commit landed with `git log -1` in hexagon-base.
