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

# Patched MCP server
MCP_SERVER="${BRAIN_DIR}/bin/mcp-server-filesystem/index.js"
if [ -z "$BRAIN_DIR" ]; then
  warn "Skipping mcp-server-filesystem check (BRAIN_DIR not set)"
elif [ ! -f "$MCP_SERVER" ]; then
  fail "Patched MCP server not found at bin/mcp-server-filesystem/index.js" \
    "Re-clone or re-run install.sh; the patched server must be committed to the brain repo"
else
  ok "Patched mcp-server-filesystem/index.js exists"
fi

for script in ai-statusline.sh ai-statusline-brain.sh ai-statusline-calendar.sh \
              agy-statusline.sh agy-statusline.py; do
  path="${BRAIN_DIR}/bin/${script}"
  if [ -z "$BRAIN_DIR" ]; then
    warn "Skipping $script check (BRAIN_DIR not set)"
  elif [ ! -f "$path" ]; then
    fail "$script not found at $path" \
      "Re-clone the brain template or copy bin/$script from the repo"
  elif [[ "$script" == *.sh ]] && [ ! -x "$path" ]; then
    fail "$script exists but is not executable" \
      "Run: chmod +x $path"
  else
    ok "$script exists"
  fi
done
for script in brain-start.sh brain-stop.sh brain-end.sh \
              gemini-brain-start.sh gemini-brain-post.sh gemini-brain-end.sh; do
  path="${BRAIN_DIR}/hooks/${script}"
  if [ -z "$BRAIN_DIR" ]; then
    warn "Skipping $script check (BRAIN_DIR not set)"
  elif [ ! -f "$path" ]; then
    fail "$script not found at $path" \
      "Re-clone the brain template or copy hooks/$script from the repo"
  elif [ ! -x "$path" ]; then
    fail "$script exists but is not executable" \
      "Run: chmod +x $path"
  else
    ok "$script exists"
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

  if json_has "$SETTINGS" "ONEDRIVE_DIR"; then
    ok "ONEDRIVE_DIR env var present in settings.json"
  else
    warn "ONEDRIVE_DIR not found in settings.json env section" \
      "Run install.sh to detect and set it (required for OneDrive MCP)"
  fi

  if json_has "$SETTINGS" "SessionStart"; then
    ok "SessionStart hook configured"
  else
    fail "SessionStart hook missing from settings.json" \
      "Run install.sh to register brain-start.sh"
  fi

  if json_has "$SETTINGS" "brain-stop.sh"; then
    ok "Stop hook configured (brain-stop.sh)"
  else
    fail "Stop hook missing from settings.json" \
      "Run install.sh to register brain-stop.sh"
  fi

  if json_has "$SETTINGS" "SessionEnd"; then
    ok "SessionEnd hook configured"
  else
    fail "SessionEnd hook missing from settings.json" \
      "Run install.sh to register brain-end.sh"
  fi

  if json_has "$SETTINGS" "ai-statusline.sh"; then
    ok "statusLine configured (ai-statusline.sh)"
  else
    fail "statusLine not configured in settings.json" \
      "Run install.sh to configure ai-statusline.sh"
  fi
fi

echo ""

# ── 4b. Claude Code MCP servers (CLI) ────────────────────────────────────────
# brain uses bin/brain-mcp/index.js (unified FS + wiki query tools + usage logging).
# onedrive uses bin/mcp-server-filesystem/index.js (patched upstream FS server).
# Each check verifies: (a) registered, (b) using the correct binary for that server.

CLAUDE_JSON="$HOME/.claude.json"

_check_mcp_server() {
  local name="$1" var_name="$2" var_val="$3" expected_binary="${4:-mcp-server-filesystem}"
  if [ -f "$CLAUDE_JSON" ] && grep -q "$expected_binary" "$CLAUDE_JSON"; then
    # Correct local server in use.
    # If command uses env var, verify the var is currently set and resolves correctly.
    if grep -qF "\$${var_name}" "$CLAUDE_JSON"; then
      if [ -n "$var_val" ] && [ -d "$var_val" ]; then
        ok "${name} MCP uses correct local server (\$${var_name} set, resolves to $(readlink -f "$var_val" 2>/dev/null || echo "$var_val"))"
      else
        fail "${name} MCP uses \$${var_name} env var but ${var_name} is unset or invalid" \
          "Run install.sh to set ${var_name} and re-register the MCP"
      fi
    else
      ok "${name} MCP uses correct local server (hardcoded path)"
    fi
  elif [ -f "$CLAUDE_JSON" ]; then
    fail "${name} MCP not using expected server binary ($expected_binary)" \
      "Re-register: claude mcp remove $(echo "$name" | tr '[:upper:]' '[:lower:]') && run install.sh"
  fi
}

if command -v claude &>/dev/null; then
  if claude mcp list 2>/dev/null | grep -q "^brain:"; then
    ok "Brain MCP registered (claude mcp list)"
    _check_mcp_server "Brain" "BRAIN_DIR" "$BRAIN_DIR" "brain-mcp/index.js"
  else
    fail "Brain MCP not registered with Claude Code CLI" \
      "Run install.sh to register it"
  fi

  if claude mcp list 2>/dev/null | grep -q "^onedrive:"; then
    ok "OneDrive MCP registered (claude mcp list)"
    _check_mcp_server "OneDrive" "ONEDRIVE_DIR" "$ONEDRIVE_DIR" "mcp-server-filesystem"
  else
    fail "OneDrive MCP not registered with Claude Code CLI" \
      "Run install.sh to register it"
  fi
else
  warn "claude CLI not found — skipping MCP registration checks"
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
      "Run install.sh — it symlinks ~/.claude/CLAUDE.md to brain/claude-global.md"
  fi
fi

echo ""

# ── 6. Skills ────────────────────────────────────────────────────────────────

SKILLS_DIR="$HOME/.claude/skills"
for skill in brain-cycle brain-dream brain-ingest brain-status brain-sync; do
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

# ── 8. Gemini CLI & Antigravity CLI ──────────────────────────────────────────

GEMINI_SETTINGS="$HOME/.gemini/settings.json"
AGY_MCP_CONFIG="$HOME/.gemini/config/mcp_config.json"
AGY_HOOKS_CONFIG="$HOME/.gemini/config/hooks.json"
GEMINI_MD="$HOME/.gemini/GEMINI.md"
GEMINI_SKILLS="$HOME/.gemini/skills"

if command -v gemini &>/dev/null || command -v agy &>/dev/null; then
  ok "Gemini/Antigravity CLI is installed"

  # Check settings / mcp_config for brain MCP
  mcp_ok=0
  if [ -f "$GEMINI_SETTINGS" ] && json_has "$GEMINI_SETTINGS" '"brain"'; then
    mcp_ok=1
  fi
  if [ -f "$AGY_MCP_CONFIG" ] && json_has "$AGY_MCP_CONFIG" '"brain"'; then
    mcp_ok=1
  fi

  if [ $mcp_ok -eq 1 ]; then
    ok "Brain MCP server configured (Gemini/Antigravity)"
    # Verify it uses brain-mcp/index.js (unified server with logging + wiki query tools)
    gemini_uses_brain_mcp=0
    if [ -f "$GEMINI_SETTINGS" ] && json_has "$GEMINI_SETTINGS" 'brain-mcp/index.js'; then
      gemini_uses_brain_mcp=1
    fi
    if [ -f "$AGY_MCP_CONFIG" ] && json_has "$AGY_MCP_CONFIG" 'brain-mcp/index.js'; then
      gemini_uses_brain_mcp=1
    fi
    if [ $gemini_uses_brain_mcp -eq 1 ]; then
      ok "Gemini brain MCP uses brain-mcp server (logging + wiki query tools)"
    else
      fail "Gemini brain MCP not using brain-mcp server (may still use mcp-server-filesystem or npx)" \
        "Run install.sh to update ~/.gemini/settings.json and mcp_config.json"
    fi
  else
    fail "Brain MCP server not configured for Gemini/Antigravity" \
      "Run install.sh to configure it"
  fi

  # Check hooks (PreInvocation start + PostInvocation reminder + Stop end)
  AGY_HOOKS_FILE=""
  [ -f "$AGY_HOOKS_CONFIG" ] && AGY_HOOKS_FILE="$AGY_HOOKS_CONFIG"
  [ -z "$AGY_HOOKS_FILE" ] && [ -f "$GEMINI_SETTINGS" ] && AGY_HOOKS_FILE="$GEMINI_SETTINGS"

  if [ -n "$AGY_HOOKS_FILE" ] && json_has "$AGY_HOOKS_FILE" "gemini-brain-start.sh"; then
    ok "PreInvocation (startup) hook configured"
  else
    fail "PreInvocation startup hook not configured" \
      "Run install.sh to configure gemini-brain-start.sh"
  fi

  if [ -n "$AGY_HOOKS_FILE" ] && json_has "$AGY_HOOKS_FILE" "gemini-brain-post.sh"; then
    ok "PostInvocation (capture reminder) hook configured"
  else
    fail "PostInvocation capture reminder hook not configured" \
      "Run install.sh to configure gemini-brain-post.sh"
  fi

  if [ -n "$AGY_HOOKS_FILE" ] && json_has "$AGY_HOOKS_FILE" "gemini-brain-end.sh"; then
    ok "Stop (session end) hook configured"
  else
    fail "Stop session end hook not configured" \
      "Run install.sh to configure gemini-brain-end.sh"
  fi

  # Check agy antigravity statusLine
  AGY_CLI_SETTINGS="$HOME/.gemini/antigravity-cli/settings.json"
  if [ -f "$AGY_CLI_SETTINGS" ] && json_has "$AGY_CLI_SETTINGS" "agy-statusline.sh"; then
    ok "agy statusLine configured (agy-statusline.sh)"
  else
    fail "agy statusLine not configured" \
      "Run install.sh to configure ~/.gemini/antigravity-cli/settings.json"
  fi

  # Check global GEMINI.md
  if [ -L "$GEMINI_MD" ]; then
    ok "Global GEMINI.md symlink exists"
  else
    warn "Global GEMINI.md symlink missing" \
      "Run install.sh to symlink ~/.gemini/GEMINI.md to brain/gemini-global.md"
  fi

  # Check skills
  for skill in brain-cycle brain-dream brain-ingest brain-status brain-sync; do
    if [ -e "$GEMINI_SKILLS/$skill" ]; then
      ok "Gemini skill registered: $skill"
    else
      fail "Gemini skill not registered: $skill" \
        "Run install.sh to register skills"
    fi
  done
else
  warn "Gemini/Antigravity CLI not installed, skipping these checks"
fi

echo ""

# ── 9. Windows Claude Desktop (WSL only) ─────────────────────────────────────

if grep -qi microsoft /proc/version 2>/dev/null; then
  WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
  CLAUDE_DESKTOP_CONFIG="/mnt/c/Users/$WIN_USER/AppData/Roaming/Claude/claude_desktop_config.json"

  if [ -f "$CLAUDE_DESKTOP_CONFIG" ]; then
    ok "Windows Claude Desktop config found"

    if json_has "$CLAUDE_DESKTOP_CONFIG" '"brain"'; then
      ok "Brain MCP configured in Windows Claude Desktop"
    else
      fail "Brain MCP missing from Windows Claude Desktop config" \
        "Run install.sh to add it"
    fi

    if json_has "$CLAUDE_DESKTOP_CONFIG" '"onedrive"'; then
      ok "OneDrive MCP configured in Windows Claude Desktop"
    else
      fail "OneDrive MCP missing from Windows Claude Desktop config" \
        "Run install.sh to add it"
    fi
  else
    warn "Windows Claude Desktop config not found (app not installed?)" \
      "Expected: $CLAUDE_DESKTOP_CONFIG"
  fi
else
  warn "Not running on WSL — skipping Windows Claude Desktop checks"
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
