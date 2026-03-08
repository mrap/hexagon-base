# Porting Priorities: Hive Features for Hexagon Base

Ranked using evidence from 13 days of landings, 2 full session transcripts, 446 lines of learnings, and 22 standing orders. Every score is backed by specific evidence from porting-evidence.md.

## Scoring Criteria

| Criterion | Weight | Description |
|-----------|--------|-------------|
| Compound Effect | Highest | Does this feature make every future session better? |
| Evidence Strength | High | How much real usage data supports this? |
| AI-Native-ness | Medium | Does it leverage AI in ways non-AI-native users wouldn't discover? |
| Accessibility | Medium | Can a non-technical user benefit without understanding internals? |
| Implementation Complexity | Tiebreaker | Lower is better. 1 = trivial, 10 = massive |

---

## Tier 1: Port Immediately

High compound effect, strong evidence, accessible to new users.

### 1. Standing Orders System (Correction-to-Rule Pipeline)

| Criterion | Score | Evidence |
|-----------|-------|----------|
| Compound Effect | 10 | 15 learnings operationalized same-session. Each correction permanently improves all future sessions. Self-reinforcing flywheel: week 1 = operational fixes, week 2 = workflow standards, week 3 = thinking principles. (porting-evidence.md: Learnings Analysis, Standing Orders Analysis) |
| Evidence Strength | 10 | 22 standing orders created across 10 days. 12/22 directly prevented repeat mistakes. Zero re-corrections on any standing-order topic. (Standing Orders Analysis: SO #6-#22) |
| AI-Native-ness | 9 | Agent autonomously creates permanent rules from user corrections. No manual config editing. The meta-rule SO #12 ("if it's not written, it didn't happen") ensures the system self-perpetuates. |
| Accessibility | 9 | User just corrects the agent naturally. The rule creation is invisible. No technical knowledge needed. |
| Complexity | 3 | Markdown table in CLAUDE.md + protocol for agent to append rows. No scripts needed. |
| **Total** | **41** | |

**Implementation brief:** Add a "Standing Orders" section to CLAUDE.md.template with an empty table (columns: #, Rule, Source Date, Category). Add a protocol instruction: "When the user corrects your behavior, create a standing order immediately. Write the rule, today's date, and categorize it. Read standing orders at startup. Never repeat a corrected mistake." Include meta-rule #12 as the seed standing order. The user experience: correct the agent once, never correct it again.

### 2. Quick Capture + Triage Pipeline

| Criterion | Score | Evidence |
|-----------|-------|----------|
| Compound Effect | 9 | 16 captures triaged in one batch on Mar 5. Captures routed to todo.md, people/, projects/. Without capture, thoughts lost between sessions. Deduplication caught 2 duplicates. Time-sensitive detection flagged 2 items. (Evidence Table: Quick Capture, Capture Triage Pipeline) |
| Evidence Strength | 9 | User built Quick Capture as hackathon submission. `cap` alias launched Claude in capture mode. 16 captures processed with specific routing. (Mar 5 msg #3, #36-41) |
| AI-Native-ness | 8 | AI categorizes and routes raw thoughts to structured locations. Deduplication and time-sensitivity detection are AI-native. No manual filing. |
| Accessibility | 9 | User types a thought, agent handles the rest. Triage is a single command. |
| Complexity | 3 | capture.sh already exists in hexagon-base. Need triage command + routing logic. |
| **Total** | **38** | |

**Implementation brief:** Create `/hex-capture` command (already have `capture.sh`). Create `/hex-triage` command that reads `raw/captures/`, categorizes each item (todo, people, project, errand, idea), detects duplicates against existing files, flags time-sensitive items, and routes to canonical locations. The triage command presents items for batch approval: "Here are 8 captures. 2 are time-sensitive. 1 is a duplicate. Approve routing?" The user experience: dump thoughts anytime via `cap`, triage them in batch when ready.

### 3. Proactive Context Surfacing (Cross-Reference Engine)

| Criterion | Score | Evidence |
|-----------|-------|----------|
| Compound Effect | 9 | Every session starts with awareness of what changed. Mar 4: agent flagged "Igor leaving Response Gen" as structural change from gchat scan. Mar 5: cross-referenced gchat with todo.md to surface unreplied pings and visibility opportunities. (Evidence Table: Proactive Context Surfacing) |
| Evidence Strength | 8 | Invoked every session in both Mar 4 and Mar 5 transcripts. Standing Orders #3 and #4 codify this behavior. (Standing Orders Analysis: SO #3, #4) |
| AI-Native-ness | 9 | AI connects dots across sources (messages, todos, calendar) that human would miss. Surfaces "org signals" like departures and reorgs. |
| Accessibility | 8 | Runs automatically at startup. User sees a summary, not raw data. |
| Complexity | 4 | Startup integration. Needs configurable data sources (gchat, calendar, email). Can start with just todo.md cross-reference. |
| **Total** | **38** | |

**Implementation brief:** Add a "context surfacing" step to startup. After loading todo.md and recent data (if any integrations are configured), cross-reference: items in todo.md with no recent progress, unreplied messages, meetings today with relevant people context. Output a "Needs Attention" section in the startup summary. Start simple: just scan todo.md for stale items (no update in 3+ days) and flag them. Add integration hooks later. The user experience: "Here's what needs attention today" with items they'd otherwise forget.

### 4. People Profile Cross-Referencing

| Criterion | Score | Evidence |
|-----------|-------|----------|
| Compound Effect | 9 | People profiles accumulate across sessions. Mar 4: agent pulled Selinah's context for cultural strategy. Mar 5: Ryan's interests noted for follow-up. Relationship-building opportunities surface automatically. (Evidence Table: People Profile Cross-Referencing) |
| Evidence Strength | 8 | Used in both Mar 4 and Mar 5 sessions. Cross-referenced against meeting prep and message drafting. Sam's bottleneck insights informed team strategy. |
| AI-Native-ness | 8 | Agent maintains relationship intelligence that humans rarely write down. Cross-references across meetings, messages, and projects. |
| Accessibility | 9 | User just mentions a name. Agent pulls context automatically. No manual profile management. |
| Complexity | 2 | Hexagon-base already has people/ directory. Need protocol instruction to read people/{name}/profile.md before any interaction involving that person. |
| **Total** | **36** | |

**Implementation brief:** Add to CLAUDE.md.template: "Before any meeting prep, message drafting, or discussion involving a specific person, check `people/{name}/profile.md`. Update the profile after every interaction with new observations." Add a people cross-reference step to startup that scans today's calendar (if available) and loads relevant people profiles. The user experience: agent already knows the relationship context when preparing for a meeting or drafting a message.

### 5. Escalation Triggers for Stalled Dependencies

| Criterion | Score | Evidence |
|-----------|-------|----------|
| Compound Effect | 8 | W5 Playground stalled 4 days with no auto-escalation. External dependency landings had ~60% stall rate. An escalation trigger would have caught W5 on day 2. (Landings Analysis: Patterns in What Gets Missed) |
| Evidence Strength | 8 | 13 days of landings data. "Waiting on Sandeep" carried 3 days. "Awaiting ETA from Dipansha/Karthick" stalled. Clear pattern: external dependencies die silently. |
| AI-Native-ness | 7 | Agent monitors todo.md/landings for stale external dependencies and generates nudge messages. Human would forget to follow up. |
| Accessibility | 9 | Automatic. Agent checks for stale items during startup and says "This landing has been waiting 3 days. Want me to draft a follow-up?" |
| Complexity | 3 | Scan todo.md and landings for items with "waiting on" or "blocked by" language. Track first-seen date. Alert after configurable threshold (default: 2 days). |
| **Total** | **35** | |

**Implementation brief:** Create a stale-dependency scanner in the startup sequence. Parse todo.md and landings for items containing "waiting on", "blocked by", "pending response", or similar markers. Track when each was first seen (use a `.dependency-tracker.json` file). At startup, flag items older than 2 days with "STALE: [item] has been waiting since [date]. Draft follow-up?" The user experience: dependencies that would silently die instead get surfaced for action.

### 6. Thinking-Work Templates

| Criterion | Score | Evidence |
|-----------|-------|----------|
| Compound Effect | 7 | "Formulate position" landings had ~40% completion vs ~85% for agent-executable tasks. Structured template (evidence, options, recommendation) would close this gap. (Landings Analysis: Sub-Item Completion Rates) |
| Evidence Strength | 8 | W5 Playground: "formulate position: yes with conditions" sat at Not Started for 4 days. Clear pattern across 13 days: amorphous thinking tasks get deferred. |
| AI-Native-ness | 8 | Agent structures the thinking work: gathers evidence, presents options with trade-offs, drafts recommendation. Converts "think about X" into a decision document. |
| Accessibility | 8 | User says "I need to decide about X." Agent produces structured options. No template knowledge needed. |
| Complexity | 3 | Command that takes a topic, produces a decision scaffold: context, options (3), trade-offs, recommendation. Can be a skill or command. |
| **Total** | **34** | |

**Implementation brief:** Create `/hex-decide` command. When user says "I need to decide about X" or has a stalled thinking-work item, the agent structures the problem: (1) gather context from relevant files, (2) present 2-3 options with trade-offs in a table, (3) draft a recommendation with reasoning. Save to `projects/{project}/decisions/` or `me/decisions/`. The user experience: "formulate position on X" becomes a 5-minute structured exercise instead of an indefinitely deferred task.

### 7. Context Persistence Protocol ("Persist After Every Message")

| Criterion | Score | Evidence |
|-----------|-------|----------|
| Compound Effect | 8 | Standing Order #12: "If it's not written, it didn't happen." Context persistence prevents the most common failure mode: discussed but not recorded. (Learnings Analysis: Meta-rule) |
| Evidence Strength | 7 | Self-reinforcing rule created Mar 3. After creation, every session produced 2-5 new standing orders. Without persistence, learnings are lost to context-window compression. |
| AI-Native-ness | 7 | Agent proactively writes observations and decisions to persistent files without being asked. |
| Accessibility | 10 | Invisible to user. Agent persists context automatically. |
| Complexity | 2 | Protocol instruction in CLAUDE.md.template. No scripts needed. |
| **Total** | **34** | |

**Implementation brief:** Add to CLAUDE.md.template: "After every substantive interaction, persist key outcomes: decisions made (write to relevant project or me/decisions/), observations about the user (write to me/learnings.md), action items (write to todo.md), people insights (write to people/). If you discussed something important, write it down before moving on. The rule: if you thought it, write it." The user experience: nothing visible changes. But the next session always has full context.

---

## Tier 2: Port with Design Thought

High compound potential, but needs adaptation for general audience or has implementation nuances.

### 8. Background Agent Delegation Pattern

| Criterion | Score | Evidence |
|-----------|-------|----------|
| Compound Effect | 8 | 8+ background agents in one session (Mar 5). Research agents produced briefs that informed team strategy. MetaClaw research informed proactive workflows decision. |
| Evidence Strength | 8 | Extensive usage across Mar 5. But agents ran out of turns (msg #45-46). Two had to be resumed. Reliability issues. |
| AI-Native-ness | 10 | "Fire and forget" parallel research is the most AI-native pattern observed. Non-AI-native users would never think to spawn 5 researchers. |
| Accessibility | 5 | Requires understanding of what can be parallelized. New users won't instinctively delegate to background agents. |
| Complexity | 6 | Needs Claude Code's Agent tool. Reliability concerns (agents running out of turns). Needs a brief-persistence protocol. |
| **Total** | **37** | (ranked Tier 2 due to low accessibility and reliability concerns) |

**Design consideration:** The pattern is extremely powerful but not beginner-friendly. A "research mode" command that spawns a background agent with persistence guarantees would make this accessible. E.g., `/hex-research "topic"` spawns a background agent that writes findings to `raw/research/{topic}.md`. The user doesn't need to understand agent spawning.

### 9. Meeting Notes Multi-Source Search

| Criterion | Score | Evidence |
|-----------|-------|----------|
| Compound Effect | 7 | Standing Order #13 created after Sam's notes were silently lost. Agent now searches 5 sources for meeting notes. (Standing Orders Analysis: SO #13) |
| Evidence Strength | 7 | Single incident but high-impact. Created a unified `meeting-search.sh` script. |
| AI-Native-ness | 7 | Agent checks calendar, memory, transcripts, raw files, and integration sources. Human would check one place and give up. |
| Accessibility | 8 | Invisible. Agent just finds the notes. |
| Complexity | 5 | Needs multiple search sources. Hexagon-base's memory system handles some of this. Needs adaptation for non-Hive file structures. |
| **Total** | **34** | (ranked Tier 2 due to integration dependency) |

**Design consideration:** Start with memory search + raw/ directory scan. Add integration hooks for calendar and messaging tools as users configure them. The key principle: never rely on a single source.

### 10. Safe Mode (Context Hiding for Demos)

| Criterion | Score | Evidence |
|-----------|-------|----------|
| Compound Effect | 4 | One-time setup. Doesn't improve over time. (Standing Orders Analysis: SO analysis notes it as "useful but not compound") |
| Evidence Strength | 5 | Referenced in CLAUDE.md structure analysis. No specific session incidents in available transcripts. |
| AI-Native-ness | 6 | Agent automatically filters sensitive context during screen shares. |
| Accessibility | 7 | Simple env var toggle. |
| Complexity | 4 | Environment variable + file filtering logic. |
| **Total** | **26** | |

**Design consideration:** Useful for anyone who does screen sharing or pairing. Implementation: `SAFE_MODE=1` environment variable. When set, agent skips reading me/learnings.md, people/ relationship notes, and me/decisions/. Simple but requires identifying which files are "sensitive."

### 11. Ad-Hoc Landing Insertion (Capture-to-Landing Pipeline)

| Criterion | Score | Evidence |
|-----------|-------|----------|
| Compound Effect | 7 | 8+ ad-hoc landings across 13 days. Users treat landings as a living dashboard. Formalizing the capture-to-landing pathway makes the system more fluid. (Landings Analysis: Ad-Hoc Landing Pattern) |
| Evidence Strength | 7 | Clear pattern with specific dates and triggers (reciprocity, meetings, momentum, background agent completion). |
| AI-Native-ness | 6 | Agent routes captures to today's landings when appropriate. |
| Accessibility | 7 | User captures a thought, agent asks "Add this as a landing for today?" |
| Complexity | 3 | Extension of capture + triage. Route "actionable today" captures to landings. |
| **Total** | **30** | |

**Design consideration:** This is a natural extension of Tier 1 items #2 (Quick Capture) and the existing landings system. During triage, if a capture is actionable today, offer to add it as a landing instead of routing to todo.md. Requires the triage command to understand the landings format.

---

## Tier 3: Defer

Hive-specific, weak evidence, or too complex for v1.

### 12. Ralph Loop / Chief Wiggum Integration

| Criterion | Score |
|-----------|-------|
| Compound Effect | 8 |
| Evidence Strength | 9 |
| AI-Native-ness | 10 |
| Accessibility | 3 |
| Complexity | 8 |
| **Total** | **38** |

**Why deferred:** Extremely powerful (Standing Order #15 is the most-referenced SO) but requires deep understanding of autonomous agent loops, spec files, and multi-session workflows. Not accessible to day-1 users. Also tightly coupled to Claude Code's specific capabilities (Agent tool, background execution). Port after core compounding features are established.

### 13. GChat Integration & Space Cache

| Criterion | Score |
|-----------|-------|
| Compound Effect | 8 |
| Evidence Strength | 8 |
| AI-Native-ness | 7 |
| Accessibility | 6 |
| Complexity | 7 |
| **Total** | **36** |

**Why deferred:** Requires MCP tool for Google Chat. Meta-specific in Hive's implementation. Hexagon-base should define integration hooks but not implement platform-specific integrations in v1. The space cache pattern is universally valuable (cache frequently-used resources), but the specific implementation is platform-dependent.

### 14. Context Audit / Token Optimization

| Criterion | Score |
|-----------|-------|
| Compound Effect | 6 |
| Evidence Strength | 5 |
| AI-Native-ness | 6 |
| Accessibility | 4 |
| Complexity | 6 |
| **Total** | **27** |

**Why deferred:** Infrastructure-level optimization. Not visible to users. Token savings matter but are secondary to feature-level compounding. Port after the system is mature enough to have token pressure.

### 15. Backlog Automation Agent

| Criterion | Score |
|-----------|-------|
| Compound Effect | 5 |
| Evidence Strength | 5 |
| AI-Native-ness | 7 |
| Accessibility | 5 |
| Complexity | 6 |
| **Total** | **28** |

**Why deferred:** One-off capability, not a persistent feature. The pattern (scan backlog, rank, automate) is interesting but too advanced for v1. Requires the agent to understand which items are automatable, which needs significant context.

### 16. Weekly Target Classification (One-Shot vs Compound)

| Criterion | Score |
|-----------|-------|
| Compound Effect | 5 |
| Evidence Strength | 5 |
| AI-Native-ness | 5 |
| Accessibility | 6 |
| Complexity | 2 |
| **Total** | **23** |

**Why deferred:** Lightweight addition to landings system. Low complexity but also low individual impact. Can be added later as an enhancement to the landings skill.

### 17. Agent-Executable Sub-Item Tagging

| Criterion | Score |
|-----------|-------|
| Compound Effect | 6 |
| Evidence Strength | 6 |
| AI-Native-ness | 7 |
| Accessibility | 5 |
| Complexity | 5 |
| **Total** | **29** |

**Why deferred:** Requires the agent to reliably distinguish "I can do this" from "the user needs to do this." Interesting but risks over-automation for new users who haven't built trust with the agent yet.

### 18. Deep Research Delegation

| Criterion | Score |
|-----------|-------|
| Compound Effect | 8 |
| Evidence Strength | 7 |
| AI-Native-ness | 10 |
| Accessibility | 4 |
| Complexity | 7 |
| **Total** | **36** |

**Why deferred:** Same accessibility and reliability concerns as #8 (Background Agent Delegation). Extremely powerful but not beginner-friendly. The research briefs are high-value but the spawning and persistence pattern needs more robustness before it's portable.

---

## Summary

| Tier | Features | Key Theme |
|------|----------|-----------|
| **Tier 1** (7 features) | Standing Orders, Quick Capture + Triage, Proactive Context Surfacing, People Profiles, Escalation Triggers, Thinking-Work Templates, Context Persistence | Core compounding: every session makes the next better, automatically |
| **Tier 2** (4 features) | Background Delegation, Multi-Source Search, Safe Mode, Capture-to-Landing | Powerful but needs UX design for accessibility |
| **Tier 3** (7 features) | Ralph Loops, GChat, Token Audit, Backlog Automation, Weekly Classification, Sub-Item Tagging, Deep Research | Too complex, platform-specific, or low-impact for v1 |

**The compound improvement stack:** Tier 1 features form a self-reinforcing loop:
1. **Capture** raw thoughts (Quick Capture)
2. **Route** them to canonical locations (Triage Pipeline)
3. **Surface** what needs attention (Proactive Context)
4. **Structure** hard decisions (Thinking-Work Templates)
5. **Escalate** stalled items (Escalation Triggers)
6. **Learn** from corrections (Standing Orders)
7. **Persist** everything (Context Persistence)

Each feature strengthens the others. Captures feed the todo system. The todo system feeds proactive surfacing. Proactive surfacing triggers escalation. Escalation outcomes feed learnings. Learnings become standing orders. Standing orders prevent future friction. The cycle accelerates.
