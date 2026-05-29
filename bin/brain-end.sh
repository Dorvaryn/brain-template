#!/bin/bash
set -uo pipefail
ORIG_PWD=$(pwd -P)
BRAIN_DIR="${BRAIN_DIR:-$HOME/brain}"
cd "$BRAIN_DIR"

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

# Conversation transcript extract from Claude session JSONL
PROJECT_SLUG="${ORIG_PWD//\//-}"
LATEST_JSONL=$(ls -t "$HOME/.claude/projects/$PROJECT_SLUG/"*.jsonl 2>/dev/null | head -1 || true)
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
                content = obj.get('message', {}).get('content', '')
                if isinstance(content, str) and content.strip():
                    ts = obj.get('timestamp', '')[:16]
                    messages.append(f'[{ts}] User: {content.strip()}')
            elif obj.get('type') == 'assistant':
                for block in obj.get('message', {}).get('content', []):
                    if isinstance(block, dict) and block.get('type') == 'text':
                        text = block['text'].strip()
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
  if git commit -m "chore(brain): session capture $TIMESTAMP [skip ci]"; then
    git push origin main \
      && echo "Brain captures committed." \
      || echo "BRAIN WARNING: Committed locally, push failed — run /brain-sync."
  else
    echo "BRAIN WARNING: Commit failed — run /brain-sync manually."
  fi
fi
