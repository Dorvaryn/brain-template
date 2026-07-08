#!/bin/bash
# brain/bin/install.sh
# Run once per machine after cloning the brain repo.
# Usage: bash ~/brain/bin/install.sh
set -e

BRAIN_DIR="${BRAIN_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

echo "Installing brain from $BRAIN_DIR"

# Detect optional dependencies
if command -v starship &>/dev/null; then
  HAVE_STARSHIP=true
else
  HAVE_STARSHIP=false
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

# StatusLine (optional — requires Starship; https://starship.rs)
have_starship = "$HAVE_STARSHIP" == "true"
if have_starship:
    target_statusline = {"type": "command", "command": "bash \$BRAIN_DIR/bin/ai-statusline.sh"}
    if settings.get("statusLine", {}).get("command") == target_statusline["command"]:
        print("  statusLine already configured, skipping.")
    else:
        settings["statusLine"] = target_statusline
        print("  Configured statusLine -> ai-statusline.sh")
else:
    print("  statusLine skipped (Starship not found — install starship and re-run to enable).")

# Session hooks
def has_hook(hooks_list, cmd):
    return any(h.get("command") == cmd for entry in hooks_list for h in entry.get("hooks", []))

settings.setdefault("hooks", {})
for event, script in [
    ("SessionStart", "brain-start.sh"),
    ("Stop",         "brain-stop.sh"),
    ("SessionEnd",   "brain-end.sh"),
]:
    # Scripts handle their own background detachment via nohup+disown; plain bash for all platforms
    cmd = f"bash \$BRAIN_DIR/hooks/{script}"
    alt_cmd = f"setsid bash \$BRAIN_DIR/hooks/{script}"  # clean up stale setsid variant
    settings["hooks"].setdefault(event, [])
    # Remove stale wrong-platform variant if present
    for _entry in settings["hooks"][event]:
        _entry["hooks"] = [h for h in _entry.get("hooks", []) if h.get("command") != alt_cmd]
    settings["hooks"][event] = [e for e in settings["hooks"][event] if e.get("hooks")]
    if has_hook(settings["hooks"][event], cmd):
        print(f"  {event} brain hook already registered, skipping.")
    else:
        settings["hooks"][event].append({"hooks": [{"command": cmd, "type": "command"}]})
        print(f"  Registered {event} hook -> hooks/{script}")

# Permissions for all brain MCP tools (global allow — works in any project directory)
BRAIN_MCP_TOOLS = [
    "mcp__brain__create_directory",
    "mcp__brain__directory_tree",
    "mcp__brain__edit_file",
    "mcp__brain__find_links",
    "mcp__brain__get_file_info",
    "mcp__brain__get_open_questions",
    "mcp__brain__get_summaries",
    "mcp__brain__list_allowed_directories",
    "mcp__brain__list_directory",
    "mcp__brain__list_directory_with_sizes",
    "mcp__brain__list_recent",
    "mcp__brain__list_wiki",
    "mcp__brain__move_file",
    "mcp__brain__read_file",
    "mcp__brain__read_media_file",
    "mcp__brain__read_multiple_files",
    "mcp__brain__read_text_file",
    "mcp__brain__search_files",
    "mcp__brain__search_frontmatter",
    "mcp__brain__search_wiki_content",
    "mcp__brain__get_outbound_links",
    "mcp__brain__write_file",
]
settings.setdefault("permissions", {}).setdefault("allow", [])
added = [t for t in BRAIN_MCP_TOOLS if t not in settings["permissions"]["allow"]]
if added:
    settings["permissions"]["allow"] = sorted(
        set(settings["permissions"]["allow"]) | set(BRAIN_MCP_TOOLS)
    )
    print(f"  Added {len(added)} brain MCP tool permission(s) to ~/.claude/settings.json")
else:
    print("  Brain MCP permissions already set in settings.json, skipping.")

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PYEOF

# --- 2b. Configure ONEDRIVE_DIR (machine-specific OneDrive root path) ---
# ONEDRIVE_DIR is the OneDrive root (e.g. "OneDrive - ATG Entertainment").
# Individual SharePoint sites are subfolders within it — configured in config.yml onedrive.sites[].path

# On reruns: skip if already configured to a valid path
EXISTING_ONEDRIVE=$(python3 -c "
import json, os
try:
    s = json.load(open(os.path.expanduser('~/.claude/settings.json')))
    print(s.get('env', {}).get('ONEDRIVE_DIR', ''))
except: print('')
" 2>/dev/null)

if [[ -n "$EXISTING_ONEDRIVE" && -d "$EXISTING_ONEDRIVE" ]]; then
  echo "  ONEDRIVE_DIR already configured: $EXISTING_ONEDRIVE (skipping)"
  ONEDRIVE_DIR="$EXISTING_ONEDRIVE"
else
  # Detect a candidate path for the work OneDrive root
  CANDIDATE=""
  if uname -r 2>/dev/null | grep -qi "microsoft\|wsl"; then
    WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r' || echo "$USER")
    WIN_HOME="/mnt/c/Users/$WIN_USER"
    for base in "$WIN_HOME"/OneDrive*; do
      if [[ -d "$base" ]] && echo "$base" | grep -qi "ATG\|Entertainment\|ambassador"; then
        CANDIDATE="$base"; break
      fi
    done
    CANDIDATE="${CANDIDATE:-$WIN_HOME/OneDrive - ATG Entertainment}"
  elif [[ "$(uname -s)" == "Darwin" ]]; then
    for base in "$HOME/Library/CloudStorage"/OneDrive* "$HOME"/OneDrive*; do
      if [[ -d "$base" ]] && echo "$base" | grep -qi "ATG\|Entertainment\|ambassador"; then
        CANDIDATE="$base"; break
      fi
    done
    CANDIDATE="${CANDIDATE:-$HOME/Library/CloudStorage/OneDrive - ATG Entertainment}"
  else
    CANDIDATE="$HOME/OneDrive - ATG Entertainment"
  fi

  echo ""
  echo "  OneDrive root detected: $CANDIDATE"
  read -r -p "  Press Enter to accept or type a different path: " ONEDRIVE_INPUT
  ONEDRIVE_DIR="${ONEDRIVE_INPUT:-$CANDIDATE}"
  # Expand tilde if user typed ~/...
  ONEDRIVE_DIR="${ONEDRIVE_DIR/#\~/$HOME}"

  python3 - <<PYEOF2
import json, os
settings_path = os.path.expanduser("~/.claude/settings.json")
onedrive_dir = "$ONEDRIVE_DIR"
try:
    with open(settings_path) as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}
settings.setdefault("env", {})
settings["env"]["ONEDRIVE_DIR"] = onedrive_dir
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
print(f"  Set ONEDRIVE_DIR={onedrive_dir} in ~/.claude/settings.json")
PYEOF2
fi

if [[ -d "$ONEDRIVE_DIR" ]]; then
  echo "  OneDrive root found at $ONEDRIVE_DIR"
  ONEDRIVE_AVAILABLE=true
else
  echo "  OneDrive root not found at $ONEDRIVE_DIR — sign in to OneDrive and sync first."
  ONEDRIVE_AVAILABLE=false
fi

# --- 2b. MCP server dependencies ---
MCP_SERVER_DIR="$BRAIN_DIR/bin/brain-mcp"
if [[ -d "$MCP_SERVER_DIR/node_modules" ]]; then
  echo "MCP server dependencies already installed, skipping."
else
  echo "Installing MCP server dependencies..."
  (cd "$MCP_SERVER_DIR" && npm install 2>&1 | tail -3)
  echo "MCP server dependencies installed."
fi

# --- 3. Claude Code MCP servers (brain + onedrive — separate for permission control) ---
if command -v claude &>/dev/null; then
  echo ""

  # 3a. Brain MCP — always registered, auto-allowed for all operations
  # Uses brain-mcp (bin/brain-mcp/) — unified server with FS + wiki query tools.
  BRAIN_MCP_CURRENT=$(claude mcp list 2>/dev/null | grep "^brain:" || echo "")
  if echo "$BRAIN_MCP_CURRENT" | grep -q "brain-mcp/index.js"; then
    echo "Brain MCP already registered with correct server, skipping."
  else
    if [[ -n "$BRAIN_MCP_CURRENT" ]]; then
      claude mcp remove brain
      echo "Removed stale brain MCP registration (was: $BRAIN_MCP_CURRENT)."
    fi
    claude mcp add brain --scope user \
      -- node "$BRAIN_DIR/bin/brain-mcp/index.js" "$BRAIN_DIR"
    echo "Brain MCP registered (mcp__brain__* — auto-allowed)."
  fi

  # 3b. OneDrive MCP — serves full OneDrive root; reads auto-allowed, writes require confirmation
  if claude mcp list 2>/dev/null | grep -q "^onedrive:"; then
    echo "OneDrive MCP already registered, skipping."
  elif [[ "$ONEDRIVE_AVAILABLE" == "true" ]]; then
    claude mcp add onedrive --scope user \
      -- node "$BRAIN_DIR/bin/mcp-server-filesystem/index.js" "$ONEDRIVE_DIR"
    echo "OneDrive MCP registered (mcp__onedrive__* — reads auto-allowed, writes require confirmation)."
  else
    echo "OneDrive MCP skipped — OneDrive root not available. Re-run install.sh after sign-in."
  fi
else
  echo ""
  echo "claude CLI not found -- register MCP servers manually:"
  echo "  claude mcp add brain --scope user -- node '$BRAIN_DIR/bin/brain-mcp/index.js' '$BRAIN_DIR'"
  echo "  claude mcp add onedrive --scope user -- node '$BRAIN_DIR/bin/mcp-server-filesystem/index.js' '$ONEDRIVE_DIR'"
fi

# --- 4. Claude Code skills symlinks ---
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

# --- 5. Global CLAUDE.md (symlink -> brain/claude-global.md) ---
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

# --- 6. Gemini / Antigravity CLI setup ---
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
# Script handles its own background detachment via nohup+disown; plain bash for all platforms
gemini_end_cmd = "bash \$BRAIN_DIR/hooks/gemini-brain-end.sh"

# 1. Update ~/.gemini/settings.json (legacy Gemini settings)
try:
    with open(settings_path) as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

settings.setdefault("mcpServers", {})
settings["mcpServers"]["brain"] = {
    "command": "node",
    "args": [f"{brain_dir}/bin/brain-mcp/index.js", brain_dir],
}
settings.setdefault("env", {})
settings["env"]["BRAIN_DIR"] = brain_dir
settings["env"].setdefault("GIT_SSH_COMMAND", "ssh.exe")

settings["hooks"] = {
    "PreInvocation": [{
        "hooks": [{
            "name": "brain-sync-start",
            "type": "command",
            "command": "bash \$BRAIN_DIR/hooks/gemini-brain-start.sh",
            "description": "Pull latest brain repo and show sync status",
            "timeout": 30000
        }]
    }],
    "PostInvocation": [{
        "hooks": [{
            "name": "brain-capture-reminder",
            "type": "command",
            "command": "bash \$BRAIN_DIR/hooks/gemini-brain-post.sh",
            "description": "Remind agent to capture decisions",
            "timeout": 5000
        }]
    }],
    "Stop": [{
        "hooks": [{
            "name": "brain-sync-end",
            "type": "command",
            "command": gemini_end_cmd,
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
    "command": "node",
    "args": [f"{brain_dir}/bin/brain-mcp/index.js", brain_dir],
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
            "command": "bash \$BRAIN_DIR/hooks/gemini-brain-start.sh",
            "description": "Pull latest brain repo and show sync status",
            "timeout": 30000
        }]
    }],
    "PostInvocation": [{
        "hooks": [{
            "name": "brain-capture-reminder",
            "type": "command",
            "command": "bash \$BRAIN_DIR/hooks/gemini-brain-post.sh",
            "description": "Remind agent to capture decisions",
            "timeout": 5000
        }]
    }],
    "Stop": [{
        "hooks": [{
            "name": "brain-sync-end",
            "type": "command",
            "command": gemini_end_cmd,
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

  # Update ~/.gemini/antigravity-cli/settings.json (agy statusLine + trustedWorkspaces)
  python3 - <<PYEOF
import json, os

agy_settings_path = os.path.expanduser("~/.gemini/antigravity-cli/settings.json")
brain_dir = "$BRAIN_DIR"

os.makedirs(os.path.dirname(agy_settings_path), exist_ok=True)
try:
    with open(agy_settings_path) as f:
        agy = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    agy = {}

# StatusLine (optional — requires Starship)
have_starship = "$HAVE_STARSHIP" == "true"
if have_starship:
    target_cmd = "bash \$BRAIN_DIR/bin/agy-statusline.sh"
    if agy.get("statusLine", {}).get("command") == target_cmd:
        print("  agy statusLine already configured, skipping.")
    else:
        agy["statusLine"] = {"type": "command", "command": target_cmd}
        print("  Configured agy statusLine -> agy-statusline.sh")
else:
    print("  agy statusLine skipped (Starship not found).")

# Trusted workspaces
agy.setdefault("trustedWorkspaces", [])
if brain_dir not in agy["trustedWorkspaces"]:
    agy["trustedWorkspaces"].append(brain_dir)
    print(f"  Added {brain_dir} to agy trustedWorkspaces.")
else:
    print("  agy trustedWorkspaces already includes brain dir, skipping.")

with open(agy_settings_path, "w") as f:
    json.dump(agy, f, indent=2)
    f.write("\n")
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

# --- 7. Windows Claude desktop app (WSL only) ---
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
onedrive_dir = "$ONEDRIVE_DIR"

try:
    with open(config_path) as f:
        config = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    config = {}

config.setdefault("mcpServers", {})
changed = False

if "brain" in config["mcpServers"]:
    print("Brain MCP already in Windows Claude Desktop config, skipping.")
else:
    config["mcpServers"]["brain"] = {
        "command": "wsl",
        "args": ["node", f"{brain_dir}/bin/brain-mcp/index.js", brain_dir],
    }
    changed = True
    print("Brain MCP added to Windows Claude Desktop config.")

if "onedrive" in config["mcpServers"]:
    print("OneDrive MCP already in Windows Claude Desktop config, skipping.")
elif onedrive_dir:
    config["mcpServers"]["onedrive"] = {
        "command": "wsl",
        "args": ["node", f"{brain_dir}/bin/mcp-server-filesystem/index.js", onedrive_dir],
    }
    changed = True
    print("OneDrive MCP added to Windows Claude Desktop config.")
else:
    print("ONEDRIVE_DIR not set — skipping OneDrive MCP for Windows Claude Desktop.")

if changed:
    with open(config_path, "w") as f:
        json.dump(config, f, indent=2)
        f.write("\n")
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

# --- 8. Shell profiles ---
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

# bash — main profile files (bash has no standard local override convention)
append_if_missing "$HOME/.bashrc"       "BRAIN_DIR"    "export BRAIN_DIR=\"$BRAIN_DIR\""
append_if_missing "$HOME/.bash_profile" "BRAIN_DIR"    "export BRAIN_DIR=\"$BRAIN_DIR\""
append_if_missing "$HOME/.bashrc"       "ONEDRIVE_DIR" "export ONEDRIVE_DIR=\"$ONEDRIVE_DIR\"" "brain-onedrive"
append_if_missing "$HOME/.bash_profile" "ONEDRIVE_DIR" "export ONEDRIVE_DIR=\"$ONEDRIVE_DIR\"" "brain-onedrive"

# zsh — local override file (not tracked in dotfiles)
ZSH_LOCAL="$HOME/.zshrc.local"
if [[ ! -f "$ZSH_LOCAL" ]]; then touch "$ZSH_LOCAL"; fi
append_if_missing "$ZSH_LOCAL" "BRAIN_DIR"    "export BRAIN_DIR=\"$BRAIN_DIR\""
append_if_missing "$ZSH_LOCAL" "ONEDRIVE_DIR" "export ONEDRIVE_DIR=\"$ONEDRIVE_DIR\"" "brain-onedrive"

# nushell — local.nu (not tracked in dotfiles; auto-sourced by env.nu)
# Detect config dir dynamically: macOS uses ~/Library/Application Support/nushell/,
# Linux uses ~/.config/nushell/ — ask nu itself rather than hardcoding.
if command -v nu &>/dev/null; then
  NU_CONFIG_DIR=$(nu -c '$nu.default-config-dir' 2>/dev/null)
else
  NU_CONFIG_DIR="$HOME/.config/nushell"
fi
NU_LOCAL="$NU_CONFIG_DIR/local.nu"
if [[ ! -f "$NU_LOCAL" ]]; then
  mkdir -p "$NU_CONFIG_DIR"
  touch "$NU_LOCAL"
  echo "  Created $NU_LOCAL"
fi
if grep -q "BRAIN_DIR" "$NU_LOCAL"; then
  echo "  $NU_LOCAL: BRAIN_DIR already set, skipping."
else
  printf '\n# brain\n$env.BRAIN_DIR = "%s"\n' "$BRAIN_DIR" >> "$NU_LOCAL"
  echo "  $NU_LOCAL: added BRAIN_DIR."
fi
if grep -q "ONEDRIVE_DIR" "$NU_LOCAL"; then
  echo "  $NU_LOCAL: ONEDRIVE_DIR already set, skipping."
else
  printf '\n# brain-onedrive\n$env.ONEDRIVE_DIR = "%s"\n' "$ONEDRIVE_DIR" >> "$NU_LOCAL"
  echo "  $NU_LOCAL: added ONEDRIVE_DIR."
fi

echo ""
echo "---"
echo "brain-template sync setup (optional)"
echo "  The brain-sync-template skill needs to know where brain-template is checked out."

# On reruns: skip if already configured to a valid git repo
EXISTING_TEMPLATE=$(python3 -c "
import json, os
try:
    s = json.load(open(os.path.expanduser('~/.claude/settings.json')))
    print(s.get('env', {}).get('BRAIN_TEMPLATE_DIR', ''))
except: print('')
" 2>/dev/null)

BRAIN_TEMPLATE_DIR_INPUT=""
if [[ -n "$EXISTING_TEMPLATE" ]] && git -C "$EXISTING_TEMPLATE" -c safe.directory='*' rev-parse HEAD &>/dev/null 2>&1; then
  echo "  BRAIN_TEMPLATE_DIR already configured: $EXISTING_TEMPLATE (skipping)"
  BRAIN_TEMPLATE_DIR_INPUT=""  # signal: skip the block below
  BRAIN_TEMPLATE_DIR_RESOLVED="$EXISTING_TEMPLATE"
  SKIP_TEMPLATE=true
else
  read -r -p "  Path to brain-template repo (leave blank to skip): " BRAIN_TEMPLATE_DIR_INPUT
  SKIP_TEMPLATE=false
fi

if [[ "$SKIP_TEMPLATE" != "true" ]] && [[ -n "$BRAIN_TEMPLATE_DIR_INPUT" ]]; then
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
    append_if_missing "$ZSH_LOCAL"          "BRAIN_TEMPLATE_DIR" "export BRAIN_TEMPLATE_DIR=\"$BRAIN_TEMPLATE_DIR_RESOLVED\"" "brain-template"

    NU_LOCAL="$HOME/.config/nushell/local.nu"
    if [[ -f "$NU_LOCAL" ]] && grep -q "BRAIN_TEMPLATE_DIR" "$NU_LOCAL"; then
      echo "  $NU_LOCAL: BRAIN_TEMPLATE_DIR already set, skipping."
    elif [[ -f "$NU_LOCAL" ]]; then
      printf '\n# brain-template\n$env.BRAIN_TEMPLATE_DIR = "%s"\n' "$BRAIN_TEMPLATE_DIR_RESOLVED" >> "$NU_LOCAL"
      echo "  $NU_LOCAL: added BRAIN_TEMPLATE_DIR."
    fi

    echo "  BRAIN_TEMPLATE_DIR=$BRAIN_TEMPLATE_DIR_RESOLVED configured."
    echo "  Run /brain-sync-template to sync infrastructure files to the template."
  fi
elif [[ "$SKIP_TEMPLATE" != "true" ]]; then
  echo "  Skipped. Set BRAIN_TEMPLATE_DIR manually or re-run install.sh when ready."
fi

echo ""
echo "Install complete. Run 'bash $BRAIN_DIR/bin/setup-check.sh' to verify."
