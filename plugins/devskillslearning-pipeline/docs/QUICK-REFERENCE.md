# Quick Reference — "I want to..."

Not sure where to start? Use `/devskillslearning-pipeline:workflow` and describe what you're trying to do.

## Start & Build

| I want to... | Skill | What it does |
|-------------|-------|-------------|
| Start a new project from scratch | `/devskillslearning-pipeline:scaffold` | Bootstrap project structure, build files, config |
| Add a feature or endpoint | `/devskillslearning-pipeline:write-code` | Full-stack implementation with auto-detection |
| Implement from a ticket | `/devskillslearning-pipeline:github` then `/devskillslearning-pipeline:write-code` | Read ticket, implement, link PR |
| Write or generate tests | `/devskillslearning-pipeline:write-tests` | Unit, web, integration, contract tests |
| Design an API contract first | `/devskillslearning-pipeline:design-api` | OpenAPI, AsyncAPI, gRPC, GraphQL specs |

## Review & Fix

| I want to... | Skill | What it does |
|-------------|-------|-------------|
| Review code before merging | `/devskillslearning-pipeline:code-review` | Architecture, security, N+1, convention checks |
| Review a GitHub PR | `/devskillslearning-pipeline:code-review` with PR URL | Fetches diff via MCP, submits inline review |
| Fix a bug or error | `/devskillslearning-pipeline:diagnose` | Root cause analysis from stack trace or log |
| Diagnose a production issue | `/devskillslearning-pipeline:diagnose` | Includes K8s, CI/CD, concurrency diagnostics |

## Improve & Harden

| I want to... | Skill | What it does |
|-------------|-------|-------------|
| Refactor or clean up code | `/devskillslearning-pipeline:refactor` | Safe restructuring with before/after tests |
| Add authentication/authorization | `/devskillslearning-pipeline:secure` | OAuth2, JWT, Keycloak, CORS, API keys |
| Add resilience to external calls | `/devskillslearning-pipeline:resilience` | Circuit breaker, retry, timeout, bulkhead |
| Upgrade Spring Boot or Java version | `/devskillslearning-pipeline:migrate` | Automated migration with test verification |
| Migrate JUnit 4 to 5 | `/devskillslearning-pipeline:migrate` | Annotation mapping, Rule→Extension conversion |
| Scan for CVEs / audit dependencies | `/devskillslearning-pipeline:dependency` | OWASP scan, version catalogs, BOMs |
| Optimize database queries/schema | `/devskillslearning-pipeline:database` | Schema design, indexes, no-downtime migrations |

## Ship & Operate

| I want to... | Skill | What it does |
|-------------|-------|-------------|
| Deploy or containerize | `/devskillslearning-pipeline:deploy` | Dockerfiles, K8s, Helm, CI/CD pipelines |
| Set up monitoring and alerting | `/devskillslearning-pipeline:monitor` | Prometheus, Grafana, Loki, tracing, SLIs/SLOs |
| Run performance/load tests | `/devskillslearning-pipeline:perf-test` | k6/Gatling scripts, JFR profiling |
| Cut a release | `/devskillslearning-pipeline:release` | Version bump, changelog, release notes |
| Document APIs or architecture | `/devskillslearning-pipeline:document` | OpenAPI docs, C4 diagrams, ADRs |
| Integrate with an external API | `/devskillslearning-pipeline:api-integrate` | Client generation, error mapping, webhooks |
| Manage GitHub issues and PRs | `/devskillslearning-pipeline:github` | Create epics/stories, review PRs via MCP |

## Common Workflows

**Greenfield project:**
```
/devskillslearning-pipeline:scaffold → /devskillslearning-pipeline:design-api → /devskillslearning-pipeline:database → /devskillslearning-pipeline:write-code → /devskillslearning-pipeline:write-tests → /devskillslearning-pipeline:code-review → /devskillslearning-pipeline:resilience → /devskillslearning-pipeline:secure → /devskillslearning-pipeline:perf-test → /devskillslearning-pipeline:deploy → /devskillslearning-pipeline:monitor → /devskillslearning-pipeline:release
```

**Feature addition:**
```
/devskillslearning-pipeline:write-code → /devskillslearning-pipeline:write-tests → /devskillslearning-pipeline:code-review
```

**Bug fix:**
```
/devskillslearning-pipeline:diagnose → /devskillslearning-pipeline:write-tests → /devskillslearning-pipeline:code-review
```

**Production hardening pass:**
```
/devskillslearning-pipeline:dependency → /devskillslearning-pipeline:resilience → /devskillslearning-pipeline:secure → /devskillslearning-pipeline:perf-test → /devskillslearning-pipeline:monitor → /devskillslearning-pipeline:deploy
```

**Refactor safely:**
```
/devskillslearning-pipeline:refactor → /devskillslearning-pipeline:write-tests → /devskillslearning-pipeline:code-review
```

**API-first feature:**
```
/devskillslearning-pipeline:design-api → /devskillslearning-pipeline:write-code → /devskillslearning-pipeline:write-tests → /devskillslearning-pipeline:code-review
```
