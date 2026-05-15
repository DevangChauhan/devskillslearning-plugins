#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Adding devskillslearning marketplace..."
claude plugins marketplace add "${SCRIPT_DIR}" 2>/dev/null || true

echo "Installing devskillslearning-plugins..."
claude plugins install devskillslearning-plugins@devskillslearning-plugins 2>/dev/null || \
claude plugins install devskillslearning-plugins 2>/dev/null || true

echo ""
echo "Available skills (after /reload-plugins):"
echo "  /devskillslearning-plugins:write-code"
echo "  /devskillslearning-plugins:code-review"
echo ""
echo "Run /reload-plugins to activate."
