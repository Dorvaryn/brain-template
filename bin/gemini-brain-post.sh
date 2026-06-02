#!/bin/bash
# PostInvocation: inject per-turn capture reminder using agy injectSteps format.
python3 -c "
import json
print(json.dumps({
  'injectSteps': [{
    'ephemeralMessage': 'BRAIN: End-of-turn capture check — follow Brain Capture (always active) rules in GEMINI.md. Write captures now, or confirm nothing to capture.'
  }]
}))
"
