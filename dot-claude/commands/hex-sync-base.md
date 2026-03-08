# /hex-sync-base -- Sync local fixes to hexagon-base

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
   - **Local only**: Mike-specific customization (personal data, preferences)
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
   For CLAUDE.md changes that are generic (new standing orders, protocol updates), apply them to the hexagon-base CLAUDE.md. Skip Mike-specific content (project references, personal evolution items).

## Path Mapping

| hex location | hexagon-base location |
|-------------|----------------------|
| `.claude/scripts/` | `dot-claude/scripts/` |
| `.claude/skills/` | `dot-claude/skills/` |
| `.claude/commands/` | `dot-claude/commands/` |
| `.claude/hooks/` | `dot-claude/hooks/` |
| `CLAUDE.md` | `CLAUDE.md` |

## Rules

- Never push personal data (me/, people/, projects/, landings/, evolution/, todo.md)
- Never push settings.json (contains personal hooks and statusline config)
- Always diff before copying. Show the diff to the user.
- Commit to hexagon-base with a clear message about what changed and why.
- After pushing, verify the commit landed with `git log -1` in hexagon-base.
