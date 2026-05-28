#!/bin/bash
# brain/bin/install.sh
# Run once per machine after cloning the brain repo.
# Usage: bash ~/brain/bin/install.sh
set -e

BRAIN_DIR="${BRAIN_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

echo "Installing brain from $BRAIN_DIR"

# --- 0. Preflight: check Identity is configured ---
if grep -q '\[YOUR_NAME\]' "$BRAIN_DIR/CLAUDE.md" 2>/dev/null; then
  echo ""
  echo "  WARNING: CLAUDE.md still contains placeholder values."
  echo "  Edit the Identity section in CLAUDE.md and config.yml before first use."
  echo "  Install will continue, but the brain will not work correctly until configured."
  echo ""
fi

# --- 1. Claude Code user settings (env + hooks) ---
SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$SETTINGS")"
if [[ ! -f "$SETTINGS" ]]; then
  echo '{}' > "$SETTINGS"
fi

python3 - <<PYEOF
import json, os

settings_path = os.path.expanduser("~/.claude/settings.json")
brain_dir = "$BRAIN_DIR"

try:
    with open(settings_path) as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

settings.setdefault("env", {})
if settings["env"].get("BRAIN_DIR") == brain_dir:
    print("  BRAIN_DIR already set in settings.json, skipping.")
else:
    settings["env"]["BRAIN_DIR"] = brain_dir
    print(f"  Set BRAIN_DIR={brain_dir} in ~/.claude/settings.json")

def has_hook(hooks_list, cmd):
    return any(h.get("command") == cmd for entry in hooks_list for h in entry.get("hooks", []))

settings.setdefault("hooks", {})
for event, script in [("SessionStart", "brain-start.sh"), ("SessionEnd", "brain-end.sh")]:
    cmd = f"bash \$BRAIN_DIR/bin/{script}"
    settings["hooks"].setdefault(event, [])
    if has_hook(settings["hooks"][event], cmd):
        print(f"  {event} brain hook already registered, skipping.")
    else:
        settings["hooks"][event].append({"hooks": [{"command": cmd, "type": "command"}]})
        print(f"  Registered {event} hook -> bin/{script}")

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PYEOF

# --- 2. Claude Code MCP server ---
if command -v claude &>/dev/null; then
  if claude mcp list 2>/dev/null | grep -q "^brain:"; then
    echo ""
    echo "Brain MCP server already registered with Claude Code."
  else
    echo ""
    claude mcp add brain --scope user -- sh -c 'npx -y @modelcontextprotocol/server-filesystem "$BRAIN_DIR"'
    echo "Brain MCP server registered with Claude Code."
  fi
else
  echo ""
  echo "claude CLI not found -- register MCP server manually:"
  echo "  claude mcp add brain --scope user -- sh -c 'npx -y @modelcontextprotocol/server-filesystem \"\$BRAIN_DIR\"'"
fi

# --- 3. Claude Code skills symlinks ---
SKILLS_DIR="$HOME/.claude/skills"
mkdir -p "$SKILLS_DIR"
for skill_dir in "$BRAIN_DIR/skills"/*/; do
  skill="$(basename "$skill_dir")"
  if [[ -L "$SKILLS_DIR/$skill" ]]; then
    echo "Skill $skill already linked (Claude Code)."
  else
    ln -s "$skill_dir" "$SKILLS_DIR/$skill"
    echo "Linked skill: $skill (Claude Code)"
  fi
done

# --- 4. Global CLAUDE.md ---
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
if [[ ! -f "$CLAUDE_MD" ]]; then
  cat > "$CLAUDE_MD" <<EOF
# Global Claude Code Configuration

@~/brain/prompt.md

## Brain System

The brain-session skill is always active. Apply it in every session without being asked.
/brain-status, /brain-sync, and /brain-dream are available as on-demand commands.

Brain repo: \$BRAIN_DIR ($BRAIN_DIR)
Brain MCP server: brain (filesystem access to the brain repo)
EOF
  echo "Created $CLAUDE_MD"
else
  echo "$CLAUDE_MD already exists, skipping."
  if ! grep -q '@~/brain/prompt.md' "$CLAUDE_MD"; then
    tmpfile=$(mktemp)
    { head -1 "$CLAUDE_MD"; printf '\n@~/brain/prompt.md\n'; tail -n +2 "$CLAUDE_MD"; } > "$tmpfile"
    mv "$tmpfile" "$CLAUDE_MD"
    echo "Added prompt.md import to $CLAUDE_MD"
  fi
fi

# --- 5. Shell profiles ---
echo ""
echo "Configuring shell profiles..."

append_if_missing() {
  local file="$1" marker="$2" line="$3"
  if [[ -f "$file" ]] && grep -qF "$marker" "$file"; then
    echo "  $file: BRAIN_DIR already set, skipping."
  elif [[ -f "$file" ]]; then
    printf '\n# brain\n%s\n' "$line" >> "$file"
    echo "  $file: added BRAIN_DIR."
  fi
}

append_if_missing "$HOME/.bashrc"       "BRAIN_DIR" "export BRAIN_DIR=\"$BRAIN_DIR\""
append_if_missing "$HOME/.bash_profile" "BRAIN_DIR" "export BRAIN_DIR=\"$BRAIN_DIR\""
append_if_missing "$HOME/.zshrc"        "BRAIN_DIR" "export BRAIN_DIR=\"$BRAIN_DIR\""
append_if_missing "$HOME/.zshenv"       "BRAIN_DIR" "export BRAIN_DIR=\"$BRAIN_DIR\""

# --- 6. Gemini CLI setup (optional) ---
echo ""
if command -v gemini &>/dev/null; then
  mkdir -p "$HOME/.gemini"

  python3 - <<PYEOF
import json, os

settings_path = os.path.expanduser("~/.gemini/settings.json")
brain_dir = "$BRAIN_DIR"

try:
    with open(settings_path) as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

settings.setdefault("mcpServers", {})
settings["mcpServers"]["brain"] = {
    "command": "bash",
    "args": ["-c", 'npx -y @modelcontextprotocol/server-filesystem "\$BRAIN_DIR"']
}
settings.setdefault("env", {})
settings["env"]["BRAIN_DIR"] = brain_dir
settings["hooks"] = {
    "SessionStart": [{"hooks": [{"name": "brain-sync-start", "type": "command",
        "command": "bash \$BRAIN_DIR/bin/gemini-brain-start.sh",
        "description": "Pull latest brain repo", "timeout": 30000}]}],
    "SessionEnd": [{"hooks": [{"name": "brain-sync-end", "type": "command",
        "command": "bash \$BRAIN_DIR/bin/gemini-brain-end.sh",
        "description": "Commit pending raw/ captures", "timeout": 60000}]}]
}

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
print("Updated ~/.gemini/settings.json with brain MCP, env vars, and hooks.")
PYEOF

  GEMINI_MD="$HOME/.gemini/GEMINI.md"
  if [[ ! -f "$GEMINI_MD" ]]; then
    cat > "$GEMINI_MD" <<EOF
@../brain/prompt.md

# Brain System

The brain-session skill is always active. Apply it in every session without being asked.
/brain-status, /brain-sync, and /brain-dream are available as on-demand commands.

Brain repo: \$BRAIN_DIR ($BRAIN_DIR)
Brain MCP server: brain (filesystem access to the brain repo)
EOF
    echo "Created $GEMINI_MD"
  else
    echo "$GEMINI_MD already exists, skipping."
  fi

  for skill_dir in "$BRAIN_DIR/skills"/*/; do
    skill="$(basename "$skill_dir")"
    if [[ -d "$HOME/.gemini/skills/$skill" ]]; then
      echo "Skill $skill already linked (Gemini CLI)."
    else
      echo "Y" | gemini skills link "$skill_dir" 2>/dev/null && echo "Linked skill: $skill (Gemini CLI)"
    fi
  done
else
  echo "gemini CLI not found -- skipping Gemini CLI setup (re-run install.sh if you add it later)."
fi

echo ""
echo "Install complete. Run 'bash $BRAIN_DIR/bin/setup-check.sh' to verify."
