---
name: brain-sync-template
description: Sync brain infrastructure files to brain-template. Detects direction of change (brain→template, template→brain, or conflict) using stored commit SHAs, shows diff, confirms before writing.
---

## Prerequisites

1. Check `$BRAIN_TEMPLATE_DIR` is set: `echo $BRAIN_TEMPLATE_DIR`. If empty: stop and tell the user to run `install.sh` or `export BRAIN_TEMPLATE_DIR=/path/to/brain-template`.
2. Verify it's a git repo: `git -C $BRAIN_TEMPLATE_DIR rev-parse HEAD`. If it fails: stop and tell the user the path is not a valid git repository.

---

## Infrastructure files

**Auto-sync verbatim (brain → template, no transformation):**
- `CLAUDE.md`
- `global-rules.md`
- `claude-global.md`
- `gemini-global.md`
- `bin/` (all files recursively)
- `skills/` (all files recursively)
- `templates/` (all files recursively)
- `.gitignore`

**Review before sync (pause and present diff, ask per-file):**
- `config.yml` — contains personal data (owner, org, Jira boards, Slack channels). Show diff; ask which sections to propagate into the template's placeholder config.
- `prompt.md` — personal prompt style. Skip by default; only ask if it changed since last sync.

**Never sync:**
- `index.md`, `log.md`, `wiki/`, `raw/`, `.brain-template-sync`

---

## Steps

### 1. Read sync state

```bash
cat $BRAIN_DIR/.brain-template-sync
```

Fields: `brain_sha`, `template_sha`, `synced_at`. If the file is missing or either SHA is `none`: treat as never synced — all infrastructure files are in scope.

### 2. Detect changes (run both in parallel)

**Brain changes since `brain_sha`** (infrastructure files only):
```bash
git -C $BRAIN_DIR log --name-only --pretty=format: <brain_sha>..HEAD \
  -- CLAUDE.md global-rules.md claude-global.md gemini-global.md \
     bin/ skills/ templates/ .gitignore config.yml prompt.md \
  | sort -u | grep -v '^$'
```
For never-synced: list all infrastructure files that exist.

**Template changes since `template_sha`**:
```bash
git -C $BRAIN_TEMPLATE_DIR log --name-only --pretty=format: <template_sha>..HEAD \
  | sort -u | grep -v '^$'
```
For never-synced: treat as no template changes.

### 3. Determine direction

| Brain changed | Template changed | Action |
|---|---|---|
| No | No | "Already in sync." Stop. |
| Yes | No | Standard: brain → template. Go to step 4. |
| No | Yes | Unusual: template diverged. Surface files, ask: sync template→brain / discard template changes / abort. |
| Yes | Yes | Conflict. List changed files per side. Ask per-overlapping-file which version to keep. Non-overlapping files sync normally. |

### 4. Show proposed changes

For each changed infrastructure file, show:
```bash
diff $BRAIN_DIR/<file> $BRAIN_TEMPLATE_DIR/<file>
```
Or flag as new/deleted. Present a summary: "N files to update in template."

For `config.yml` (if changed in brain): show full diff, ask explicitly which hunks to propagate.
For `prompt.md` (if changed in brain): ask "Sync prompt.md to template? Default: skip."

**Confirm:** "Sync N files to brain-template? [y/N]" — stop if no.

### 5. Copy approved files

```bash
cp $BRAIN_DIR/<file> $BRAIN_TEMPLATE_DIR/<file>
# For directories:
cp -r $BRAIN_DIR/<dir>/. $BRAIN_TEMPLATE_DIR/<dir>/
```

For `config.yml`: apply only the approved sections as targeted edits (not a full overwrite).

### 6. Commit template

```bash
git -C $BRAIN_TEMPLATE_DIR add -A
git -C $BRAIN_TEMPLATE_DIR commit -m "chore(brain-template): sync from brain $(date -u +%Y-%m-%dT%H:%M:%SZ)"
git -C $BRAIN_TEMPLATE_DIR push origin main
TEMPLATE_SHA=$(git -C $BRAIN_TEMPLATE_DIR rev-parse HEAD)
```

### 7. Update `.brain-template-sync` and commit brain

```bash
BRAIN_SHA=$(git -C $BRAIN_DIR rev-parse HEAD)
SYNCED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
```

Write `$BRAIN_DIR/.brain-template-sync`:
```
brain_sha: <BRAIN_SHA>
template_sha: <TEMPLATE_SHA>
synced_at: <SYNCED_AT>
```

```bash
git -C $BRAIN_DIR add .brain-template-sync
git -C $BRAIN_DIR commit -m "chore(brain): template sync marker $(date -u +%Y-%m-%dT%H:%M:%SZ)"
git -C $BRAIN_DIR push origin main
```

### 8. Report

```
Sync complete.
  N files updated in brain-template.
  brain @ <brain_sha[:7]>  ↔  template @ <template_sha[:7]>
```
