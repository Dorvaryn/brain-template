#!/bin/bash
# ai-statusline.sh — Generic AI statusline wrapper for Claude Code and agy.
#
# Sets STARSHIP_CONFIG to the brain custom config so both CLIs get the same
# statusline layout (model, context gauge, brain metrics, calendar).
#
# Claude Code sends native claude-code JSON directly via stdin.
# agy pipes through agy-statusline.py first to transform its JSON format.
#
# Usage (Claude Code settings.json):
#   "statusLine": { "type": "command", "command": "bash $BRAIN_DIR/bin/ai-statusline.sh" }
#
# Usage (agy pipeline):
#   agy session data → agy-statusline.py → this script → starship

BRAIN_DIR="${BRAIN_DIR:-$HOME/brain}"
STARSHIP_CONFIG="$BRAIN_DIR/config/starship-statusline.toml" \
    starship statusline claude-code
