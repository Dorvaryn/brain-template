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

# Env vars
settings.setdefault("env", {})
if settings["env"].get("BRAIN_DIR") == brain_dir:
    print("  BRAIN_DIR already set in settings.json, skipping.")
else:
    settings["env"]["BRAIN_DIR"] = brain_dir
    print(f"  Set BRAIN_DIR={brain_dir} in ~/.claude/settings.json")

# Session hooks
def has_hook(hooks_list, cmd):
    return any(h.get("command") == cmd for entry in hooks_list for h in entry.get("hooks", []))

settings.setdefault("hooks", {})
for event, script in [
    ("SessionStart", "brain-start.sh"),
    ("Stop",         "brain-stop.sh"),
    ("SessionEnd",   "brain-end.sh"),
]:
    # brain-end.sh must use setsid so it survives Claude Code's process group teardown
    prefix = "setsid bash" if script == "brain-end.sh" else "bash"
    cmd = f"{prefix} \$BRAIN_DIR/bin/{script}"
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

# --- 4. Global CLAUDE.md (symlink -> brain/claude-global.md) ---
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
TARGET="$BRAIN_DIR/claude-global.md"
if [[ -L "$CLAUDE_MD" && "$(readlink "$CLAUDE_MD")" == "$TARGET" ]]; then
  echo "$CLAUDE_MD already symlinked to claude-global.md, skipping."
elif [[ -e "$CLAUDE_MD" || -L "$CLAUDE_MD" ]]; then
  mv "$CLAUDE_MD" "${CLAUDE_MD}.bak"
  echo "Backed up existing $CLAUDE_MD to ${CLAUDE_MD}.bak"
  ln -s "$TARGET" "$CLAUDE_MD"
  echo "Created symlink: $CLAUDE_MD -> $TARGET"
else
  mkdir -p "$(dirname "$CLAUDE_MD")"
  ln -s "$TARGET" "$CLAUDE_MD"
  echo "Created symlink: $CLAUDE_MD -> $TARGET"
fi

# --- 5. Gemini / Antigravity CLI setup ---
echo ""
if command -v gemini &>/dev/null || command -v agy &>/dev/null; then
  mkdir -p "$HOME/.gemini"
  mkdir -p "$HOME/.gemini/config"

  # Update ~/.gemini/settings.json, ~/.gemini/config/mcp_config.json and ~/.gemini/config/hooks.json
  python3 - <<PYEOF
import json, os

settings_path = os.path.expanduser("~/.gemini/settings.json")
mcp_config_path = os.path.expanduser("~/.gemini/config/mcp_config.json")
hooks_config_path = os.path.expanduser("~/.gemini/config/hooks.json")
brain_dir = "$BRAIN_DIR"

# 1. Update ~/.gemini/settings.json (legacy Gemini settings)
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
    "PreInvocation": [{
        "hooks": [{
            "name": "brain-sync-start",
            "type": "command",
            "command": "bash \$BRAIN_DIR/bin/gemini-brain-start.sh",
            "description": "Pull latest brain repo and show sync status",
            "timeout": 30000
        }]
    }],
    "PostInvocation": [{
        "hooks": [{
            "name": "brain-capture-reminder",
            "type": "command",
            "command": "bash \$BRAIN_DIR/bin/gemini-brain-post.sh",
            "description": "Remind agent to capture decisions",
            "timeout": 5000
        }]
    }],
    "Stop": [{
        "hooks": [{
            "name": "brain-sync-end",
            "type": "command",
            "command": "setsid bash \$BRAIN_DIR/bin/gemini-brain-end.sh",
            "description": "Commit any pending raw/ captures to brain repo",
            "timeout": 60000
        }]
    }]
}

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
print("Updated ~/.gemini/settings.json with brain MCP, env vars, and hooks.")

# 2. Update ~/.gemini/config/mcp_config.json (Antigravity custom MCP config)
try:
    with open(mcp_config_path) as f:
        mcp_config = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    mcp_config = {}

mcp_config.setdefault("mcpServers", {})
mcp_config["mcpServers"]["brain"] = {
    "command": "bash",
    "args": ["-c", 'npx -y @modelcontextprotocol/server-filesystem "\$BRAIN_DIR"']
}

with open(mcp_config_path, "w") as f:
    json.dump(mcp_config, f, indent=2)
    f.write("\n")
print("Updated ~/.gemini/config/mcp_config.json with brain MCP server.")

# 3. Update ~/.gemini/config/hooks.json (Antigravity hooks config)
try:
    with open(hooks_config_path) as f:
        hooks_config = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    hooks_config = {}

hooks_config["hooks"] = {
    "PreInvocation": [{
        "hooks": [{
            "name": "brain-sync-start",
            "type": "command",
            "command": "bash \$BRAIN_DIR/bin/gemini-brain-start.sh",
            "description": "Pull latest brain repo and show sync status",
            "timeout": 30000
        }]
    }],
    "PostInvocation": [{
        "hooks": [{
            "name": "brain-capture-reminder",
            "type": "command",
            "command": "bash \$BRAIN_DIR/bin/gemini-brain-post.sh",
            "description": "Remind agent to capture decisions",
            "timeout": 5000
        }]
    }],
    "Stop": [{
        "hooks": [{
            "name": "brain-sync-end",
            "type": "command",
            "command": "setsid bash \$BRAIN_DIR/bin/gemini-brain-end.sh",
            "description": "Commit any pending raw/ captures to brain repo",
            "timeout": 60000
        }]
    }]
}

with open(hooks_config_path, "w") as f:
    json.dump(hooks_config, f, indent=2)
    f.write("\n")
print("Updated ~/.gemini/config/hooks.json with PreInvocation, PostInvocation, and Stop hooks.")
PYEOF

  # Global GEMINI.md (symlink -> brain/gemini-global.md)
  GEMINI_MD="$HOME/.gemini/GEMINI.md"
  GEMINI_TARGET="$BRAIN_DIR/gemini-global.md"
  if [[ -L "$GEMINI_MD" && "$(readlink "$GEMINI_MD")" == "$GEMINI_TARGET" ]]; then
    echo "$GEMINI_MD already symlinked to gemini-global.md, skipping."
  elif [[ -e "$GEMINI_MD" || -L "$GEMINI_MD" ]]; then
    mv "$GEMINI_MD" "${GEMINI_MD}.bak"
    echo "Backed up existing $GEMINI_MD to ${GEMINI_MD}.bak"
    ln -s "$GEMINI_TARGET" "$GEMINI_MD"
    echo "Created symlink: $GEMINI_MD -> $GEMINI_TARGET"
  else
    ln -s "$GEMINI_TARGET" "$GEMINI_MD"
    echo "Created symlink: $GEMINI_MD -> $GEMINI_TARGET"
  fi

  # Link brain skills to Gemini/Antigravity CLI (using CLI-agnostic symlinks)
  mkdir -p "$HOME/.gemini/skills"
  for skill_dir in "$BRAIN_DIR/skills"/*/; do
    skill="$(basename "$skill_dir")"
    if [[ -L "$HOME/.gemini/skills/$skill" || -d "$HOME/.gemini/skills/$skill" ]]; then
      echo "Skill $skill already linked (Gemini/Antigravity)."
    else
      ln -s "$skill_dir" "$HOME/.gemini/skills/$skill"
      echo "Linked skill: $skill (Gemini/Antigravity)"
    fi
  done
else
  echo "Neither gemini nor agy CLI was found -- skipping Gemini/Antigravity setup."
  echo "Install Gemini/Antigravity CLI and re-run install.sh."
fi

# --- 6. Windows Claude desktop app (WSL only) ---
echo ""
if grep -qi microsoft /proc/version 2>/dev/null; then
  WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
  if [[ -n "$WIN_USER" ]]; then
    CLAUDE_DESKTOP_CONFIG="/mnt/c/Users/$WIN_USER/AppData/Roaming/Claude/claude_desktop_config.json"
    if [[ -f "$CLAUDE_DESKTOP_CONFIG" ]]; then
      python3 - <<PYEOF
import json

config_path = "$CLAUDE_DESKTOP_CONFIG"
brain_dir = "$BRAIN_DIR"

try:
    with open(config_path) as f:
        config = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    config = {}

config.setdefault("mcpServers", {})
if "brain" in config["mcpServers"]:
    print("Brain MCP server already configured in Windows Claude desktop app.")
else:
    config["mcpServers"]["brain"] = {
        "command": "wsl",
        "args": ["bash", "-c", 'npx -y @modelcontextprotocol/server-filesystem "$BRAIN_DIR"']
    }
    with open(config_path, "w") as f:
        json.dump(config, f, indent=2)
        f.write("\n")
    print("Brain MCP server added to Windows Claude desktop app.")
PYEOF
    else
      echo "Windows Claude desktop config not found -- is the app installed?"
      echo "  Expected: $CLAUDE_DESKTOP_CONFIG"
    fi
  else
    echo "Could not detect Windows username -- skipping Windows Claude desktop app setup."
  fi
else
  echo "Not running on WSL -- skipping Windows Claude desktop app setup."
fi

# --- 7. Shell profiles ---
echo ""
echo "Configuring shell profiles..."

append_if_missing() {
  local file="$1" marker="$2" line="$3" comment="${4:-brain}"
  if [[ -f "$file" ]] && grep -qF "$marker" "$file"; then
    echo "  $file: $marker already set, skipping."
  elif [[ -f "$file" ]]; then
    printf '\n# %s\n%s\n' "$comment" "$line" >> "$file"
    echo "  $file: added $marker."
  fi
}

# bash
append_if_missing "$HOME/.bashrc"       "BRAIN_DIR" "export BRAIN_DIR=\"$BRAIN_DIR\""
append_if_missing "$HOME/.bash_profile" "BRAIN_DIR" "export BRAIN_DIR=\"$BRAIN_DIR\""

# zsh
append_if_missing "$HOME/.zshrc"  "BRAIN_DIR" "export BRAIN_DIR=\"$BRAIN_DIR\""
append_if_missing "$HOME/.zshenv" "BRAIN_DIR" "export BRAIN_DIR=\"$BRAIN_DIR\""

# nushell
NU_ENV="$HOME/.config/nushell/env.nu"
if [[ -f "$NU_ENV" ]] && grep -q "BRAIN_DIR" "$NU_ENV"; then
  echo "  $NU_ENV: BRAIN_DIR already set, skipping."
elif [[ -f "$NU_ENV" ]]; then
  printf '\n# brain\n$env.BRAIN_DIR = "%s"\n' "$BRAIN_DIR" >> "$NU_ENV"
  echo "  $NU_ENV: added BRAIN_DIR."
fi

echo ""
echo "---"
echo "brain-template sync setup (optional)"
echo "  The brain-sync-template skill needs to know where brain-template is checked out."
read -r -p "  Path to brain-template repo (leave blank to skip): " BRAIN_TEMPLATE_DIR_INPUT

if [[ -n "$BRAIN_TEMPLATE_DIR_INPUT" ]]; then
  # Expand tilde manually (double-quoting prevents shell tilde expansion)
  BRAIN_TEMPLATE_DIR_EXPANDED="${BRAIN_TEMPLATE_DIR_INPUT/#\~/$HOME}"
  BRAIN_TEMPLATE_DIR_RESOLVED=$(cd "$BRAIN_TEMPLATE_DIR_EXPANDED" 2>/dev/null && pwd) || true
  # Use safe.directory=* to handle WSL /mnt/c/ ownership mismatches
  if [[ -z "$BRAIN_TEMPLATE_DIR_RESOLVED" ]] || ! git -C "$BRAIN_TEMPLATE_DIR_RESOLVED" -c safe.directory='*' rev-parse HEAD &>/dev/null; then
    echo "  Warning: '$BRAIN_TEMPLATE_DIR_INPUT' is not a valid git repo — skipping BRAIN_TEMPLATE_DIR setup."
    echo "  Re-run install.sh after cloning brain-template, or set BRAIN_TEMPLATE_DIR manually."
  else
    # Claude Code settings.json
    python3 - <<PYEOF
import json, os

settings_path = os.path.expanduser("~/.claude/settings.json")
val = "$BRAIN_TEMPLATE_DIR_RESOLVED"

try:
    with open(settings_path) as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

settings.setdefault("env", {})
if settings["env"].get("BRAIN_TEMPLATE_DIR") == val:
    print("  BRAIN_TEMPLATE_DIR already set in settings.json, skipping.")
else:
    settings["env"]["BRAIN_TEMPLATE_DIR"] = val
    with open(settings_path, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    print(f"  Set BRAIN_TEMPLATE_DIR={val} in ~/.claude/settings.json")
PYEOF

    # Shell profiles
    append_if_missing "$HOME/.bashrc"       "BRAIN_TEMPLATE_DIR" "export BRAIN_TEMPLATE_DIR=\"$BRAIN_TEMPLATE_DIR_RESOLVED\"" "brain-template"
    append_if_missing "$HOME/.bash_profile" "BRAIN_TEMPLATE_DIR" "export BRAIN_TEMPLATE_DIR=\"$BRAIN_TEMPLATE_DIR_RESOLVED\"" "brain-template"
    append_if_missing "$HOME/.zshrc"        "BRAIN_TEMPLATE_DIR" "export BRAIN_TEMPLATE_DIR=\"$BRAIN_TEMPLATE_DIR_RESOLVED\"" "brain-template"
    append_if_missing "$HOME/.zshenv"       "BRAIN_TEMPLATE_DIR" "export BRAIN_TEMPLATE_DIR=\"$BRAIN_TEMPLATE_DIR_RESOLVED\"" "brain-template"

    NU_ENV="$HOME/.config/nushell/env.nu"
    if [[ -f "$NU_ENV" ]] && grep -q "BRAIN_TEMPLATE_DIR" "$NU_ENV"; then
      echo "  $NU_ENV: BRAIN_TEMPLATE_DIR already set, skipping."
    elif [[ -f "$NU_ENV" ]]; then
      printf '\n# brain-template\n$env.BRAIN_TEMPLATE_DIR = "%s"\n' "$BRAIN_TEMPLATE_DIR_RESOLVED" >> "$NU_ENV"
      echo "  $NU_ENV: added BRAIN_TEMPLATE_DIR."
    fi

    echo "  BRAIN_TEMPLATE_DIR=$BRAIN_TEMPLATE_DIR_RESOLVED configured."
    echo "  Run /brain-sync-template to sync infrastructure files to the template."
  fi
else
  echo "  Skipped. Set BRAIN_TEMPLATE_DIR manually or re-run install.sh when ready."
fi

echo ""
echo "Install complete. Run 'bash $BRAIN_DIR/bin/setup-check.sh' to verify."
