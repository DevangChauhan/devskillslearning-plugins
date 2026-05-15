#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Install user-wide so skills are available across all projects
PLUGIN_DIR="${HOME}/.claude/plugins/devskillslearning-plugins"

echo "Installing devskillslearning-plugins to ${PLUGIN_DIR}..."

# Remove old install if present
rm -rf "${PLUGIN_DIR}"

# Copy plugin files
mkdir -p "${PLUGIN_DIR}"
cp -r "${SCRIPT_DIR}/.claude-plugin" "${PLUGIN_DIR}/"
cp -r "${SCRIPT_DIR}/skills" "${PLUGIN_DIR}/"
cp -r "${SCRIPT_DIR}/docs" "${PLUGIN_DIR}/"

echo ""
echo "devskillslearning-plugins installed!"
echo ""
echo "Available skills (after reload):"
for d in "${SCRIPT_DIR}/skills/"*/; do
    name=$(basename "$d")
    echo "  /devskillslearning-plugins:${name}"
done
echo ""
echo "Run /reload-plugins to activate."
