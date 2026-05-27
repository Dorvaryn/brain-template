# Brain — Your LLM-Maintained Personal Wiki

A personal knowledge management system built on the [Karpathy LLM-wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f): compile knowledge once, maintain it continuously, query it instantly. The LLM writes the wiki; AI tools and humans alike read it.

---

## How it works

```
raw/        ←  immutable captures (sessions, tickets, email, calendar, Slack…)
  ↓ /brain-dream
wiki/       ←  LLM-maintained synthesis (projects, decisions, architecture, people…)
  ↓
AI tools read it  (context injection at session start, mid-session queries, cross-tool access)
Humans read it    (review, planning, reference)
```

Three immutable layers:
1. **`raw/`** — append-only captures. Written by ingest commands and session hooks. Never modified after write.
2. **`wiki/`** — synthesised knowledge. Written only by the dream cycle.
3. **`CLAUDE.md`** — the schema. Read first by every agent, every time.

The wiki is the AI's persistent memory as much as it is yours. At session start, the brain-session skill loads relevant wiki context so the AI arrives with full situational awareness — no re-explaining. The structured frontmatter and consistent page format are optimised for machine parsing, not just human readability. Any AI tool with filesystem access to the repo can query it.

---

## Quick start (minimal — no integrations)

**Requirements:** [Claude Code](https://claude.ai/code) CLI installed.

### 1. Fork or clone this repo

```bash
gh repo clone Dorvaryn/brain-template ~/brain
cd ~/brain
```

### 2. Configure

Edit two files:

**`config.yml`** — set your name, timezone, teams, and which integrations to enable.

**`CLAUDE.md`** — update the `## Identity` section with your name, role, org, and domain.

### 3. Wire up Claude Code

Add to your global `~/.claude/CLAUDE.md`:

```markdown
## Brain System

@~/brain/prompt.md

The brain-session skill is always active. Apply it in every session without being asked.

Brain repo: ~/brain
Brain MCP server: brain (filesystem access to the brain repo)
```

Add the brain MCP server to your Claude Code config (`~/.claude/claude_desktop_config.json` or equivalent):

```json
{
  "mcpServers": {
    "brain": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/home/YOUR_USER/brain"]
    }
  }
}
```

Register the skills in your Claude Code project or global settings:

```json
{
  "skills": [
    "~/brain/skills/brain-session",
    "~/brain/skills/brain-dream",
    "~/brain/skills/brain-ingest",
    "~/brain/skills/brain-status",
    "~/brain/skills/brain-sync"
  ]
}
```

Add the session hooks to your global `~/.claude/settings.json`. The `SessionStart` hook pulls the latest brain state before each session; the `SessionEnd` hook commits and pushes any new `raw/` captures so they are available on other machines:

```json
{
  "env": {
    "BRAIN_DIR": "/home/YOUR_USER/brain"
  },
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash $BRAIN_DIR/bin/brain-start.sh"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash $BRAIN_DIR/bin/brain-end.sh"
          }
        ]
      }
    ]
  }
}
```

The scripts live in `bin/` in this repo. `brain-start.sh` fails gracefully if there is no network or the remote is not yet configured. `brain-end.sh` is a no-op if there are no new captures.

Once everything is configured, verify the setup with:

```bash
bash ~/brain/bin/setup-check.sh
```

This runs 19 read-only checks across BRAIN_DIR, git remote, hook scripts, settings.json, CLAUDE.md, skill registration, and config placeholders — and prints exactly what to fix for anything that fails.

### 4. Run the first dream cycle

Open Claude Code in any project and run:

```
/brain-dream
```

On first run with an empty `raw/`, it initialises the wiki structure and writes a first log entry. From here, you can start adding raw captures manually (drop `.md` files into `raw/inbox/`) and re-running `/brain-dream` to synthesise them.

---

## Full setup (with integrations)

Each integration requires an MCP server. Enable only what you use — the dream cycle skips unavailable sources gracefully.

| Integration | MCP server | Captures |
|---|---|---|
| Jira | Atlassian MCP (`claude.ai/integrations`) | Tickets, epics, board activity |
| Slack | Slack MCP (`claude.ai/integrations`) | Saved items, monitored channels, canvases |
| Outlook email | Microsoft 365 MCP (`claude.ai/integrations`) | Filtered work email |
| Outlook calendar | Microsoft 365 MCP (`claude.ai/integrations`) | Meetings, transcripts |
| Gmail | Google tools (Gemini CLI) or Gmail MCP | Filtered personal email |
| Google Calendar | Google tools (Gemini CLI) or GCal MCP | Personal events |
| Confluence | Atlassian MCP (`claude.ai/integrations`) | RFCs, ADRs, meeting pages |

Configure each integration's filters in `config.yml`. See inline comments for details.

### Running ingest

```
/brain-ingest   # pull from all configured sources → raw/
/brain-dream    # synthesise raw/ → wiki/
```

Or run them together as a daily habit. The `brain-session` skill runs automatically at the start of every Claude Code session and loads relevant wiki context.

---

## Commands

| Command | What it does |
|---|---|
| `/brain-ingest` | Pull from all configured sources → `raw/` |
| `/brain-dream` | Synthesise `raw/` → `wiki/`, run lint, commit |
| `/brain-dream --full` | Reprocess all `raw/` files (asks confirmation) |
| `/brain-sync` | Commit and push pending `raw/` captures |
| `/brain-status` | Health check — last dream, pending captures, open questions |

---

## Directory structure

```
brain/
├── CLAUDE.md                    # Schema and agent instructions — read first
├── config.yml                   # Runtime config — edit this, not CLAUDE.md
├── prompt.md                    # LLM prompt injected into every session
├── index.md                     # Master content index (LLM-maintained)
├── log.md                       # Append-only operation log (LLM-maintained)
├── raw/                         # Immutable captures — never edited after write
│   ├── sessions/                # Session captures from brain-session skill
│   ├── tickets/                 # Jira captures
│   ├── slack/                   # Slack saved items + channels
│   ├── gmail/                   # Gmail captures
│   ├── outlook/                 # Outlook email captures
│   ├── google-calendar/         # Google Calendar events
│   ├── outlook-calendar/        # Outlook Calendar events
│   ├── confluence/              # RFC and ADR page captures
│   ├── transcripts/             # Teams meeting transcripts
│   ├── reading/                 # Web clipper drops + manual reading notes
│   ├── inbox/                   # Manual captures — quick notes, unstructured
│   └── cowork/                  # Pair/co-work session outputs
├── wiki/                        # LLM-maintained synthesis
│   ├── teams/                   # One page per team
│   ├── projects/                # One subdirectory per team area (matches config.yml teams[].area)
│   │   ├── my-team/             # ← example: matches area: "my-team" in config.yml — rename to your team
│   │   ├── leadership/          # always present — cross-team and org-level work
│   │   └── personal/            # always present — personal projects and life admin
│   ├── decisions/               # Decisions (type: decision) and questions (type: question)
│   ├── people/                  # People pages
│   ├── architecture/            # Architecture positions, RFCs, ADRs
│   ├── knowledge/               # Durable reference material
│   └── week-notes/              # Weekly notes
├── skills/                      # Claude Code skill definitions
│   ├── brain-session/SKILL.md
│   ├── brain-dream/SKILL.md
│   ├── brain-ingest/SKILL.md
│   ├── brain-status/SKILL.md
│   └── brain-sync/SKILL.md
├── bin/                         # Session lifecycle hooks (referenced by settings.json)
│   ├── brain-start.sh           # SessionStart: git pull to sync before session
│   └── brain-end.sh             # SessionEnd: auto-commit new raw/ captures
└── templates/                   # Frontmatter templates for each entity type
```

---

## Customisation

### Adapting the personal areas

The default personal areas (theatre, travel, life-admin, etc.) are examples. Edit `config.yml` and `CLAUDE.md` to match your life. The system has no hard dependency on any specific area names.

### Adding wiki entity types

The entity types in `CLAUDE.md` (project, decision, architecture, person, etc.) are the core schema. You can add new types by defining their frontmatter and page format in `CLAUDE.md`. The dream cycle will pick them up on next run.

### Multi-machine setup

The repo is designed to sync via git. Run `/brain-sync` at the end of a session to push captures; run `git pull` at the start of another machine's session to pick them up. The startup hook in the example global `CLAUDE.md` does a `git pull` automatically.

---

## Philosophy

- **The wiki is the product.** Raw captures are ephemeral inputs. The wiki is what you and your AI tools actually read and query.
- **LLM writes, everyone reads.** Don't edit wiki pages manually — run `/brain-dream` and let the agent maintain them. Both you and the AI consume the output.
- **Compile once, query always.** The dream cycle is expensive; sessions are cheap. Invest in the dream cycle so every session — human or AI — gets instant, rich context.
- **Design for machines first.** Consistent frontmatter, predictable page structure, and dense factual language all make the wiki more useful to AI tools. Human readability follows naturally from those same properties.
- **Tool-agnostic.** The wiki is plain markdown with YAML frontmatter. Claude, Gemini, or any AI tool with filesystem access can consume it. The skills in this repo target Claude Code, but the data layer is not Claude-specific.
- **Finance is always manual.** Never configure automated financial data capture.
