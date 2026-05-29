#!/bin/bash
# Gemini CLI SessionEnd hook — outputs JSON as required by Gemini hook spec
# Commits any pending raw/ captures (best-effort: CLI may not wait for completion)
ORIG_PWD=$(pwd -P)
BRAIN_DIR="${BRAIN_DIR:-$HOME/brain}"
cd "$BRAIN_DIR" || exit 0

BRANCH=$(git -C "$ORIG_PWD" branch --show-current 2>/dev/null || echo "no-git")
REPO=$(git -C "$ORIG_PWD" rev-parse --show-toplevel 2>/dev/null | xargs basename 2>/dev/null || basename "$ORIG_PWD")
STAMP=$(date -u +%Y-%m-%d-%H%M)
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
mkdir -p "$BRAIN_DIR/raw/sessions"

# Git context record
SESSION_FILE="$BRAIN_DIR/raw/sessions/$STAMP.md"
if [[ ! -f "$SESSION_FILE" ]]; then
  cat > "$SESSION_FILE" <<RECORD
---
source: session
timestamp: $TIMESTAMP
branch: $BRANCH
repo: $REPO
cwd: $ORIG_PWD
---

## Session Record
Closed: $TIMESTAMP

### Git context
Branch: $BRANCH | Repo: $REPO

### Commits this session (git log --oneline -10)
$(git -C "$ORIG_PWD" log --oneline -10 2>/dev/null || echo "none")

### Staged/modified files (git status --short)
$(git -C "$ORIG_PWD" status --short 2>/dev/null || echo "none")
RECORD
fi

# Conversation transcript extract from Gemini session JSONL
PROJ_NAME=$(basename "$ORIG_PWD")
LATEST_JSONL=$(find "$HOME/.gemini/tmp" -maxdepth 3 -name "session-*.jsonl" \
  -path "*/${PROJ_NAME}*/chats/*" -printf "%T@ %p\n" 2>/dev/null \
  | sort -rn | head -1 | cut -d' ' -f2- || true)
TRANSCRIPT_FILE="$BRAIN_DIR/raw/sessions/$STAMP-transcript.md"
if [[ -n "$LATEST_JSONL" && ! -f "$TRANSCRIPT_FILE" ]]; then
  python3 - "$LATEST_JSONL" "$BRANCH" "$REPO" "$ORIG_PWD" "$TIMESTAMP" <<'PYEOF' > "$TRANSCRIPT_FILE" 2>/dev/null || rm -f "$TRANSCRIPT_FILE"
import json, sys

jsonl_path, branch, repo, cwd, timestamp = sys.argv[1:]
messages = []

with open(jsonl_path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
            if obj.get('type') == 'user':
                for part in obj.get('content', []):
                    text = part.get('text', '').strip()
                    if text:
                        ts = obj.get('timestamp', '')[:16]
                        messages.append(f'[{ts}] User: {text}')
                        break
            elif obj.get('type') == 'gemini':
                text = obj.get('content', '').strip()
                if text:
                    messages.append(f'Assistant: {text}')
        except Exception:
            pass

if not messages:
    sys.exit(1)

print(f"""---
source: session
type: transcript
timestamp: {timestamp}
branch: {branch}
repo: {repo}
cwd: {cwd}
---

## Conversation Transcript

""" + '\n\n'.join(messages))
PYEOF
fi

if [[ -n $(git status --porcelain raw/) ]]; then
  git add raw/ 2>/dev/null
  if git commit -m "chore(brain): session capture $TIMESTAMP [skip ci]" 2>/dev/null; then
    if git push origin main 2>/dev/null; then
      echo '{"systemMessage": "Brain captures committed."}'
    else
      echo '{"systemMessage": "BRAIN WARNING: Committed locally, push failed — run /brain-sync."}'
    fi
  else
    echo '{"systemMessage": "BRAIN WARNING: Commit failed — run /brain-sync manually."}'
  fi
else
  echo '{"systemMessage": "No brain captures pending."}'
fi
