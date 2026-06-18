#!/bin/bash
# PostInvocation: inject per-turn capture reminder using agy injectSteps format.
python3 -c "
import json
print(json.dumps({
  'injectSteps': [{
    'ephemeralMessage': 'BRAIN capture check. Write a capture file for: (1) A decision the USER confirmed — not a plan you proposed; only capture once endorsed. (2) An open question the USER raised or confirmed needs tracking. (3) An architectural position taken or challenged. (4) A vendor/SDK evaluation finding. Do NOT capture your own proposals — wait for the user to endorse them first. Full instructions and body structure: Brain Capture section in gemini-global.md. Confirm clean if nothing applies.'
  }]
}))
"
