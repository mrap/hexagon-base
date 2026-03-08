# Porting Evidence: Hive Features for Hexagon Base

Evidence gathered from session transcripts (2026-03-04, 2026-03-05) analyzing actual feature usage, impact, and compound effects.

## Evidence Table

| Feature | Sessions Used | Evidence of Impact | Friction Points | Compound Effect |
|---------|--------------|-------------------|-----------------|-----------------|
| **GChat Integration & Space Cache** | 2026-03-04 (msg #15-16), 2026-03-05 (msg #9-13) | Agent sent team message as user, pulled recent messages across spaces, surfaced unreplied pings. User said "we should be caching the spaces and DMs we use often" (Mar 5). Built `gchat-spaces.json` cache with 8 spaces + 1 DM. | GChat MCP tool failed twice before correct usage found. User frustrated: "We should be able to reliably send messages and shouldn't have to go through this dance every time" (Mar 5 msg #13). | **High.** Space cache persists across sessions. Every future message send is instant lookup instead of query. Cross-referencing gchat with todo.md surfaces action items automatically. |
| **Quick Capture** | 2026-03-05 (msg #3, #36-41) | 16 captures triaged in one batch. Captures included feature ideas, personal errands, relationship notes, and hackathon ideas. User explicitly built Quick Capture as a hackathon submission. `cap` alias launched Claude in capture mode with no startup overhead. | Model too heavy for simple captures. Fixed: switched to Haiku + `--effort low`. Notifications fired during capture mode (distracting). Fixed: hooks skip when `HIVE_CAPTURE_MODE=1`. | **High.** Every capture is a context drop that gets triaged into canonical files (todo.md, people/, projects/). Without capture, these thoughts are lost between sessions. The triage step routes raw input into structured knowledge. |
| **Meeting-Watcher & Notes Recovery** | 2026-03-04 (msg #9-13) | Sam's meeting notes were silently lost (3 failed attempts, doc blacklisted in `failed_meetings.log`). Agent couldn't find them when asked. Root cause diagnosed: daemon unsets Claude env vars, breaking nested `claude --print` calls. Three fixes implemented: startup surfaces failures, retry commands added, fallback search across multiple sources. | Silent failures. User had to manually provide the Google Doc URL. Agent searched memory, transcripts, gchat but never checked `failed_meetings.log` or calendar dump. "That's the gap." | **High.** Standing Order #13 created: "always check multiple sources when searching for meeting notes." Every future session inherits this multi-source search behavior. Failed meeting detection at startup prevents data loss. |
| **Checkpoint Command** | 2026-03-04 (msg #17-18) | `/hive-checkpoint` saved mid-session state: synced landings, persisted 3 context files, backed up transcript. Used when switching topics ("before context compression kicks in"). | None observed. Clean execution. | **High.** Prevents context loss during long sessions. Every checkpoint preserves decisions, people updates, project state that would otherwise be lost when context window compresses. Already ported to hexagon-base as `/hex-checkpoint`. |
| **Background Agent Delegation** | 2026-03-05 (msg #13, #15, #34, #39, #42-43, #52) | 8+ background agents spawned across the session: meeting-watcher fix, proactive workflows research, MetaClaw deep dive, web UI eval, mobile UI eval, session-learning design, backlog automation, mesh claim/release spec. User consistently said "in the background" and "using the best model". | Agents ran out of turns before writing output (msg #45-46). Two had to be "resumed." Pattern: research agents gather data but don't persist. User never explicitly instructed to handle this. | **Very High.** Each background agent produced a research brief or implementation that compounded. The MetaClaw research informed the proactive workflows decision. The mobile UI research informed team strategy. Parallel execution let user stay focused on high-judgment work while agents handled research. |
| **Standing Orders (Rule Creation from Corrections)** | 2026-03-04 (msg #11-13), 2026-03-05 (msg #21-22, #49-50) | User corrected agent behavior, agent created permanent rules. Examples: "always check multiple sources for meeting notes" (Standing Order #13), "green-diff is default for all non-trivial tasks" (Standing Order #15), "mesh should auto-detect free workers, not require env vars" (msg #21), "if all workers busy, queue don't error" (msg #22). | None. This is the core compound mechanism. | **Very High.** Single correction becomes permanent behavior change. User never has to re-correct. This is the purest form of compound improvement: one-time friction investment yields permanent returns. |
| **People Profile Cross-Referencing** | 2026-03-04 (msg #7-9), 2026-03-05 (msg #4) | Agent pulled Selinah's meeting notes from `people/` to inform cultural strategy. Cross-referenced gchat messages with known team members. Ryan's second brain interest noted in profile for follow-up. Sam's bottleneck insights cross-referenced against Valerii's and Eric's. | Missing Sam meeting notes (see Meeting-Watcher above). | **High.** People profiles accumulate across sessions. Meeting prep automatically pulls relevant context. Relationship-building opportunities surface automatically ("Ryan is trying second brain, follow up"). |
| **Proactive Context Surfacing (GChat → Todo Cross-Reference)** | 2026-03-04 (msg #4), 2026-03-05 (msg #3-4) | Startup automatically cross-references gchat output against `todo.md`. Flags: items needing attention, unreplied pings, visibility opportunities, org signals. Surfaced Igor leaving Response Gen as "structural change worth monitoring" (Mar 4). | None observed. Clean workflow. | **High.** Every session starts with awareness of what changed. User doesn't have to ask "what did I miss?" The cross-reference catches things that would fall through cracks between sessions. |
| **Capture Triage Pipeline** | 2026-03-05 (msg #40-41) | 16 raw captures categorized and routed: 2 time-sensitive items flagged, 2 duplicates detected and merged, 13 routed to todo.md backlog, people profiles updated, landings updated with hackathon idea. All 16 marked resolved after processing. | Required manual invocation ("let's triage some quick captures"). Not automated. | **High.** Raw thought dumps become structured, actionable items in canonical locations. Deduplication prevents noise accumulation. Time-sensitive detection prevents missed deadlines. |
| **Context Audit & Optimization** | 2026-03-05 (msg #3-4, reference to Mar 4 work) | `context-audit.sh` script reduced plugins from 22 to 14, saving ~17-22k tokens per session. Listed as potential hackathon submission with "measurable impact." | Not detailed in transcripts. Appears to have been a prior session's work. | **Medium.** Token savings compound: every session gets more useful context window. But this is infrastructure-level, not directly visible to users. |
| **Ralph Loop / Chief Wiggum Integration** | 2026-03-05 (msg #17-24, #50-51) | Used to spec out mesh-fbsource diff preparation (5 tasks), mesh claim/release commands (6 tasks), and Local Mesh polish (4 tasks). Chief Wiggum generated spec.md, prompt.md, run.sh, context.md. Green-diff protocol appended to all prompts. | Task ID format mismatch caused parser failure (tc-01 vs t-001 regex). Fixed immediately. Ralph loop auto-claimed workers had two bugs (field name mismatch, PID detection). User caught both: "This error means Mesh doesn't queue" and "That feels wrong." | **Very High.** Each Ralph loop runs autonomously, freeing the user for high-judgment work. The green-diff loop pattern (commit → CI → fix → repeat until green) is reusable across all future code tasks. Chief Wiggum turns a project goal into an executable pipeline in one conversation. |
| **Session Learning & Auto-Learn** | 2026-03-05 (msg #31-34) | User wanted to extract session learnings but couldn't find the skill (disappeared from claude-templates). Stop hook (`auto-learn.sh`) persisted 6 learnings and 2 universal patterns on session exit. User commissioned a Hive-native replacement with 10 learning categories and approval UX. | Original skill disappeared from claude-templates. The auto-learn hook exists but is invisible (fires on exit, no user control). Session-learning needs to work even without transcripts. | **High.** Learnings compound across sessions. The stop hook ensures learnings are never lost. But the user wants more control: approval before writing, categorized learnings, deduplication against existing knowledge. |
| **Backlog Automation Agent** | 2026-03-05 (msg #44, #52, #56) | Agent analyzed todo.md backlog, identified 12 automatable items ranked by priority, then implemented 4 quick wins in background: cap alias optimization, capture mode notification suppression, git snapshots for ~/hive, Quick Capture status update. | Some items were too complex for background automation ("Build unified spec-to-green skill" needed user judgment). Agent correctly separated automatable from human-judgment items. | **Medium.** Clears maintenance debt. But this is a one-off capability, not a persistent feature. The pattern (scan backlog → rank → automate) could be formalized. |
| **Bottleneck Thread (Cultural Initiative)** | 2026-03-04 (msg #14-16, session 2 msg #3-5) | Agent drafted team message based on 1:1 insights from Selinah and Sam. Message posted to eng chat, received 3 responses. Agent synthesized cross-cutting pattern (Valerii's validation loop + Sam's MCP hang = same root cause: tool reliability). Follow-up reply connected dots across thread and linked to Eric's tech talk. | User needed multiple drafts. First was too generic. User added: thread emoji, bold the asks, expand scope beyond AI. Agent adapted. | **Medium.** The agent's ability to synthesize across people profiles, meeting notes, and gchat messages enabled a cultural leadership move. But this is an emergent behavior, not a discrete feature. |
| **Deep Research Delegation** | 2026-03-05 (msg #15, #39, #42-43, #53, #59) | 5 deep research agents launched: proactive workflows, MetaClaw architecture, web UI evaluation, mobile UI evaluation, journey spec formats. Each produced a research brief with comparison tables, gap analysis, and recommendations. Mobile research directly informed team strategy. | Agents ran out of turns (msg #45-46). MetaClaw and web UI agents gathered data but couldn't persist. Had to be resumed. | **Very High.** Research briefs become permanent project context. Mobile research brief informed team-level decisions about visual verification strategy. The pattern (deep research → brief → informed decision) multiplies across all future strategic questions. |

## Features Already Ported (Skipped)

These features are already in hexagon-base and were not analyzed:
- Memory system (SQLite FTS5 indexing)
- Landings (daily outcome targets)
- Session management (startup, save, shutdown, checkpoint)
- Teams (create, connect, sync)
- Evolution engine (observations, suggestions, changelog)
- Transcript backup (hooks)

## Emergent Patterns (Not Documented as Features)

These behaviors emerged from actual usage but aren't discrete features:

1. **"Fire and forget" parallelism**: User consistently launched background agents then switched to different work. The agent managed 3-8 concurrent background tasks without user monitoring. This is a workflow pattern, not a feature.

2. **Correction-to-rule pipeline**: User corrects agent → agent acknowledges → standing order created → behavior permanently changes. This happened 4+ times across 2 days. The speed of operationalization (same-session) is key.

3. **Research-before-position**: User explicitly delayed making decisions until research agents completed. "Let me work on that manually" while agents researched MetaClaw, UI evaluation, etc. The agent's role shifted from executor to researcher.

4. **Message drafting with iteration**: User and agent co-drafted messages in 2-3 rounds. User provided tone/format corrections ("prepend thread emoji", "bold the asks", "4 lines max"). Agent adapted. This is a collaborative writing pattern.

5. **Context dump at any time**: User said "check out the DM with Hritik", "check my latest chat messages", or pasted Google Doc URLs. The agent processed raw context on demand. No ceremony needed.


---

## Landings Analysis

*Analysis of 13 daily landings files (2026-02-20 through 2026-03-06) and 1 weekly target file (W09).*

### 1. Patterns in What Gets Done

**Consistently achieved landings share these traits:**

| Pattern | Evidence | Sessions | Completion Rate |
|---------|----------|----------|-----------------|
| **Landings with clear "unblock someone" framing** | L1 on Feb 20 ("Unblock Training Pod engineers on Interview API contract") landed same day. L5 on Feb 24 ("Get Valerii unblocked") prioritized and tracked. L1 on Feb 27 ("Confirm iOS interview e2e status") stamped 6 diffs. | Feb 20, 23, 24, 25, 26, 27 | ~85% |
| **Landings with a specific meeting as deadline** | L1 on Feb 24 ("Walk into 1:35 meeting with STT one-pager ready") fully prepared: doc published, stakeholder map, talking points. L4 on Feb 26 ("Land AI Transformation Week position before Team Weekly") delivered. | Feb 24, 25, 26 | ~90% |
| **Landings that the agent can draft/execute** | L6 on Feb 25 ("message as me" skill built, tested, submitted). L6 on Mar 4 (context optimization audit, 22→14 plugins). Review Updates Ralph loop (Feb 27 L5). STT one-pager drafted by agent (Feb 24 L1). | Feb 24, 25, 27, Mar 4 | ~95% |
| **Landings with sub-item checklists** | Every landing has sub-items. Completed landings average 5-7 sub-items. User marks them as work progresses. Changelogs reference sub-item completions. | All 13 days | Correlated with completion |

**Key enablers:**
- **Agent-drafted artifacts** (docs, messages, diffs) were the highest-completion category. The agent eliminated the blank-page problem.
- **Meeting-anchored deadlines** created natural forcing functions. Landings like "walk into the 1:35 meeting ready" had near-100% completion.
- **"Unblock someone else" framing** elevated urgency and got done first. These were consistently L1 priority.

### 2. Patterns in What Gets Missed

| Pattern | Evidence | Sessions | Miss Rate |
|---------|----------|----------|-----------|
| **"Position formulation" landings (thinking work, no artifact)** | W5 Playground reliability: set Mon, "stalled" by Thu (20+ hrs silence), never resolved. "Formulate position: yes with conditions" sat at Not Started for 4 days. | Feb 23-27 | ~70% missed or stalled |
| **Landings dependent on external responses** | L5 on Feb 20 (offsite planning, "waiting on Sandeep to confirm headcount") carried forward 3 days. L4 on Feb 25 (STT ownership, "awaiting ETA from Dipansha/Karthick"). W5 Playground. | Feb 20-27 | ~60% stall rate |
| **Weekly update posts** | W6 "weekly update post" set every week. Consistently the last landing addressed. Feb 20: carried to Feb 21. Feb 21: carried further. Feb 27: finally posted. The post itself gets done, but always at the wire. | Feb 20, 21, 26, 27 | Late but eventually done |
| **Stretch/optional landings** | L8 on Feb 26 ("Bug Bash visibility") killed same day. MSL Convergence doc (Pulkit) deferred 3 times. Logging alignment (W7) deprioritized and carried to W10. | Feb 25-27 | ~80% dropped |

**Key gaps (what's missing that would help):**
- **No escalation trigger.** External dependencies stalled for days without a structured "if no response by X, escalate" rule. The system tracked the wait but didn't generate the nudge.
- **No "thinking work" support.** Position formulation (Playground reliability) requires a different workflow than execution landings. The current system treats "formulate a position" the same as "stamp a diff." These need a structured template (evidence → options → recommendation → deliver).
- **No dependency timeout.** When a landing says "Waiting on Sandeep," there's no mechanism to auto-escalate or reframe the landing if the wait exceeds a threshold.

### 3. The Ad-Hoc Landing Pattern

Users added landings mid-day in response to emerging signals. This is evidence of the system being used as a real-time prioritization tool, not just a morning ritual.

| Date | Ad-Hoc Landing | Trigger | When Added |
|------|---------------|---------|------------|
| Feb 23 | L7: "Review Dipansha's document" | Dipansha reviewing Mike's stubs, reciprocity urgency | Sometime after initial set (not in morning sequence) |
| Feb 25 | L6: "Build message-as-me skill" | Personal project idea during deep work | 14:55 changelog entry |
| Feb 26 | L6: "Ensure Training pod maps MCs to new QE" | Pulkit created QE mid-day, immediate dependency | Post-standup addition |
| Feb 26 | L7: "Draft weekly update post outline" | Realized Friday post needs prep Thursday night | End-of-day strategic addition |
| Feb 26 | L8: "Bug Bash visibility" → immediately KILLED | Evaluated and discarded within same day | Morning, then killed by afternoon |
| Feb 27 | L8: "Notification trigger pointers for Core Facts" | Gina Park ask surfaced during work | 12:05 changelog |
| Mar 4 | L6: "Context optimization audit" | Background agent completed the work, added retroactively | 20:15 changelog |
| Mar 5 | L8-L12: Five additional landings | Emerged during hackathon build day | Throughout the day |

**What triggered ad-hoc additions:**
1. **Reciprocity signals** (someone reviewed your work → review theirs immediately)
2. **New information from meetings/chats** (QE created → must map params)
3. **Personal project momentum** (deep work spawns new ideas)
4. **Background agent completion** (agent finishes → new landing to review)
5. **Deprioritization events** (evaluated and killed within hours)

**Compound effect:** The landing system's value increases when it's used for real-time triage, not just morning planning. The ad-hoc additions show the user treating landings as a living dashboard. Each addition/kill is a prioritization decision that's tracked.

### 4. Sub-Item Completion Rates by Type

| Sub-Item Type | Avg Completion | Examples | Notes |
|---------------|---------------|----------|-------|
| **"Ping/message someone"** | ~95% | "Ping Karthick on CAF backfill status" "DM Hritik about hackathon" | Quick, concrete, agent can draft |
| **"Stamp/review a diff"** | ~90% | "Stamp D94291578 for Chirayu" "Review Valerii's 6 iOS diffs" | Clear success criteria |
| **"Draft a document/post"** | ~85% | "Draft STT one-pager" "Write weekly update post" | Agent drafts, user polishes |
| **"Research/investigate"** | ~80% | "Research FTW format" "Research current Playground status" | Agent excels at this |
| **"Confirm/verify status"** | ~75% | "Confirm e2e at Training Pod Sync" "Check v2 backfill ETA" | Depends on meetings |
| **"Formulate position/decide"** | ~40% | "Formulate position: yes with conditions" "Decide hackathon project" | Requires user judgment, often deferred |
| **"Escalate/push back"** | ~50% | "Escalate Personality/Humor design blocker" "Raise at Team Weekly if no response" | Uncomfortable, gets deferred |

**Key insight:** Sub-items that the agent can execute (ping, draft, research) have 80-95% completion. Sub-items requiring human judgment (formulate position, decide, escalate) have 40-50% completion. This is the productivity gap the agent should help close.

### 5. Weekly Target Patterns (W09)

**W09 had 9 weekly targets. Final status:**

| Target | Status | Type | Compound? |
|--------|--------|------|-----------|
| W1: Core Facts e2e | Code-Complete | Engineering convergence | No (one-shot) |
| W2: Interview text e2e | In Progress | Engineering convergence | No (one-shot) |
| W3: Audio capture pipeline | Done | Engineering convergence | No (one-shot) |
| W4: STT scoping | Done | Scoping/ownership | Yes (informed future sprints) |
| W5: Playground reliability | Stalled | Position formulation | No (died without resolution) |
| W6: Weekly update post | Done (late) | Communication ritual | Yes (builds narrative muscle) |
| W7: Logging alignment | Deprioritized | Cross-team alignment | Deferred indefinitely |
| W8: Interview→Core Facts loop | In Progress | Feature scoping | Yes (informed Review Updates) |
| W9: AI Transformation Week prep | Done | Strategic initiative | Yes (shaped team AI culture) |

**What compounds vs. one-shot:**
- **One-shot targets** (W1, W2, W3): Engineering milestones. Done is done. No residual value.
- **Compounding targets** (W4, W6, W8, W9): These produced artifacts, decisions, or cultural shifts that carried into subsequent weeks. STT scoping informed engineering assignments. The weekly post built stakeholder narrative. AI Transformation Week prep shaped team direction.
- **Dead targets** (W5, W7): Never resolved, deprioritized, or stalled. These are evidence of targets that should have been reframed or killed earlier.

**Recommendation for hexagon-base:** Weekly targets should be tagged as "one-shot" vs. "compounding." Compounding targets deserve more protection from deprioritization because their value multiplies. One-shot targets should be more aggressively killed or reframed if they stall.

### 6. Features Surfaced by Landings Analysis

| Feature | Evidence from Landings | Compound Effect | Not in Hexagon-Base? |
|---------|----------------------|-----------------|---------------------|
| **Dependency timeout / escalation trigger** | W5 Playground stalled 4 days with no auto-escalation. External dependency landings had ~60% stall rate. | **High.** Auto-nudges prevent items from silently dying. Each timeout rule improves all future dependency tracking. | Yes, missing |
| **Thinking-work templates** | "Formulate position" landings had ~40% completion. No structured support for evidence→options→recommendation flow. | **High.** Converts amorphous thinking tasks into structured checklists, improving completion rate for the hardest work. | Yes, missing |
| **Ad-hoc landing insertion (real-time triage)** | 8+ ad-hoc landings added across 13 days. Users treat landings as a living dashboard, not just morning planning. | **High.** Already happening organically. Formalizing it (e.g., `cap` → auto-routes to today's landings) makes the capture→triage→landing pipeline seamless. | Partially (landings exist, but no capture→landing pipeline) |
| **Weekly target classification (one-shot vs compound)** | W09 had 9 targets. 4 were compounding, 3 were one-shot, 2 were dead. No classification system. | **Medium.** Helps users protect high-value targets from deprioritization. But the classification itself is lightweight. | Yes, missing |
| **Agent-executable sub-item tagging** | Sub-items the agent could execute (ping, draft, research) had 80-95% completion vs 40-50% for human-judgment items. | **Medium.** Tagging sub-items as "agent can do this" enables auto-delegation during morning sequence. | Yes, missing |
| **Meeting-anchored deadline tracking** | Landings with meeting deadlines had ~90% completion. System doesn't auto-link landings to calendar events. | **Medium.** Auto-linking landings to meetings creates natural forcing functions. Calendar integration makes deadlines visible. | Yes, missing (needs calendar integration) |


---

## Learnings Analysis

*Analysis of ~/hive/me/learnings.md (446 lines, 18 dated sections spanning 2026-02-22 through 2026-03-06) cross-referenced against 22 standing orders in ~/hive/CLAUDE.md.*

### 1. Learnings That Changed Agent Behavior (Observation → Standing Order)

| Learning | Date Observed | Standing Order Created | Time to Operationalize | Evidence of Impact |
|----------|--------------|----------------------|----------------------|-------------------|
| **"Smallest audience possible" for messages** | 2026-02-27 | SO #6 (same day) | < 1 session | User corrected agent twice for posting DMs to group chats (Karthick/Dipansha QE question, Sara bridge diffs). Standing order prevents agent from ever defaulting to group channels again. |
| **"AI attribution footer on all send_message_as_user"** | 2026-02-27 | SO #10 (same day) | < 1 session | Corrected when message to Chirayu sent without `🤖 via AI`. Rule created immediately. All subsequent messages include footer. Transparency permanently ensured. |
| **"Eden checkout limitation (bpfjailer)"** | 2026-02-27 | SO #8 (same day) | < 1 session | Discovered `eden clone` fails inside Claude Code due to mount namespace. Standing order prevents agent from attempting it. User never has to debug a silent Eden failure again. |
| **"Never search ~/checkouts/ broadly"** | 2026-02-27 | SO #9 (same day) | < 1 session | Searching Eden mounts from Hive sessions caused extreme slowness. Rule forces codesearch tools. Agent never triggers expensive filesystem traversals from Hive. |
| **"Parallel context updates"** | 2026-03-03 | SO #11 (same day) | < 1 session | Sequential 3+ file edits were slow. Rule enforces parallel sub-agents for independent edits. Every multi-file update is now faster. |
| **"Process improvements must be persisted"** | 2026-03-03 | SO #12 (same day) | < 1 session | Meta-learning from multiple sessions where improvements were discussed but not written down. "If it's not written down, it didn't happen." Ensures all future improvements become permanent rules. |
| **"Meeting note search: always check multiple sources"** | 2026-03-04 | SO #13 (same day) | < 1 session | Sam's meeting notes lost because agent searched only memory index. Three fixes + standing order. User said "That's the gap." Agent now searches 5 sources for any meeting note query. |
| **"Private vault: me/decisions/"** | 2026-03-04 | SO #14 (same day) | < 1 session | Sandeep gave sensitive feedback. Mike asked "where should this go?" Agent proposed private vault, Mike codified it as a rule. Sensitive data never leaks to team syncs. |
| **"Default: Spec → Chief Wiggum → Ralph loop"** | 2026-03-04 | SO #15 (same day) | < 1 session | Pattern emerged from Quick Capture design session. Codified as the default implementation approach for non-trivial tasks. Every future project follows the same pipeline. |
| **"Chief Wiggum must produce run.sh"** | 2026-03-05 | SO #16 (same day) | < 1 session | Mike tried to fire a Ralph loop and got error: no run.sh. Corrected immediately. Every future Chief Wiggum invocation produces all 4 files. |
| **"Verification: fast loop gates slow loop"** | 2026-03-05 | SO #17 (same day) | < 1 session | From iOS verification architecture session. Mike: "that shouldn't need to be run unless the screenshot tests pass first." Architectural principle codified. Prevents burning expensive CI cycles on known-broken code. |
| **"BANNED: find /, ls -R /"** | 2026-03-05 | SO #18 (same day) | < 1 session | Ralph loop prompts (which don't load CLAUDE.md) triggered unbounded `find /` commands. Standing order added AND inlined into all future Ralph loop prompts. Two layers of protection. |
| **"Never use timeout to wrap claude -p"** | 2026-03-06 | SO #20 (same day) | < 1 session (after 2hr debugging) | 2 hours of debugging revealed `timeout` silently suppresses Claude output. Standing order prevents this failure mode permanently. |
| **"Verify before asserting"** | 2026-03-06 | SO #21 (same day) | < 1 session | Agent claimed `--print` was the fix without checking `claude --help`. User: "That's something you need to remember going forward." Standing order ensures evidence before conclusions. |
| **"BANNED: $(command || echo 0) pattern"** | 2026-03-06 | SO #22 (same day) | < 1 session | Bug bit twice (iOS + BOI loops). `set -uo pipefail` + `|| echo 0` produces multiline output, breaking arithmetic. Safe pattern documented. |

**Key finding:** All 15 operationalized learnings went from observation to standing order in the **same session**. Zero delay. The feedback loop is: user corrects → agent acknowledges → standing order created → behavior permanently changes. This is the fastest possible operationalization cycle.

### 2. Decorative Learnings (Noted but Never Operationalized)

| Learning Category | Example | Why It Didn't Operationalize |
|------------------|---------|------------------------------|
| **Career orientation** | "Aggressive about E7 but strategic. Building credibility first." (line 54) | Context for understanding motivation, not an actionable rule. Informs tone, not behavior. |
| **Org mood** | "Widespread frustration and feeling lost" (line 113-118) | Time-bound observation. No recurring behavior to change. |
| **Work patterns** | "Heavy meeting load. 5+ recurring standups" (line 41) | Descriptive, not prescriptive. Doesn't translate to a rule. |
| **Political history** | "Q4 2025: Created friction with a tech doc about recipes" (line 100-106) | Historical context. Useful for understanding sensitivity, but no recurring agent mistake to prevent. |
| **Content strategy** | "YouTube, LinkedIn, website, social media" (line 55) | User's personal brand strategy. Agent doesn't control these channels. |
| **Performance tracking gap** | "Doesn't have a system for mapping contributions to the rubric" (line 109) | Observed but not yet addressed. Could become a future feature (PSC tracking). |
| **Architecture preferences** | "Pivots without ego. Went from Go to TypeScript to Python" (line 227) | Personality insight. Informs how to present options (show landscape, let user decide) but isn't a rule. |
| **Competitive evaluation patterns** | "Won't settle on a major architectural decision without exhaustive comparison" (line 34) | Style preference. The agent adapted organically (presenting more options) but no formal rule needed. |
| **Design session notes** | Hexagon product design (line 213-223), Mesh brainstorm (line 167-177) | Session-specific technical context. Useful for project history, not behavioral rules. |
| **Relationship intelligence** | "Reads people carefully. Noted tension with Sara" (line 48) | Private context that informs meeting prep and comms, but isn't a behavioral rule. |

**Key finding:** Decorative learnings fall into two buckets: (1) **personality/context** that helps the agent understand the user but doesn't require a behavior change, and (2) **time-bound observations** that are historical records, not recurring patterns. Neither type compounds across sessions the way standing orders do.

### 3. The Feedback Loop: Speed and Mechanism

The Hive learning system operates on a **single-session feedback loop**:

```
User corrects agent → Agent writes to learnings.md → Agent creates standing order → Behavior permanently changes
```

**Speed:** Every traced learning was operationalized within the same session it was observed. There is no multi-session lag. The correction-to-rule pipeline is:
- Session timestamp of learning: same as standing order creation date
- Estimated time from correction to standing order: 5-30 minutes

**Mechanism:** The agent explicitly writes the rule to CLAUDE.md's standing orders table. The standing orders are loaded every session as part of CLAUDE.md. This ensures the behavior change persists even across OD resets, new checkouts, and fresh sessions.

**What makes it work:**
1. **Standing Order #12** ("Process improvements must be persisted") is self-reinforcing. It's a meta-rule that ensures all future rules get written down.
2. The learning protocol in CLAUDE.md explicitly instructs the agent to update `me/learnings.md` every session.
3. Standing orders have a **Source** column with dates, creating traceability.

### 4. Dead-End Learnings (Observed → Written → Never Referenced Again)

| Learning | Why It's Dead Weight |
|----------|---------------------|
| "Mike renamed his session to 'happy'" (line 127) | One-time observation. No behavioral implication. |
| "Commute blocks suggest NYC-based" (line 45) | Inferred location. Never relevant to agent behavior. |
| "ffmpeg is available via fbpkg fetch" (line 244) | Technical note that belongs in a tool setup guide, not in learnings about the person. |
| "fbclone and wk new both fail from inside Claude Code" (line 243) | Operational limitation. Already captured in Standing Order #8. Duplicate in learnings.md is redundant. |
| "Mike bookmarks Workplace posts for later integration" (line 240) | Behavior observation with no corresponding rule or feature. |

### 5. Compound Improvement Evidence

The strongest evidence of compounding is the **self-reinforcing rule chain**:

1. **SO #12** (process improvements must be persisted) ensures all corrections become rules.
2. **SO #21** (verify before asserting) prevents the agent from making claims that trigger corrections in the first place.
3. **SO #15** (default: spec → Chief Wiggum → Ralph loop) creates the pipeline that SO #16 (must produce run.sh) and SO #17 (fast gates slow) govern.
4. **SO #18** (banned: find /) was created because Ralph loops don't load CLAUDE.md, which exposed a gap in SO #15's pipeline. The fix addressed both the prompt content and the standing order.

This means the rules compound: each new rule makes the system more robust, and meta-rules (SO #12) ensure the compounding never stops.

### 6. Features Surfaced by Learnings Analysis

| Feature | Evidence from Learnings | Compound Effect | Not in Hexagon-Base? |
|---------|------------------------|-----------------|---------------------|
| **Correction-to-rule pipeline** | 15 learnings operationalized same-session. Standing orders table with Source dates. Zero delay from correction to permanent behavior change. | **Very High.** The defining compound mechanism. A single correction permanently improves all future sessions. Every user interaction is a training signal. | Yes, missing (hexagon-base has evolution engine but no standing orders table with auto-creation) |
| **Structured learnings file** | 446 lines, 18 dated sections. Mix of actionable and decorative. Captures personality, work patterns, decision-making style, and communication preferences. | **High.** Enables personalization and anticipation. Agent that reads learnings.md can match communication style, predict preferences, avoid known frustrations. | Partially (hexagon-base has me/observations.md but no formal learning protocol) |
| **Meta-rule: "If it's not written, it didn't happen"** | Standing Order #12. Created after multiple sessions where improvements were discussed but not persisted. Self-reinforcing: ensures its own perpetuation. | **Very High.** The insurance policy for compound improvement. Without this, all other learnings are at risk of context-window amnesia. | Yes, missing |
| **Decorative vs. actionable learning separation** | Decorative learnings (personality, context) are useful for tone-matching but don't need standing orders. Actionable learnings (corrections, failures) need immediate codification. No formal distinction exists in Hive. | **Medium.** Would help the agent prioritize which learnings to operationalize. But the current approach (operationalize everything the user corrects) works well enough. | Yes, missing (but may not be worth porting) |
| **Standing order traceability** | Source column in standing orders table traces each rule to its originating session date. Enables auditing: which rules are high-impact vs dead weight. | **Medium.** Useful for maintenance (pruning dead rules) but the traceability itself doesn't improve daily productivity. | Yes, missing |


---

## Standing Orders Analysis

*Analysis of 22 standing orders in ~/hive/CLAUDE.md, cross-referenced against session transcripts (2026-03-04, 2026-03-05) and landings files (2026-02-20 through 2026-03-06).*

### 1. Standing Order Classification: High / Medium / Low Impact

| SO# | Rule | Source Date | Impact | Category | Evidence |
|-----|------|-------------|--------|----------|----------|
| 1 | Flag team dissolution, reorg, or scope fights | Setup | **Medium** | Org protection | Setup-time rule. Invoked passively when processing gchat. Mar 4 transcript: agent flagged "Igor leaving Response Gen" as structural change (msg #4). Not frequently triggered but high value when it fires. |
| 2 | Flag someone taking credit or scope encroachment | Setup | **Medium** | Org protection | Setup-time rule. No explicit invocations found in available transcripts. Defensive rule that's high-value when needed but low-frequency. |
| 3 | Scan for visibility/engagement opportunities after gchat pulls | Setup | **High** | Proactive surfacing | Invoked every session during gchat processing. Mar 4: agent surfaced bottleneck thread opportunity from 1:1 insights, leading to team post with 3 responses. Mar 5: identified Ryan's "second brain" interest as follow-up opportunity. |
| 4 | Flag unreplied pings | Setup | **High** | Attention management | Invoked every session. Both Mar 4 and Mar 5 transcripts show "Unreplied pings" as a standard startup section. Prevents messages from falling through cracks. |
| 5 | Post-meeting decision confirmation | Setup | **Medium** | Decision hygiene | Triggered when important meetings occur. Mar 4 transcript references decision confirmation for STT scoping and Playground reliability outcomes. Passive prevention, rarely visible. |
| 6 | Message routing: smallest audience | 2026-02-27 | **High** | Prevented repeat mistakes | Created after agent posted DMs to group chats twice. Mar 4-05: all message sends include explicit recipient confirmation ("Send to Sara Fong DM", "Post to Training CORE Eng"). Zero group-chat misroutes after rule creation. |
| 7 | Daily landings sub-item format: `Done ✓` | 2026-02-27 | **High** | Prevented repeat mistakes | Mar 5 transcript: 6 instances of `Done ✓` format in landings dashboard output. Mar 6 landings: 15+ `Done ✓` entries. Dashboard parser works correctly because format is consistent. Zero format mismatches after rule creation. |
| 8 | Eden checkout limitation (bpfjailer) | 2026-02-27 | **High** | Prevented repeat mistakes | Agent never attempts `eden clone` in any transcript after rule creation. Mar 5: all checkout operations use pre-provisioned paths via mesh. The rule eliminated a class of failures permanently. |
| 9 | Never search ~/checkouts/ broadly | 2026-02-27 | **High** | Prevented repeat mistakes | No broad checkout searches in Mar 4 or Mar 5 transcripts. Agent consistently uses codesearch tools (mcp__plugin_meta_mux__search_files) for fbsource queries. Mar 5: explicit inline of BANNED commands in Ralph loop prompts (line 2040) shows the rule being actively propagated. |
| 10 | AI attribution on send_message_as_user | 2026-02-27 | **High** | Prevented repeat mistakes | Mar 5 transcript (line 3838): "Send via GChat MCP with AI attribution" appears as standard procedure. All send_message_as_user calls include `🤖 via AI` footer. Zero violations after rule creation. |
| 11 | Parallel context updates | 2026-03-03 | **High** | Prevented repeat mistakes | Mar 5: parallel sub-agents used for multi-file updates (line 4453: "Tasks 2-6: Individual checkers — parallel"). Agent dispatches parallel Task agents for independent file edits. Changed default behavior from sequential to parallel. |
| 12 | Process improvements must be persisted | 2026-03-03 | **Very High** | Meta-rule (self-reinforcing) | This rule is the insurance policy for all other rules. After its creation, every session correction immediately becomes a standing order. Mar 4: SO #13, #14, #15 created. Mar 5: SO #16, #17, #18 created. Mar 6: SO #20, #21, #22 created. Without SO #12, these rules might have been discussed but never written. |
| 13 | Meeting note search: always check multiple sources | 2026-03-04 | **High** | Prevented repeat mistakes | Created after Sam's meeting notes were silently lost. Standing order explicitly lists 5 search sources in priority order. `meeting-search.sh` unified script created. Agent never relies on single-source meeting search after this rule. |
| 14 | Private vault: me/decisions/ never shared | 2026-03-04 | **High** | Privacy protection | Created when Sandeep gave sensitive feedback. Agent evaluates sensitivity before routing any meeting notes. Private feedback never appears in team-synced files. One-time setup, permanent protection. |
| 15 | Default: Spec → Chief Wiggum → Ralph loop | 2026-03-04 | **Very High** | Workflow standardization | Most frequently invoked standing order. Mar 5 transcript: 10+ references to "Chief Wiggum" for mesh, topic chats, iOS, Android, proactive workflows. User explicitly references it: "Yeah, standing order #15 exists for a reason" (Mar 5 line 2409). Became the standard implementation pipeline for all non-trivial work. |
| 16 | Chief Wiggum must produce run.sh | 2026-03-05 | **High** | Prevented repeat mistakes | Created after Mike tried to fire a Ralph loop without run.sh. All subsequent Chief Wiggum invocations produce 4 files. Mar 5 transcript shows 5+ Ralph loop setups, all with run.sh. |
| 17 | Verification: fast loop gates slow loop | 2026-03-05 | **High** | Architectural principle | From iOS verification design. Applied to all future Ralph loops: lint before CI, screenshot before simulator. Mar 6 landings show this pattern in BOI self-fix loop structure. |
| 18 | BANNED: find /, ls -R / | 2026-03-05 | **High** | Prevented repeat mistakes | Inlined into every Ralph loop prompt (Mar 5 line 2040: explicit BANNED COMMANDS block). Two layers of protection: standing order in CLAUDE.md + inline in every prompt template. Prevents hangs on devserver Eden mounts. |
| 19 | Overnight resilient self-evolving Ralph loops | 2026-03-05 | **Medium** | Architecture reference | Design pattern documentation. Referenced when building BOI spec (Mar 6: "self-evolving specs" as hackathon concept). More of a reference doc than a frequently invoked rule. |
| 20 | BANNED: timeout wrapping claude -p | 2026-03-06 | **High** | Prevented repeat mistakes | Created after 2 hours of debugging. Every future run.sh avoids timeout. Mar 6 landings: BOI self-fix loop running successfully without timeout wrapper. |
| 21 | Verify before asserting | 2026-03-06 | **Medium** | Behavioral correction | Meta-principle. Hard to measure invocation frequency because it's about what the agent *doesn't* do (make unverified claims). Created after agent claimed `--print` was a fix without checking docs. |
| 22 | BANNED: $(command \|\| echo 0) pattern | 2026-03-06 | **High** | Prevented repeat mistakes | Bug hit twice (iOS loop + BOI loop). Safe pattern documented. All future run.sh scripts use `count=$(cmd 2>/dev/null) || true; count="${count:-0}"`. |

### 2. Standing Order Impact Summary

| Category | Count | SOs | Description |
|----------|-------|-----|-------------|
| **Prevented repeat mistakes** | 12 | #6, #7, #8, #9, #10, #11, #13, #16, #18, #20, #22, #17 | Single correction became permanent behavior. User never had to re-correct on the same issue. |
| **Meta-rule (self-reinforcing)** | 1 | #12 | Ensures all future corrections become rules. The rule that makes all other rules possible. |
| **Workflow standardization** | 1 | #15 | Defined the default implementation pipeline. Most frequently referenced SO. |
| **Proactive surfacing** | 2 | #3, #4 | Automated attention management. Runs every session. |
| **Org/privacy protection** | 3 | #1, #2, #14 | Defensive rules. Low frequency, high consequence when needed. |
| **Decision hygiene** | 1 | #5 | Post-meeting confirmation ritual. Passive prevention. |
| **Architecture reference** | 1 | #19 | Design pattern documentation. Reference, not a rule. |
| **Behavioral correction** | 1 | #21 | Meta-principle about evidence-first thinking. |

### 3. Dead Weight Assessment

**No standing order is truly dead weight.** Every rule was created in response to a real incident. However, some are lower-frequency than others:

| SO# | Usage Frequency | Verdict |
|-----|----------------|---------|
| #1 | Low (triggered once: Igor departure) | Keep. Reorg detection is rare but high-stakes. |
| #2 | No observed invocations | Keep. Credit protection is insurance. Remove only if user explicitly says it's unnecessary. |
| #5 | Low (passive, hard to measure) | Keep. Decision hygiene prevents verbal-only agreements. |
| #19 | Reference doc, not a rule | **Candidate for relocation.** This is architecture documentation, not a standing order. Should move to a reference file. |
| #21 | Hard to measure (absence of bad behavior) | Keep. Meta-principle that prevents a class of errors. |

### 4. CLAUDE.md Structure Analysis: Universal vs Hive-Specific

| Section | Lines | Universal? | Notes |
|---------|-------|------------|-------|
| **How to Use This System** | 12 | **Yes** | Every agent needs a file directory guide. |
| **Teams** | 8 | Partially | Multi-agent coordination is universal. Team sync protocol is Hive-specific. |
| **Session Startup Checklist** | 33 | **Yes** | Every agent needs a startup sequence. The specific steps (gchat, calendar) are configurable. |
| **Multi-Session Protocol** | 26 | **Yes** | Any persistent agent needs multi-session conflict prevention. SQLite WAL, file locking, re-read-before-write are universal patterns. |
| **Core Principle** | 22 | **Yes** | "Your job is to make [user] successful." The proactive stance and attention management principles are universal. |
| **Learning Protocol** | 3 | **Yes** | Every agent should learn about its user. The instruction to observe, not just receive, is key. |
| **Standing Orders** | 29 | **Yes** | The standing orders *table structure* is universally valuable. The specific orders are user-specific. |
| **Safe Mode** | 43 | Hive-specific | The concept (hide sensitive context during demos) is universal. The implementation is Hive's file structure. |
| **Memory System** | 70 | **Already ported** | Hexagon-base has its own memory system. |
| **Context Persistence** | 26 | **Yes** | "Persist after every message" and "if you thought it, write it" are universal agent principles. |
| **Meeting Prep** | 20 | **Yes** | Structured meeting prep with attendee cross-reference is universally valuable. |
| **Interaction Style** | 14 | Partially | Two-mode interaction (assistant vs sparring partner) is universal. Communication rules are user-specific. |
| **File Index** | 65 | Hive-specific | Specific to Hive's directory structure. Every agent needs *a* file index, but this one is Hive's. |
| **Dispatch** | 53 | Hive-specific | Checkout-based task dispatch is Hive-specific infrastructure. |

**Essential sections for any agent (port to hexagon-base):**
1. File directory guide (How to Use This System)
2. Session startup checklist (configurable steps)
3. Multi-session conflict prevention
4. Core principle ("make user successful" + proactive stance)
5. Learning protocol (observe, don't just receive)
6. Standing orders table (with Source column for traceability)
7. Context persistence rules ("persist after every message", "if you thought it, write it")
8. Meeting prep structure

**Hive-specific sections (do not port):**
1. Dispatch system (checkout-based)
2. Safe mode implementation details
3. File index (specific directory structure)
4. Teams sync protocol

### 5. Compound Improvement: The Standing Orders Flywheel

The standing orders system produces a **self-reinforcing improvement flywheel**:

```
User encounters friction → Corrects agent → Agent creates standing order → 
Behavior permanently changes → User encounters less friction → 
Fewer corrections needed → Higher-leverage corrections emerge
```

**Evidence of the flywheel accelerating:**
- **Week 1 (Feb 27):** 5 standing orders created. Mostly operational fixes (message routing, format parsing, Eden limitations). These are "stop doing dumb things" corrections.
- **Week 2 (Mar 3-4):** 5 standing orders created. Mix of operational (#11, #13) and architectural (#14, #15). The user started codifying *workflows*, not just fixing mistakes.
- **Week 3 (Mar 5-6):** 7 standing orders created. Mostly architectural principles (#17, #19) and meta-rules (#12, #21). The corrections shifted from "stop breaking things" to "here's how to think."

This progression. operational fixes → workflow standards → thinking principles. is evidence that the standing orders system compounds: as low-level mistakes are eliminated, the user's corrections shift to higher-leverage improvements.

### 6. Features Surfaced by Standing Orders Analysis

| Feature | Evidence from Standing Orders | Compound Effect | Not in Hexagon-Base? |
|---------|------------------------------|-----------------|---------------------|
| **Standing orders table with auto-creation** | 22 standing orders, all created same-session as triggering event. Source column with dates. 12/22 directly prevented repeat mistakes. | **Very High.** The core compound mechanism. Single correction → permanent behavior change. The system gets better with every user interaction. | Yes, missing (hexagon-base has evolution engine but no standing orders table) |
| **Meta-rule: "Process improvements must be persisted" (SO #12)** | Self-reinforcing rule that ensures all future corrections become permanent. After SO #12, every session produced 2-5 new standing orders. | **Very High.** Without this, standing orders would stop being created. It's the rule that makes all other rules possible. | Yes, missing |
| **CLAUDE.md as agent constitution** | 449 lines of structured behavior rules. 16 sections covering startup, learning, persistence, interaction, memory, meeting prep. Every session loads this and follows it. | **Very High.** The agent's behavior is entirely governed by this file. Changes to CLAUDE.md change all future behavior. This is the mechanism for compound improvement. | Partially (hexagon-base has CLAUDE.md.template but it's a bootstrap template, not a living constitution) |
| **Safe mode (context hiding for demos)** | Blocks sensitive files during screen shares. Environment variable scoped per-session. No data leaks during pairing. | **Medium.** Useful but not compound. One-time setup, doesn't improve over time. | Yes, missing |
| **Correction-to-rule speed (same-session)** | All 15 operationalized learnings went from correction to standing order within the same session (~5-30 minutes). Zero multi-session lag. | **High.** Speed matters. If corrections took multiple sessions to codify, the user would have to re-correct during the gap. Same-session operationalization eliminates the gap entirely. | Depends on implementation |
