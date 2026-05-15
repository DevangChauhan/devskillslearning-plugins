#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-.}"

if [ ! -d "$TARGET" ]; then
    echo "Error: '$TARGET' is not a directory"
    exit 1
fi

SKILL_DIR="$TARGET/.claude/skills/devskillslearning-plugins"
mkdir -p "$SKILL_DIR"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/skills/"*.md "$SKILL_DIR/"
cp "$SCRIPT_DIR/docs/CONVENTIONS.md" "$SKILL_DIR/"

echo "Installed devskillslearning-plugins to $SKILL_DIR"
echo ""
echo "Available skills:"
for f in "$SCRIPT_DIR/skills/"*.md; do
    name=$(basename "$f" .md)
    echo "  /devskillslearning-plugins:$name"
done
