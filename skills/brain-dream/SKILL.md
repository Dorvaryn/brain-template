---
name: brain-dream
description: Run the brain dream cycle locally. Ingests raw/ captures into wiki/, runs lint, commits result. Accepts optional --full flag to reprocess all raw files regardless of last run.
---

1. Read `$BRAIN_DIR/CLAUDE.md` and `$BRAIN_DIR/config.yml` via the brain MCP server
2. Determine scope:
   - Default: files in `raw/` added or modified in git since the last `dream-cycle` entry in `log.md`. Fall back to filesystem mtime if git is unavailable. Newly added files are processed normally. Modified files (M) are flagged as "caution: previously ingested — check for new content vs. tooling artefact" but still processed.
   - `--full`: all files in `raw/` (excluding `.gitkeep`)
3. Report scope: "Processing N files [since YYYY-MM-DD | full reprocess]"
4. For `--full`: warn and wait for explicit confirmation before continuing
5. For each file in scope: run the ingest workflow defined in `CLAUDE.md`
   Timezone note: `raw/outlook-calendar/` files store times as UTC ISO 8601 (e.g. `2026-05-21T09:00:00Z`).
   Convert to the local timezone specified in `config.yml` owner.timezone when writing times into wiki pages.
   `raw/google-calendar/` files are already in local time — no conversion needed.
6. Run the lint workflow defined in `CLAUDE.md`
7. Update `index.md` and append to `log.md`
8. Commit and push:
   ```
   git add wiki/ index.md log.md
   git commit -m "chore(brain): local dream cycle [--full] $(date -u +%Y-%m-%dT%H:%M:%SZ)"
   git push origin main
   ```
9. Report: "Dream cycle complete. N files ingested. N wiki pages updated. Lint flags: [summary]."

Rules:
- Always read CLAUDE.md before writing any wiki page
- Raw files are immutable -- never modify anything in raw/ after initial write
- Always ask for confirmation before `--full` reprocess
