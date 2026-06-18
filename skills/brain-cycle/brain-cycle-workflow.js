export const meta = {
  name: 'brain-cycle',
  description: 'Full brain pipeline: ingest all sources, sync raw captures, synthesise into wiki',
  phases: [
    { title: 'Ingest', detail: 'capture all sources and sync raw files' },
    { title: 'Dream', detail: 'synthesise raw captures into wiki pages' },
  ],
}

const ENV_SCHEMA = {
  type: 'object',
  properties: { brainDir: { type: 'string' } },
  required: ['brainDir']
}

const env = await agent(
  'Run via Bash: echo $BRAIN_DIR\nReturn the trimmed output (no trailing slash or newline) as brainDir.',
  { label: 'env', schema: ENV_SCHEMA }
)
const BRAIN_DIR = env.brainDir

phase('Ingest')
await workflow({ scriptPath: `${BRAIN_DIR}/skills/brain-ingest/ingest-workflow.js` })

phase('Dream')
await workflow({ scriptPath: `${BRAIN_DIR}/skills/brain-dream/dream-workflow.js` })

log('Brain cycle complete.')
