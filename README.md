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

## Set up with Claude Code

The easiest way to configure the template is to let Claude Code do it. The repo is designed to be read and configured by an AI agent — `CLAUDE.md` tells the agent exactly what needs filling in, and it can walk you through the whole thing interactively.

**1. Use the template on GitHub**

Click **"Use this template"** → **"Create a new repository"** on [github.com/Dorvaryn/brain-template](https://github.com/Dorvaryn/brain-template). Name it `brain` (or whatever you prefer), clone it locally:

```bash
git clone git@github.com:YOUR_USERNAME/brain.git ~/brain
```

**2. Open Claude Code in the repo**

```bash
claude ~/brain
```

**3. Paste this prompt to get started**

```
I've just cloned brain-template to use as my personal wiki. Here's my setup:

- Name: [your name]
- Role: [your role and org]
- Domain: [what you work on]
- Teams: [list your teams, with Jira board prefixes if you use Jira]
- Integrations I want to enable: [Slack / Outlook / Jira / Confluence / Gmail / none]
- Timezone: [your timezone]
- Personal areas to track: [e.g. side projects, travel, reading — or skip]

Please read CLAUDE.md and config.yml, fill in the Identity section, configure
config.yml for my setup, then run bin/setup-check.sh to show what still needs
doing outside the repo.
```

Claude will read `CLAUDE.md`, understand the schema, fill in `config.yml` and the Identity section from your description, and run `setup-check.sh` to surface anything that still needs manual wiring (settings.json hooks, skill symlinks, global CLAUDE.md). You only need to handle the parts that touch files outside the repo.

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

### 3. Run the installer

```bash
bash ~/brain/bin/install.sh
```

Wires everything automatically: `BRAIN_DIR` env var, session hooks, MCP server, skill symlinks, global `CLAUDE.md`, and shell profiles. Also handles Gemini CLI and Windows Claude desktop app if present.

**Optional:** if [Starship](https://starship.rs) is installed, the installer also configures the `ai-statusline.sh` brain metrics statusline for Claude Code and Antigravity CLI. If Starship isn't present, the statusline step is skipped with a note — install Starship and re-run `install.sh` to pick it up.

Verify the setup:

```bash
bash ~/brain/bin/setup-check.sh
```

Runs read-only checks across BRAIN_DIR, git remote, hooks, MCP server, skill registration, and config placeholders — prints exactly what to fix for anything that fails.

### 4. Run the first dream cycle

Open Claude Code in any project and run:

```
/brain-dream
```

On first run with an empty `raw/`, it initialises the wiki structure and writes a first log entry. From here, you can start adding raw captures manually (drop `.md` files into `raw/inbox/`) and re-running `/brain-dream` to synthesise them.

---

## Obsidian dashboard (optional)

`dashboard.md` in the repo root is an [Obsidian](https://obsidian.md) + [Dataview](https://github.com/blacksmithgu/obsidian-dataview) dashboard. Open the brain repo as an Obsidian vault and enable the Dataview plugin to get live views of open items, active projects, stale decisions, and recently resolved items. Optional personal-area sections (travel, theatre, etc.) are included as commented-out examples.

The wiki is plain markdown — Obsidian is optional. The brain-session skill provides equivalent context at every session start without it.

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
├── hooks/
│   ├── brain-start.sh           # Claude Code SessionStart hook — git pull
│   ├── brain-end.sh             # Claude Code SessionEnd hook — auto-commit raw/
│   ├── brain-stop.sh            # Claude Code Stop hook — capture reminder
│   ├── gemini-brain-start.sh    # Gemini CLI SessionStart hook — git pull + systemMessage
│   ├── gemini-brain-end.sh      # Gemini CLI SessionEnd hook — commit raw/ + systemMessage
│   └── gemini-brain-post.sh     # Gemini CLI PostToolUse hook — capture reminder
├── bin/
│   ├── install.sh               # One-shot machine setup (Claude Code + Gemini CLI)
│   ├── setup-check.sh           # Verify setup is intact (read-only)
│   └── ai-statusline.sh         # Brain metrics statusline (optional — requires Starship)
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
