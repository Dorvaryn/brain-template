#!/bin/bash
# Validates that the brain system is correctly wired up.
# Read-only: makes no changes to any files.
# Run from anywhere: bash ~/brain/bin/setup-check.sh

PASS=0
FAIL=0
WARN=0

# Colour output when connected to a terminal
if [ -t 1 ]; then
  GREEN="\033[0;32m"; RED="\033[0;31m"; YELLOW="\033[0;33m"; RESET="\033[0m"
else
  GREEN=""; RED=""; YELLOW=""; RESET=""
fi

ok()   { echo -e "${GREEN}[PASS]${RESET} $1"; ((PASS++)); }
fail() { echo -e "${RED}[FAIL]${RESET} $1"; [ -n "$2" ] && echo "       → $2"; ((FAIL++)); }
warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; [ -n "$2" ] && echo "       → $2"; ((WARN++)); }

# JSON helper — uses python3 (universal) for reliable parsing
json_has() {
  local file="$1" pattern="$2"
  python3 -c "
import json, sys
try:
    d = json.load(open('$file'))
    print(json.dumps(d))
except: print('{}')
" 2>/dev/null | grep -q "$pattern"
}

echo "Checking brain setup..."
echo ""

# ── 1. BRAIN_DIR ────────────────────────────────────────────────────────────

if [ -z "$BRAIN_DIR" ]; then
  fail "BRAIN_DIR is not set" \
    "Add it to the env section of ~/.claude/settings.json:\n       \"env\": { \"BRAIN_DIR\": \"/path/to/your/brain\" }"
else
  ok "BRAIN_DIR is set ($BRAIN_DIR)"

  if [ -d "$BRAIN_DIR" ]; then
    ok "Brain directory exists"
  else
    fail "BRAIN_DIR points to a directory that does not exist ($BRAIN_DIR)" \
      "Clone the repo: git clone <remote> $BRAIN_DIR"
  fi

  if [ -f "$BRAIN_DIR/CLAUDE.md" ]; then
    ok "CLAUDE.md found in brain repo"
  else
    fail "CLAUDE.md not found in $BRAIN_DIR" \
      "Make sure BRAIN_DIR points to the root of the brain repo"
  fi
fi

echo ""

# ── 2. Git remote ────────────────────────────────────────────────────────────

if [ -n "$BRAIN_DIR" ] && [ -d "$BRAIN_DIR/.git" ]; then
  REMOTE=$(git -C "$BRAIN_DIR" remote get-url origin 2>/dev/null)
  if [ -n "$REMOTE" ]; then
    ok "Git remote configured ($REMOTE)"
  else
    warn "No git remote configured" \
      "Run: git -C \$BRAIN_DIR remote add origin <your-repo-url>"
  fi
else
  warn "Skipping git remote check (BRAIN_DIR not set or not a git repo)"
fi

echo ""

# ── 3. Hook scripts ──────────────────────────────────────────────────────────

for script in brain-start.sh brain-end.sh; do
  path="${BRAIN_DIR}/bin/${script}"
  if [ -z "$BRAIN_DIR" ]; then
    warn "Skipping $script check (BRAIN_DIR not set)"
  elif [ ! -f "$path" ]; then
    fail "$script not found at $path" \
      "Re-clone the brain template or copy bin/$script from the repo"
  elif [ ! -x "$path" ]; then
    fail "$script exists but is not executable" \
      "Run: chmod +x $path"
  else
    ok "$script exists and is executable"
  fi
done

echo ""

# ── 4. settings.json ─────────────────────────────────────────────────────────

SETTINGS="$HOME/.claude/settings.json"

if [ ! -f "$SETTINGS" ]; then
  fail "~/.claude/settings.json not found" \
    "Create it — see the README for the full template"
else
  ok "~/.claude/settings.json exists"

  if json_has "$SETTINGS" "BRAIN_DIR"; then
    ok "BRAIN_DIR env var present in settings.json"
  else
    fail "BRAIN_DIR not found in settings.json env section" \
      "Add: \"env\": { \"BRAIN_DIR\": \"/path/to/your/brain\" }"
  fi

  if json_has "$SETTINGS" "SessionStart"; then
    ok "SessionStart hook configured"
  else
    fail "SessionStart hook missing from settings.json" \
      "Add the hooks block from the README (bin/brain-start.sh)"
  fi

  if json_has "$SETTINGS" "SessionEnd"; then
    ok "SessionEnd hook configured"
  else
    fail "SessionEnd hook missing from settings.json" \
      "Add the hooks block from the README (bin/brain-end.sh)"
  fi
fi

echo ""

# ── 5. Global CLAUDE.md ───────────────────────────────────────────────────────

GLOBAL_CLAUDE="$HOME/.claude/CLAUDE.md"

if [ ! -f "$GLOBAL_CLAUDE" ]; then
  fail "~/.claude/CLAUDE.md not found" \
    "Create it and add the brain reference block from the README"
else
  ok "~/.claude/CLAUDE.md exists"

  if grep -q "brain" "$GLOBAL_CLAUDE" 2>/dev/null; then
    ok "~/.claude/CLAUDE.md references brain"
  else
    warn "~/.claude/CLAUDE.md does not appear to reference the brain" \
      "Add the brain block from the README (prompt.md reference + brain-session skill)"
  fi
fi

echo ""

# ── 6. Skills ────────────────────────────────────────────────────────────────

SKILLS_DIR="$HOME/.claude/skills"
for skill in brain-session brain-dream brain-ingest brain-status brain-sync; do
  if [ -e "$SKILLS_DIR/$skill" ]; then
    ok "Skill registered: $skill"
  else
    fail "Skill not registered: $skill" \
      "Symlink it: ln -s \$BRAIN_DIR/skills/$skill $SKILLS_DIR/$skill"
  fi
done

echo ""

# ── 7. Configuration placeholders ────────────────────────────────────────────

if [ -n "$BRAIN_DIR" ] && [ -f "$BRAIN_DIR/config.yml" ]; then
  if grep -q "Your Name" "$BRAIN_DIR/config.yml" 2>/dev/null; then
    warn "config.yml still has default owner.name (\"Your Name\")" \
      "Edit config.yml and fill in owner.name, role, org, domain, timezone"
  else
    ok "config.yml owner.name has been personalised"
  fi
fi

if [ -n "$BRAIN_DIR" ] && [ -f "$BRAIN_DIR/CLAUDE.md" ]; then
  if grep -q "\[YOUR_NAME\]" "$BRAIN_DIR/CLAUDE.md" 2>/dev/null; then
    warn "CLAUDE.md Identity section still has [YOUR_NAME] placeholder" \
      "Edit the ## Identity section in CLAUDE.md"
  else
    ok "CLAUDE.md Identity section has been filled in"
  fi
fi

echo ""

# ── Summary ───────────────────────────────────────────────────────────────────

TOTAL=$((PASS + FAIL + WARN))
echo "─────────────────────────────────────────"
echo -e "${GREEN}${PASS} passed${RESET}  ${RED}${FAIL} failed${RESET}  ${YELLOW}${WARN} warnings${RESET}  (${TOTAL} checks)"

if [ "$FAIL" -gt 0 ]; then
  exit 1
else
  exit 0
fi
