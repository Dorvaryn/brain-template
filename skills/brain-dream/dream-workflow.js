export const meta = {
  name: 'brain-dream',
  description: 'Synthesise raw/ captures into wiki/ pages — one agent per file, up to 14 concurrent',
  phases: [
    { title: 'Scope', detail: 'determine pending raw files since last dream-cycle' },
    { title: 'Synthesise', detail: 'one agent per raw file, pipeline' },
    { title: 'Finalise', detail: 'update index.md, log.md, lint, commit' },
  ],
}

const SCOPE_SCHEMA = {
  type: 'object',
  properties: {
    files: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          path: { type: 'string' },
          sourceType: { type: 'string' },
          isModified: { type: 'boolean' }
        },
        required: ['path', 'sourceType', 'isModified']
      }
    },
    since: { type: 'string' },
    runTimestamp: { type: 'string' }
  },
  required: ['files', 'runTimestamp']
}

const SYNTHESIS_SCHEMA = {
  type: 'object',
  properties: {
    rawFile: { type: 'string' },
    pagesCreated: { type: 'array', items: { type: 'string' } },
    pagesUpdated: { type: 'array', items: { type: 'string' } },
    logNote: { type: 'string' }
  },
  required: ['rawFile', 'pagesCreated', 'pagesUpdated', 'logNote']
}

const FINALISE_SCHEMA = {
  type: 'object',
  properties: {
    newPages: { type: 'integer' },
    updatedPages: { type: 'integer' },
    lintFlags: { type: 'array', items: { type: 'string' } },
    slackUnsaves: { type: 'array', items: { type: 'string' } }
  },
  required: ['newPages', 'updatedPages', 'lintFlags', 'slackUnsaves']
}

const ENV_SCHEMA = {
  type: 'object',
  properties: { brainDir: { type: 'string' } },
  required: ['brainDir']
}

const env = await agent(
  'Run via Bash: echo $BRAIN_DIR\nReturn the trimmed output (no trailing slash or newline) as brainDir.',
  { label: 'env', phase: 'Scope', schema: ENV_SCHEMA }
)
const BRAIN_DIR = env.brainDir
const FULL = (args && args.full) === true

phase('Scope')

const scope = await agent(`
You are scoping a brain dream cycle.

Brain dir: ${BRAIN_DIR}
Full reprocess: ${FULL ? 'YES — process ALL raw/ files' : 'NO — only files added/modified since last dream-cycle'}

Steps:
1. Capture the current UTC timestamp via Bash: date -u +%Y-%m-%dT%H:%MZ — this is the runTimestamp.
2. Read ${BRAIN_DIR}/log.md — find the most recent line matching "## [YYYY-MM-DDTHH:MMZ] dream-cycle |" and extract the timestamp.
3. ${FULL
    ? `List ALL files under ${BRAIN_DIR}/raw/ (excluding .gitkeep). Use find ${BRAIN_DIR}/raw -type f -not -name .gitkeep`
    : `Run: git -C ${BRAIN_DIR} log --since="<extracted timestamp>" --name-only --diff-filter=AM --pretty=format: -- raw/ | sort -u | grep -v "^$"
    Prepend ${BRAIN_DIR}/ to each path so it is absolute.`
  }
4. For each file path, set sourceType based on its directory segment:
   raw/captures → captures | raw/tickets → tickets | raw/slack → slack
   raw/outlook → outlook | raw/outlook-calendar → outlook-calendar
   raw/confluence → confluence | raw/onedrive → onedrive
   raw/reading → reading | raw/inbox → inbox | raw/cowork → cowork
   raw/transcripts → transcripts | raw/gmail → gmail | raw/google-calendar → google-calendar
5. For --full, set isModified=false for all. Otherwise, run:
   git -C ${BRAIN_DIR} log --since="<timestamp>" --name-only --diff-filter=M --pretty=format: -- raw/ | sort -u | grep -v "^$"
   and mark those paths as isModified=true.
6. Return the files array, the since timestamp (or null for --full), and the runTimestamp.
`, { label: 'scope', phase: 'Scope', schema: SCOPE_SCHEMA })

if (!scope || scope.files.length === 0) {
  log('No files pending — dream cycle already up to date.')
} else {
  log(`Processing ${scope.files.length} file(s) since ${scope.since || 'beginning'}`)

  phase('Synthesise')

  const results = await pipeline(
    scope.files,
    file => agent(`
You are synthesising one raw brain capture file into wiki pages.

Brain dir: ${BRAIN_DIR}
Raw file: ${file.path}
Source type: ${file.sourceType}
${file.isModified ? 'CAUTION: previously ingested file — check for genuinely new content vs tooling artefact before writing.' : ''}

Steps:
1. Read ${BRAIN_DIR}/CLAUDE.md — entity schemas, page format, rules.
2. Read ${BRAIN_DIR}/config.yml — team/board/channel mappings.
3. Read ${BRAIN_DIR}/skills/brain-dream/SKILL.md — the "## Reference: Synthesis rules" section for your sourceType (2a–2o) and the entity rules.
4. Read the raw file: ${file.path}
5. Extract all items: decisions, questions, architectural positions, projects, people, theatre events, etc.
6. For each item:
   a. Determine the correct wiki page path (find existing or create new).
   b. If the page exists, read it first — then update content and append a ## Log entry.
   c. If new, create it following the entity schema from CLAUDE.md exactly.
7. Write all pages. Raw files are immutable — never modify anything in ${BRAIN_DIR}/raw/.
8. Return: rawFile path, list of pages created (relative paths from ${BRAIN_DIR}/), list of pages updated (relative paths), one-line logNote summarising what this file produced.
`, {
      label: file.path.split('/').slice(-2).join('/'),
      phase: 'Synthesise',
      schema: SYNTHESIS_SCHEMA
    })
  )

  const validResults = results.filter(Boolean)
  const allCreated = validResults.flatMap(r => r.pagesCreated)
  const allUpdated = validResults.flatMap(r => r.pagesUpdated)
  const logNotes = validResults.map(r => `  ${r.rawFile.split('/').pop()}: ${r.logNote}`)

  log(`Synthesis complete — ${allCreated.length} pages created, ${allUpdated.length} updated`)

  phase('Finalise')

  const summary = await agent(`
You are finalising a brain dream cycle.

Brain dir: ${BRAIN_DIR}
Run timestamp: ${scope.runTimestamp}
Files processed: ${scope.files.length}

Pages created (relative to ${BRAIN_DIR}/):
${allCreated.length > 0 ? allCreated.join('\n') : '  (none)'}

Pages updated (relative to ${BRAIN_DIR}/):
${allUpdated.length > 0 ? allUpdated.join('\n') : '  (none)'}

Per-file notes:
${logNotes.join('\n')}

Steps:
1. Read ${BRAIN_DIR}/CLAUDE.md — index.md and log.md conventions.
2. Read ${BRAIN_DIR}/index.md.
3. For each page in "Pages created" above:
   a. Read the page to get its type, slug, and Summary.
   b. Add an entry under the correct section in index.md: [[slug]] -- one-line summary
4. Append to ${BRAIN_DIR}/log.md:
   ## [${scope.runTimestamp}] dream-cycle | ${scope.files.length} files → ${allCreated.length} new pages, ${allUpdated.length} updated
5. Lint — read ${BRAIN_DIR}/skills/brain-dream/SKILL.md "## Reference: Lint rules" section and run each check:
   a. Contradictions: flag with > CONFLICT: blockquote in both affected pages
   b. Orphan pages: wiki pages with no inbound links from index.md or other pages
   c. Potentially resolved open questions: type:question status:open that may be answered by recent activity
   d. Stale items: decisions/questions open >30 days; active projects with no Log update >90 days
   e. Slack un-saves: resolved/complete/seen/abandoned pages with Sources lines containing "· saved" but not "· unsaved"
6. Write index.md and log.md.
7. Commit and push:
   git -C ${BRAIN_DIR} add wiki/ index.md log.md
   git -C ${BRAIN_DIR} commit -m "chore(brain): local dream cycle ${scope.runTimestamp}"
   git -C ${BRAIN_DIR} push origin main
8. Return: newPages count, updatedPages count, lintFlags array (one string per flag), slackUnsaves array (Slack URLs ready to un-save).
`, { label: 'finalise', phase: 'Finalise', schema: FINALISE_SCHEMA })

  log(`Dream cycle complete. ${summary.newPages} new, ${summary.updatedPages} updated. Lint: ${summary.lintFlags.length} flag(s). Un-saves: ${summary.slackUnsaves.length}.`)
  if (summary.lintFlags.length > 0) {
    log('Lint flags:\n' + summary.lintFlags.map(f => '  • ' + f).join('\n'))
  }
  if (summary.slackUnsaves.length > 0) {
    log('Ready to un-save in Slack:\n' + summary.slackUnsaves.map(u => '  • ' + u).join('\n'))
  }
}
