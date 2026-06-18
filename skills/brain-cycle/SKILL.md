---
name: brain-cycle
description: Full brain pipeline — ingest all sources, sync raw captures, then synthesise into wiki. The recommended daily driver. Accepts optional --full flag to reprocess all raw files in the dream step.
---

## Invocation

Invoke the Workflow tool with:
- `scriptPath`: `$BRAIN_DIR/skills/brain-cycle/brain-cycle-workflow.js`
- `args`: `{"brainDir": "$BRAIN_DIR", "full": false}` — set `full: true` if `--full` was passed

This runs brain-ingest (including sync) followed by brain-dream in sequence.
Use `/brain-ingest` alone if you only want to capture without synthesising.
Use `/brain-dream` alone if you want to synthesise without re-ingesting (e.g. to process session captures).
