#!/bin/bash
set -uo pipefail
cd "$BRAIN_DIR"
git pull --rebase origin main 2>&1 | tail -5
echo '{}'
