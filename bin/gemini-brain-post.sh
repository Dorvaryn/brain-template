#!/bin/bash
# PostInvocation: inject per-turn capture reminder using agy injectSteps format.
python3 -c "
import json
print(json.dumps({
  'injectSteps': [{
    'ephemeralMessage': 'BRAIN: Review the previous turn. If the user CONFIRMED a decision, agreed to an architectural position, or an open question was identified — write a capture file to ~/brain/raw/captures/YYYY-MM-DD-[topic].md before continuing. Do NOT capture plans you proposed that are pending approval, or options you presented that have not been endorsed.'
  }]
}))
"
