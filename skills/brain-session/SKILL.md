---
name: brain-session
description: Active in every Claude Code and Gemini CLI session. Loads brain wiki context
  at session start and captures decisions, architecture positions, and open questions
  during work. Triggers automatically on every session -- do not wait to be invoked.
  Detects active team from branch Jira prefix, mapped via config.yml. Reads brain/CLAUDE.md
  and brain/config.yml first.
---

# Brain Session Skill

## Session Start Sequence

1. Read `brain/CLAUDE.md` and `brain/config.yml`
2. Detect team from `git branch --show-current` — match branch prefix against `config.yml` teams[].jira_board
3. For personal sessions (no Jira prefix, personal repo): set area from context
4. Read `brain/index.md` and last 20 lines of `brain/log.md`
5. Read `brain/wiki/teams/[detected-team].md` (or personal area page if it exists)
6. Read open questions tagged to detected team/area
7. Read last 5 decisions tagged to detected team/area
8. Read relevant architecture pages tagged to team or cross-cutting

Report at session start:
"Brain loaded. Team/Area: [x]. Open questions: [N].
Recent decisions: [list]. Dream cycle flags: [anything from log]."

If no Jira prefix matches and context is unclear: ask once "Which team/area is this session for?"

## Capture Triggers

Append to `brain/raw/sessions/YYYY-MM-DD-HH.md` (create or append) when:
- A decision is made or discussed
- An architectural position is taken or challenged
- An open question is identified or answered
- A person is mentioned with relevant context
- A project or epic status changes
- A vendor, provider, or SDK is evaluated
- A personal project milestone is reached or changes
- A travel, life admin, or personal area item is discussed

## Capture Format

```markdown
## [HH:MM] decision | Brief title
Team/Area: [value]
Project: [value or n/a]
Decision: What was decided
Rationale: Why
Alternatives: If any
Status: decided|open|deferred
Confidence: high|medium|low

## [HH:MM] open-question | Brief title
Team/Area: [value]
Project: [value or n/a]
Question: What needs answering
Context: Why it matters
Owner: If known

## [HH:MM] architectural-position | Brief title
Teams: [teams this applies to]
Position: What the position is
Constraints: Driving constraints
Trade-offs: What was accepted

## [HH:MM] evaluation | Brief title
Team/Area: [value]
Subject: [vendor/provider/SDK being evaluated]
Context: Why evaluating
Findings: What was found
Status: ongoing|decided|abandoned

## [HH:MM] personal | Brief title
Area: [personal area from config.yml]
Item: What happened or was decided
Context: Why it matters

## [HH:MM] session-summary | End of session
Team/Area: [value]
Key outcomes:
- [bullet]
Open items:
- [bullet]
Next steps:
- [bullet]
```

## Rules

- Do not ask permission before capturing. Capture autonomously at natural breakpoints and at session end.
- For discovery conversations: capture the problem space mapped, approaches considered,
  and emerging positions even when no final decision was made.
- When answering questions about past decisions, context, or projects: query the wiki
  via the filesystem MCP before answering from general knowledge.
- Raw files are immutable after write. Do not modify previous session captures.
- Always read CLAUDE.md before writing any wiki page.
