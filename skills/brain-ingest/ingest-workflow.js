export const meta = {
  name: 'brain-ingest',
  description: 'Run all capture sources — Jira+Slack+OneDrive parallel, M365 sequential, then Confluence',
  phases: [
    { title: 'Parallel', detail: 'Jira + Slack + OneDrive concurrently' },
    { title: 'M365', detail: 'Outlook email → calendar → transcripts (sequential, concurrency limit)' },
    { title: 'Confluence', detail: 'RFC and ADR pages' },
    { title: 'Finalise', detail: 'write log.md entries, report' },
  ],
}

const CAPTURE_RESULT = {
  type: 'object',
  properties: {
    source: { type: 'string' },
    rawFile: { type: 'string' },
    summary: { type: 'string' },
    logLine: { type: 'string' },
    failed: { type: 'boolean' },
    error: { type: 'string' }
  },
  required: ['source', 'summary', 'logLine', 'failed']
}

const ENV_SCHEMA = {
  type: 'object',
  properties: { brainDir: { type: 'string' } },
  required: ['brainDir']
}

const env = await agent(
  'Run via Bash: echo $BRAIN_DIR\nReturn the trimmed output (no trailing slash or newline) as brainDir.',
  { label: 'env', phase: 'Parallel', schema: ENV_SCHEMA }
)
const BRAIN_DIR = env.brainDir

const sourcePrompt = (sourceName, skillSection, extraNotes) => `
You are running the ${sourceName} capture step for the brain ingest system.

Brain dir: ${BRAIN_DIR}

Steps:
1. Read ${BRAIN_DIR}/CLAUDE.md
2. Read ${BRAIN_DIR}/config.yml
3. Read ${BRAIN_DIR}/log.md — find the most recent log entry for this source to determine the lookback timestamp (see SKILL.md for the correct log entry format per source).
4. Read ${BRAIN_DIR}/skills/brain-ingest/SKILL.md — follow ${skillSection} exactly.
5. Execute the capture using the available MCP tools. On failure, wait 5 seconds and retry once.
6. Write output to the appropriate raw/ subdirectory file.
7. Return:
   - source: "${sourceName}"
   - rawFile: the absolute path written (or "" if nothing written)
   - summary: one-line human-readable summary (e.g. "NUTS: 4, AA: 7, MPH: 2 personal")
   - logLine: the full log.md entry line to append (format from SKILL.md "After all captures" section)
   - failed: true if capture failed after retry, false otherwise
   - error: error message if failed, omit or "" otherwise
${extraNotes || ''}
Raw files are immutable after write — never modify a raw file once written.
Do not write to raw/captures/ — that directory is for session captures only.
`

// Phase 1: Jira, Slack, OneDrive — no MCP overlap, run fully concurrent
phase('Parallel')

const group1 = await parallel([
  () => agent(sourcePrompt('Jira', 'section 1 (Jira capture)'), {
    label: 'jira',
    phase: 'Parallel',
    schema: CAPTURE_RESULT
  }),
  () => agent(sourcePrompt('Slack', 'section 2 (Slack capture)'), {
    label: 'slack',
    phase: 'Parallel',
    schema: CAPTURE_RESULT
  }),
  () => agent(sourcePrompt('OneDrive', 'section 8 (OneDrive capture)'), {
    label: 'onedrive',
    phase: 'Parallel',
    schema: CAPTURE_RESULT
  }),
])

// Phase 2: M365 sequential — email, calendar, transcripts share one MCP connection
phase('M365')

const outlookEmail = await agent(
  sourcePrompt('Outlook email', 'section 3 (Outlook email capture)', 'Uses: Microsoft 365 MCP (outlook_email_search)'),
  { label: 'outlook-email', phase: 'M365', schema: CAPTURE_RESULT }
)

const outlookCalendar = await agent(
  sourcePrompt('Outlook calendar', 'section 4 (Outlook calendar capture)', 'Uses: Microsoft 365 MCP (outlook_calendar_search). Wait 5 seconds after outlook-email completes before starting (M365 concurrency limit): sleep 5 via Bash.'),
  { label: 'outlook-calendar', phase: 'M365', schema: CAPTURE_RESULT }
)

const transcripts = await agent(
  sourcePrompt('Transcripts', 'section 4b (Teams transcript capture)', 'Uses: Microsoft 365 MCP. Wait 5 seconds after outlook-calendar completes: sleep 5 via Bash.'),
  { label: 'transcripts', phase: 'M365', schema: CAPTURE_RESULT }
)

// Phase 3: Confluence — Atlassian MCP, after Jira group has completed
phase('Confluence')

const confluence = await agent(
  sourcePrompt('Confluence', 'section 7 (Confluence capture)', 'Uses: Atlassian MCP (searchConfluenceUsingCql, getConfluencePage, etc.)'),
  { label: 'confluence', phase: 'Confluence', schema: CAPTURE_RESULT }
)

// Finalise: write log.md entries, report
phase('Finalise')

const allResults = [
  ...group1.filter(Boolean),
  outlookEmail,
  outlookCalendar,
  transcripts,
  confluence,
].filter(Boolean)

const succeeded = allResults.filter(r => !r.failed)
const failed = allResults.filter(r => r.failed)

await agent(`
You are finalising a brain ingest run.

Brain dir: ${BRAIN_DIR}

Capture results:
${allResults.map(r => `${r.source}: ${r.failed ? 'FAILED — ' + (r.error || 'unknown error') : r.logLine}`).join('\n')}

Steps:
1. Capture the current UTC timestamp via Bash: date -u +%Y-%m-%dT%H:%MZ — save as TIMESTAMP.
2. Read ${BRAIN_DIR}/skills/brain-ingest/SKILL.md — "After all captures" section for log.md entry format.
3. Append one log entry per source that ran (not skipped) to ${BRAIN_DIR}/log.md, using TIMESTAMP.
   Use the logLine values from the results above. For failed sources, format as:
   ## [YYYY-MM-DDTHH:MMZ] [source]-capture | FAILED after retry: [error]
4. Commit and push raw captures:
   git -C ${BRAIN_DIR} add raw/ log.md
   git -C ${BRAIN_DIR} commit -m "chore(brain): session capture TIMESTAMP [skip ci]"
   git -C ${BRAIN_DIR} push origin main
   If nothing to commit (no new raw files), skip the commit silently.
5. Report the full ingest summary in the format specified in SKILL.md "After all captures" section.
`, { label: 'finalise', phase: 'Finalise' })

log(`Ingest complete. ${succeeded.length}/${allResults.length} sources succeeded.${failed.length > 0 ? ' FAILED: ' + failed.map(r => r.source).join(', ') : ''}`)
log('Run /brain-dream to synthesise captures into wiki.')
