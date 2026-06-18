# agy-statusline.py — Transforms Antigravity CLI (agy) session JSON into the
# Claude-Code statusline format, then pipes through ai-statusline.sh for rendering.
# agy sends a different JSON schema than what starship expects; this script bridges that gap.
import sys, json, os, subprocess

# 1. Read agy session data from stdin
try:
    raw_input = sys.stdin.read()
    session_data = json.loads(raw_input)
except Exception:
    session_data = {}

# 2. Extract model name & display name
model_val = session_data.get("model")
model_id = "gemini-3.5"
model_display = "Gemini 3.5"

if isinstance(model_val, str):
    model_id = model_val
    model_display = model_val.replace("-", " ").replace("pro", "Pro").replace("flash", "Flash").title()
elif isinstance(model_val, dict):
    model_id = model_val.get("name", model_val.get("displayName", "gemini-3.5"))
    model_display = model_val.get("displayName", model_val.get("name", "Gemini 3.5"))
else:
    model_info = session_data.get("modelInfo", {})
    if isinstance(model_info, dict):
        model_id = model_info.get("name", "gemini-3.5")
        model_display = model_info.get("displayName", model_info.get("name", "Gemini 3.5"))

# Format display name nicely (make sure Gemini is capitalized correctly)
if "gemini" in model_display.lower():
    model_display = model_display.replace("gemini", "Gemini").replace("Gemini", "Gemini ")
    # Strip any double spaces
    model_display = " ".join(model_display.split())

# 3. Extract tokens and max tokens
context_window = session_data.get("context_window", {})
tokens = context_window.get("total_input_tokens", 0)
max_tokens = context_window.get("context_window_size", 1048576)
used_pct = context_window.get("used_percentage", 0.0)

# Fallback for old/legacy formats
if not tokens:
    t_val = session_data.get("tokens")
    if isinstance(t_val, int):
        tokens = t_val
    elif isinstance(t_val, dict):
        tokens = t_val.get("currentUsage", t_val.get("input", 0) + t_val.get("output", 0))
    else:
        c_val = session_data.get("context")
        if isinstance(c_val, int):
            tokens = c_val
        elif isinstance(c_val, dict):
            tokens = c_val.get("currentUsage", c_val.get("tokens", 0))

if not tokens:
    tokens = session_data.get("currentUsage", session_data.get("inputTokens", 0) + session_data.get("outputTokens", 0))

# Fallback for max tokens / context window size
if max_tokens == 1048576 and "maxTokens" in session_data:
    max_tokens_val = session_data.get("maxTokens", 1000000)
    if isinstance(max_tokens_val, dict):
        max_tokens = max_tokens_val.get("limit", 1000000)
    elif isinstance(max_tokens_val, int):
        max_tokens = max_tokens_val

# Compute fallback used percentage
if used_pct == 0.0 and max_tokens > 0:
    used_pct = (tokens / max_tokens) * 100.0

# 4. Construct Starship compatible JSON
starship_json = {
    "model": {
        "id": model_id,
        "display_name": model_display
    },
    "context_window": {
        "context_window_size": max_tokens,
        "total_input_tokens": tokens,
        "total_output_tokens": context_window.get("total_output_tokens", 0),
        "used_percentage": used_pct,
        "current_usage": context_window.get("current_usage", {
            "input_tokens": tokens,
            "output_tokens": 0,
            "cache_creation_input_tokens": 0,
            "cache_read_input_tokens": 0
        })
    },
    "cost": {
        "total_cost_usd": 0.0,
        "total_duration_ms": 0,
        "total_api_duration_ms": 0,
        "total_lines_added": 0,
        "total_lines_removed": 0
    }
}

# 5. Pipe JSON through ai-statusline.sh (sets STARSHIP_CONFIG, calls starship)
try:
    brain_dir = os.environ.get("BRAIN_DIR", os.path.expanduser("~/brain"))
    wrapper = os.path.join(brain_dir, "bin", "ai-statusline.sh")
    env = os.environ.copy()
    env["TERM"] = "xterm-256color"
    p = subprocess.Popen(
        ["bash", wrapper],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        text=True
    )
    stdout, stderr = p.communicate(input=json.dumps(starship_json))
    sys.stdout.write(stdout)
except Exception as e:
    sys.stderr.write(f"Error executing statusline: {e}\n")
