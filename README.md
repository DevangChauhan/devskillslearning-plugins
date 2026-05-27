# DevSkillsLearning Pipeline

Claude Code plugin pack for AI-first Java/Spring Boot development. Provides slash-command skills that automate the SDLC: spec-driven code generation, architectural code review, and more. Adapts to monolith, microservices, and event-driven architectures by discovering project conventions automatically.

## Installation

### Prerequisites

- [Claude Code](https://claude.ai/code) CLI installed and authenticated
- Verify with: `claude --version`

### Option 1: One-command install (recommended)

```sh
# Clone and install into your project in one go
git clone https://github.com/DevangChauhan/devskillslearning-plugins.git ~/devskillslearning-pipeline && \
  cd ~/devskillslearning-pipeline && \
  ./install.sh /path/to/your-project
```

### Option 2: Step-by-step install

```sh
# Step 1: Clone the marketplace repo
git clone https://github.com/DevangChauhan/devskillslearning-plugins.git ~/devskillslearning-pipeline

# Step 2: Navigate to your project
cd /path/to/your-java-project

# Step 3: Register the marketplace (one-time)
claude plugins marketplace add ~/devskillslearning-pipeline

# Step 4: Install the plugin at project scope
claude plugins install devskillslearning-pipeline --scope project

# Step 5: Activate in your Claude Code session
# Type: /reload-plugins
```

### Verify Installation

```sh
# List installed plugins — you should see devskillslearning-pipeline
claude plugins list

# Show plugin details
claude plugins details devskillslearning-pipeline
```

After running `/reload-plugins` in Claude Code, these slash commands become available:

| Skill | Invocation | What it does |
|-------|-----------|--------------|
| Scaffold | `/devskillslearning-pipeline:scaffold` | Bootstraps a new Java/Spring Boot project — build file, package structure, base classes, config, Docker, health endpoint |
| Write Code | `/devskillslearning-pipeline:write-code` | Discovers project conventions, implements full stack: migration → entity → repo → DTO → mapper → service → controller → events → observability → tests |
| Code Review | `/devskillslearning-pipeline:code-review` | Reviews code against architecture, transactions, N+1 queries, caching, observability, security — reports issues with file:line and severity |
| Write Tests | `/devskillslearning-pipeline:write-tests` | Generates comprehensive tests: unit, web layer, integration, contract, architecture — with systematic edge case coverage |
| Refactor | `/devskillslearning-pipeline:refactor` | Safe refactoring with before/after test verification — extract service, split controller, convert to record, restructure packages |
| Diagnose | `/devskillslearning-pipeline:diagnose` | Systematic root cause analysis for build failures, test failures, startup errors, and runtime issues |
| Secure | `/devskillslearning-pipeline:secure` | Security hardening: OAuth2/JWT, Keycloak, method-level security, API keys, CORS, rate limiting, audit logging |
| Deploy | `/devskillslearning-pipeline:deploy` | Deployment artifacts: Docker (multi-stage/distroless), K8s manifests, GitHub Actions CI/CD, Helm charts |
| Document | `/devskillslearning-pipeline:document` | Generate API docs (OpenAPI 3.0, AsyncAPI), C4 architecture diagrams, ADRs, onboarding READMEs |
| Migrate | `/devskillslearning-pipeline:migrate` | Automate Spring Boot 2→3, javax→jakarta, Java version upgrades, deprecated API replacement |
| GitHub | `/devskillslearning-pipeline:github` | GitHub project management + PR review via MCP — create epics/stories/tickets |
| Monitor | `/devskillslearning-pipeline:monitor` | Production observability — metrics, tracing, Loki log aggregation, Grafana, SLIs/SLOs, alerting |
| Design API | `/devskillslearning-pipeline:design-api` | Contract-first API design — OpenAPI, AsyncAPI, gRPC, GraphQL specs |
| Database | `/devskillslearning-pipeline:database` | Schema design, query optimization, no-downtime migrations, connection pool tuning |
| Resilience | `/devskillslearning-pipeline:resilience` | Resilience4j — circuit breaker, retry, timeout, bulkhead, rate limiter |
| Perf Test | `/devskillslearning-pipeline:perf-test` | k6/Gatling load tests, JFR/profiling, bottleneck identification, capacity planning |
| Release | `/devskillslearning-pipeline:release` | Semantic versioning, changelogs, release notes, CI release automation |
| Dependency | `/devskillslearning-pipeline:dependency` | OWASP CVE scanning, version catalogs, BOMs, transitive conflict resolution |
| API Integrate | `/devskillslearning-pipeline:api-integrate` | OpenAPI client gen, RestClient/WebClient, error mapping, caching, webhook receivers |
| Workflow | `/devskillslearning-pipeline:workflow` | Guided entry point — describes what you want to do and get routed to the right skill chain |

## Supported Technology Stack

The plugin adapts to the technologies detected in your project:

| Category | Technologies |
|----------|-------------|
| **Build** | Maven, Gradle, Gradle Kotlin DSL |
| **Java** | 17, 21, 23 |
| **Spring Boot** | 2.x (javax), 3.x (jakarta) |
| **Architecture** | Monolith, Spring Modulith, REST Microservices, Event-Driven Microservices |
| **Execution** | Servlet (Tomcat), Reactive (Netty/WebFlux/R2DBC) |
| **API Protocols** | REST, gRPC, GraphQL, WebSocket, SSE |
| **Databases** | PostgreSQL, MySQL, Redis, MongoDB |
| **Messaging** | Kafka, RabbitMQ |
| **Security** | OAuth2/JWT, Keycloak, API Keys |
| **Deployment** | Kubernetes, Docker, GitHub Actions, GitLab CI, Helm |
| **Observability** | Micrometer, Prometheus, OpenTelemetry, Grafana |
| **Batch** | Spring Batch, @Scheduled |
| **Resilience** | Circuit Breaker, Retry, Timeout, Bulkhead, Rate Limiter |
| **Data Patterns** | Multi-tenancy, Event Sourcing, CDC (Debezium), Schema Registry, CloudEvents |

## Updating

When new versions are released, update to get the latest skills, conventions, and fixes:

```sh
# Step 1: Pull latest changes from GitHub
cd ~/devskillslearning-pipeline
git pull origin main

# Step 2: Update the plugin in Claude Code
claude plugins update devskillslearning-pipeline

# Step 3: Activate
# Type /reload-plugins in Claude Code
```

To check which version you have:

```sh
claude plugins list                  # Shows installed version
claude plugins details devskillslearning-pipeline  # Full details
```

## Uninstall

```sh
# Step 1: Uninstall the plugin from your project
cd /path/to/your-java-project
claude plugins uninstall devskillslearning-pipeline

# Step 2: Remove the marketplace registry (optional)
claude plugins marketplace remove devskillslearning-pipeline

# Step 3: Delete the cloned repo (optional)
rm -rf ~/devskillslearning-pipeline
```

## Requirements

Works with any Java/Spring Boot project. The skills auto-detect:

- **Build system**: Maven or Gradle (single or multi-module)
- **Architecture**: Monolith, REST microservices, or event-driven microservices
- **Project conventions**: Package structure, error handling patterns, response wrappers, base classes

No specific project layout or library is required. The skills discover your conventions by scanning the codebase and `CLAUDE.md`.

## Conventions Enforced

The skills automatically enforce these rules (see [docs/CONVENTIONS.md](plugins/devskillslearning-pipeline/docs/CONVENTIONS.md)):

| Rule | Enforced by |
|------|------------|
| Constructor injection only | `write-code` + `code-review` |
| Records for DTOs | `write-code` + `code-review` |
| `BigDecimal` for money (never `Double`) | `write-code` + `code-review` |
| Error code enum (never ad-hoc strings) | `write-code` + `code-review` |
| `@Getter`/`@Setter`/`@NoArgsConstructor` on entities (no `@Data`) | `write-code` + `code-review` |
| Controllers implement OpenAPI-generated interfaces (when present) | `write-code` + `code-review` |
| Controllers to Services to Repositories (no skipping layers) | `code-review` |
| Proper package placement (`*.controller`, `*.service.impl`, etc.) | Both |
| Event contracts treated as first-class API (event-driven projects) | `code-review` |
| Outbox pattern for transactional event publishing (event-driven projects) | `write-code` + `code-review` |

## License

MIT
