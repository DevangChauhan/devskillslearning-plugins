# Quick Reference — "I want to..."

Not sure where to start? Use `/devskillslearning-pipeline:workflow` and describe what you're trying to do.

## Start & Build

| I want to... | Skill | What it does |
|-------------|-------|-------------|
| Start a new project from scratch | `/scaffold` | Bootstrap project structure, build files, config |
| Add a feature or endpoint | `/write-code` | Full-stack implementation with auto-detection |
| Implement from a ticket | `/github` then `/write-code` | Read ticket, implement, link PR |
| Write or generate tests | `/write-tests` | Unit, web, integration, contract tests |
| Design an API contract first | `/design-api` | OpenAPI, AsyncAPI, gRPC, GraphQL specs |

## Review & Fix

| I want to... | Skill | What it does |
|-------------|-------|-------------|
| Review code before merging | `/code-review` | Architecture, security, N+1, convention checks |
| Review a GitHub PR | `/code-review` with PR URL | Fetches diff via MCP, submits inline review |
| Fix a bug or error | `/diagnose` | Root cause analysis from stack trace or log |
| Diagnose a production issue | `/diagnose` | Includes K8s, CI/CD, concurrency diagnostics |

## Improve & Harden

| I want to... | Skill | What it does |
|-------------|-------|-------------|
| Refactor or clean up code | `/refactor` | Safe restructuring with before/after tests |
| Add authentication/authorization | `/secure` | OAuth2, JWT, Keycloak, CORS, API keys |
| Add resilience to external calls | `/resilience` | Circuit breaker, retry, timeout, bulkhead |
| Upgrade Spring Boot or Java version | `/migrate` | Automated migration with test verification |
| Migrate JUnit 4 to 5 | `/migrate` | Annotation mapping, Rule→Extension conversion |
| Scan for CVEs / audit dependencies | `/dependency` | OWASP scan, version catalogs, BOMs |
| Optimize database queries/schema | `/database` | Schema design, indexes, no-downtime migrations |

## Ship & Operate

| I want to... | Skill | What it does |
|-------------|-------|-------------|
| Deploy or containerize | `/deploy` | Dockerfiles, K8s, Helm, CI/CD pipelines |
| Set up monitoring and alerting | `/monitor` | Prometheus, Grafana, tracing, SLIs/SLOs |
| Run performance/load tests | `/perf-test` | k6/Gatling scripts, JFR profiling |
| Cut a release | `/release` | Version bump, changelog, release notes |
| Document APIs or architecture | `/document` | OpenAPI docs, C4 diagrams, ADRs |
| Integrate with an external API | `/api-integrate` | Client generation, error mapping, webhooks |
| Manage GitHub issues and PRs | `/github` | Create epics/stories, review PRs via MCP |

## Common Workflows

**Greenfield project:**
```
/scaffold → /design-api → /database → /write-code → /write-tests → /code-review
→ /resilience → /secure → /perf-test → /deploy → /monitor → /release
```

**Feature addition:**
```
/write-code → /write-tests → /code-review
```

**Bug fix:**
```
/diagnose → /write-tests → /code-review
```

**Production hardening pass:**
```
/dependency → /resilience → /secure → /perf-test → /monitor → /deploy
```

**Refactor safely:**
```
/refactor → /write-tests → /code-review
```

**API-first feature:**
```
/design-api → /write-code → /write-tests → /code-review
```
