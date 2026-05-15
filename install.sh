#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Adding devskillslearning marketplace..."
claude plugins marketplace add "${SCRIPT_DIR}" 2>/dev/null ||
    echo "    (marketplace already registered, skipping)"

echo "==> Installing devskillslearning-pipeline..."
if claude plugins list 2>/dev/null | grep -q devskillslearning-pipeline; then
    echo "    (plugin already installed, skipping)"
else
    claude plugins install devskillslearning-pipeline
fi

echo ""
echo "Done! Run /reload-plugins in Claude Code to activate."
echo ""
echo "Available skills:"
echo "  /devskillslearning-pipeline:write-code"
echo "  /devskillslearning-pipeline:code-review"
