# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A **Claude Code marketplace** that distributes a single plugin: `devskillslearning-pipeline`. The plugin provides 19 slash-command skills (`scaffold`, `write-code`, `code-review`, `write-tests`, `refactor`, `diagnose`, `secure`, `deploy`, `document`, `migrate`, `github`, `monitor`, `design-api`, `database`, `resilience`, `perf-test`, `release`, `dependency`, `api-integrate`) for AI-assisted Java/Spring Boot development covering the full enterprise SDLC. Skills auto-detect project architecture, execution model, Spring Boot version, build system, and conventions. GitHub integration via MCP: create epics/stories/tickets, PR review by URL or ticket ID, issue management.

## Repo structure

```
.claude-plugin/marketplace.json         # Marketplace manifest — lists contained plugins
plugins/devskillslearning-pipeline/
  .claude-plugin/plugin.json            # Plugin manifest (name, version, description)
  skills/
    scaffold/SKILL.md                   # Bootstrap new projects
    write-code/SKILL.md                 # Full-stack feature implementation
    code-review/SKILL.md                # Architectural review with 100+ checks
    write-tests/SKILL.md                # Comprehensive test generation
    refactor/SKILL.md                   # Safe refactoring with test verification
    diagnose/SKILL.md                   # Root cause analysis and fix
    secure/SKILL.md                     # Security hardening (OAuth2, JWT, Keycloak)
    deploy/SKILL.md                     # K8s, CI/CD, Docker, Helm
    document/SKILL.md                   # OpenAPI, AsyncAPI, C4 diagrams, ADRs
    migrate/SKILL.md                    # Spring Boot 2→3, javax→jakarta, Java upgrades
    github/SKILL.md                     # GitHub integration: epics, stories, PR review
    monitor/SKILL.md                    # Production observability: metrics, tracing, alerting
    design-api/SKILL.md                 # Contract-first API design: OpenAPI, AsyncAPI, gRPC
    database/SKILL.md                   # Schema design, query optimization, safe migrations
    resilience/SKILL.md                 # Resilience4j: circuit breaker, retry, timeout, bulkhead
    perf-test/SKILL.md                  # k6/Gatling load tests, JFR profiling, capacity planning
    release/SKILL.md                    # Semantic versioning, changelogs, release notes, CI automation
    dependency/SKILL.md                 # OWASP scanning, version catalogs, BOMs, Renovate/Dependabot
    api-integrate/SKILL.md              # OpenAPI client gen, RestClient/WebClient, webhook receivers
  README.md                             # Usage guide with quick start and examples
  docs/CONVENTIONS.md                   # Best practices: full enterprise stack (1,700+ lines)
  docs/api-examples.md                  # Full OpenAPI, AsyncAPI, gRPC, GraphQL spec examples
  docs/SKILL-DEVELOPMENT.md             # Contributor guide: how to add/modify skills
install.sh                              # Idempotent install: registers marketplace + installs plugin
```

## Skill development

- Each skill is a single `SKILL.md` file with YAML frontmatter (`name`, `description`, `type: skill`).
- The frontmatter `name` is what appears in the slash-command palette.
- All skills auto-discover the target project's conventions: build system (Maven/Gradle), module structure, architecture type, Spring Boot version (2.x vs 3.x, javax vs jakarta), migration tool (Flyway/Liquibase), package layout, error handling patterns, response wrappers, and observability stack. `docs/CONVENTIONS.md` provides the best-practice reference that guides the skills when project-specific conventions cannot be discovered.
- When editing a skill, think in terms of the full codebase the skill will operate in — the skill instructs Claude Code on what to do inside the target Java project, not inside this repo.
- Skills must work across monolith, REST microservices, and event-driven microservices. Architecture-specific rules are gated behind auto-detection of the project type.
- `scaffold` is the entry point for greenfield projects — it bootstraps the project structure that the other skills operate on.
- `write-tests` is separated from `write-code` so users can request comprehensive test coverage for existing code without regenerating the implementation.
- `refactor` always runs tests before and after the change to verify no regression.
- `diagnose` is the troubleshooting entry point — classify the failure (build/compile/startup/test/runtime), trace root cause, apply fix, verify.
- `secure` adds defense-in-depth: OAuth2/JWT, Keycloak, method security, API keys, CORS, rate limiting, audit logging.
- `deploy` generates cloud-native artifacts: multi-stage Dockerfiles, K8s manifests (Deployment, Service, HPA, PDB, Ingress), GitHub Actions CI/CD, Helm charts.
- `github` provides full GitHub project management via MCP: create epics/stories/bug tickets with proper templates, read and search issues, update ticket status/assignees/labels, link stories to epics, implement features from ticket IDs, create PRs linked to issues, review PRs by URL or ticket ID with inline comments and formal review submission.
- CONVENTIONS.md now covers the full enterprise stack: REST, gRPC, GraphQL, WebSocket, reactive, Spring Modulith, security, resilience (circuit breaker/retry/timeout/bulkhead/rate limiter), Redis, Spring Batch, multi-tenancy, i18n, feature flags, event sourcing, CDC (Debezium), Schema Registry, CloudEvents.

## Testing plugin changes

To test skill changes locally:
1. Run `./install.sh /path/to/your-java-project` to register and install from the local clone.
2. In a Claude Code session in the target project, type `/reload-plugins`.
3. Invoke the skill (e.g., `/devskillslearning-pipeline:write-code`) and verify behavior.

## Releasing

- Bump `version` in `plugins/devskillslearning-pipeline/.claude-plugin/plugin.json`.
- Users update with `git pull` in their clone followed by `claude plugins update devskillslearning-pipeline`.
- The install script is idempotent — it skips marketplace registration and plugin install if already present.

## Conventions for this repo

- Shell scripts use `set -euo pipefail`, POSIX-compatible constructs, and check preconditions before acting.
- JSON files are hand-edited (manifest, plugin.json) — keep them valid.
- Markdown tables in skill files use GitHub-flavored table syntax.
