#!/bin/bash
# agy-statusline.sh — Wrapper for agy (Antigravity CLI) statusline.
# Reads agy session JSON from stdin, transforms it to Claude-Code format,
# then pipes through ai-statusline.sh for rendering.

BRAIN_DIR="${BRAIN_DIR:-$HOME/brain}"
python3 "$BRAIN_DIR/bin/agy-statusline.py"
