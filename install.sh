#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_PROJECT="${1:-$(pwd)}"

if [ ! -d "$TARGET_PROJECT" ]; then
    echo "Error: '$TARGET_PROJECT' is not a directory"
    echo "Usage: ./install.sh /path/to/your-java-project"
    exit 1
fi

echo "==> Installing devskillslearning-pipeline into: $TARGET_PROJECT"
echo ""

# Step 1: Register marketplace (idempotent)
echo "==> Registering marketplace..."
if claude plugins marketplace list 2>/dev/null | grep -q devskillslearning-pipeline; then
    echo "    Marketplace already registered, skipping"
else
    claude plugins marketplace add "${SCRIPT_DIR}"
fi

# Step 2: Install plugin at project scope
echo "==> Installing plugin (project scope)..."
pushd "$TARGET_PROJECT" > /dev/null

if claude plugins list 2>/dev/null | grep -q devskillslearning-pipeline; then
    echo "    Plugin already installed, skipping"
else
    claude plugins install devskillslearning-pipeline --scope project
fi

popd > /dev/null

echo ""
echo "Done! Run /reload-plugins in Claude Code to activate."
echo ""
echo "Available skills:"
echo "  /devskillslearning-pipeline:workflow     — guided entry point (start here if unsure)"
echo "  /devskillslearning-pipeline:scaffold     — bootstrap new project"
echo "  /devskillslearning-pipeline:write-code   — implement features"
echo "  /devskillslearning-pipeline:code-review  — architectural review"
echo "  /devskillslearning-pipeline:write-tests  — comprehensive test generation"
echo "  /devskillslearning-pipeline:refactor     — safe refactoring with verification"
echo "  /devskillslearning-pipeline:diagnose     — troubleshoot failures"
echo "  /devskillslearning-pipeline:secure       — security hardening (OAuth2, JWT, Keycloak)"
echo "  /devskillslearning-pipeline:deploy       — K8s, CI/CD, Docker, Helm"
echo "  /devskillslearning-pipeline:document     — API docs, AsyncAPI, architecture diagrams"
echo "  /devskillslearning-pipeline:migrate      — Spring Boot, Java, javax→jakarta upgrades"
echo "  /devskillslearning-pipeline:github       — GitHub project management + PR review"
echo "  /devskillslearning-pipeline:monitor      — metrics, tracing, logging, dashboards, alerting"
echo "  /devskillslearning-pipeline:design-api   — contract-first API design"
echo "  /devskillslearning-pipeline:database     — schema design, query optimization"
echo "  /devskillslearning-pipeline:resilience   — circuit breaker, retry, timeout, bulkhead"
echo "  /devskillslearning-pipeline:perf-test    — load testing, profiling, capacity planning"
echo "  /devskillslearning-pipeline:release      — semantic versioning, changelogs, release notes"
echo "  /devskillslearning-pipeline:dependency   — CVE scanning, version catalogs, BOMs"
echo "  /devskillslearning-pipeline:api-integrate — API client gen, webhook receivers"
echo ""
echo "---"
echo "To update:   cd ~/devskillslearning-pipeline && git pull && claude plugins update devskillslearning-pipeline"
echo "To uninstall: cd $TARGET_PROJECT && claude plugins uninstall devskillslearning-pipeline"
