# DevSkillsLearning Pipeline — Usage Guide

Complete AI-first Java/Spring Boot SDLC automation with GitHub project management integration.

## Skills Overview

| # | Skill | What It Does | Run After |
|---|-------|-------------|-----------|
| 1 | `scaffold` | Bootstrap a new project with best-practice foundation | — (entry point for greenfield) |
| 2 | `write-code` | Implement features with full-stack code generation | `scaffold` or when adding features |
| 3 | `code-review` | 100+ architectural, security, and convention checks | `write-code`, before PR |
| 4 | `write-tests` | Comprehensive test generation (unit, web, integration) | `write-code`, for existing code |
| 5 | `refactor` | Safe restructuring with before/after test verification | When code needs cleanup |
| 6 | `diagnose` | Root cause analysis for build/test/runtime failures | When something breaks |
| 7 | `secure` | Defense-in-depth: OAuth2, JWT, Keycloak, CORS, rate limiting | Before production deploy |
| 8 | `deploy` | Containerization, K8s manifests, CI/CD pipelines | After features are built |
| 9 | `document` | OpenAPI, AsyncAPI, C4 diagrams, ADRs, READMEs | After APIs stabilize |
| 10 | `migrate` | Automated Spring Boot/Java version upgrades | For version upgrade tasks |
| 11 | `github` | GitHub project management + PR review via MCP | For ticket/PR workflows |
| 12 | `monitor` | Metrics, tracing, alerting, Grafana dashboards | Before production deploy |
| 13 | `design-api` | Contract-first API design (OpenAPI, AsyncAPI, gRPC, GraphQL) | Before implementing endpoints |
| 14 | `database` | Schema design, query optimization, no-downtime migrations | Before/alongside schema changes |
| 15 | `resilience` | Circuit breaker, retry, timeout, bulkhead, rate limiter | After adding downstream calls |
| 16 | `perf-test` | k6/Gatling load tests, JFR/profiling, capacity planning | Before production deploy |
| 17 | `release` | Semantic versioning, changelogs, release notes, CI release automation | When cutting a release |
| 18 | `dependency` | OWASP scanning, version catalogs, BOMs, auto-updates | Weekly / before releases |

---

## Quick Start: Choose Your Entry Point

### I'm starting a new project

```
/devskillslearning-pipeline:scaffold
Create a new project called "order-service" for com.acme
```

Then build features:
```
/devskillslearning-pipeline:write-code
Add CRUD endpoints for orders with fields: id, customerId, items, totalAmount, status
```

### I'm adding a feature to an existing project

```
/devskillslearning-pipeline:write-code
Add a PATCH endpoint to update order status with state machine validation
```

### I need to review code before a PR

```
# Review local changes
/devskillslearning-pipeline:code-review

# Review a GitHub PR
/devskillslearning-pipeline:code-review https://github.com/myorg/myservice/pull/128
```

### I have a ticket to work on

```
/devskillslearning-pipeline:github
Read ticket #15 from myorg/myservice, implement it, and link the PR
```

---

## GitHub Integration

The `github` skill and PR review features require the **GitHub MCP server** to be configured.

### One-Time Setup

**1. Create a GitHub Personal Access Token:**

Go to https://github.com/settings/tokens → Generate new token (classic).
Required scopes: `repo`, `read:org`, `workflow`

**2. Configure the MCP server in Claude Code:**

Add to `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "github": {
      "type": "http",
      "url": "https://mcp.github.com/mcp",
      "headers": {
        "Authorization": "Bearer ghp_xxxxxxxxxxxxxxxxxxxx"
      }
    }
  }
}
```

**3. Verify it works:**

```
# In Claude Code, ask:
List open issues in myorg/myservice
```

If you see your issues, you're all set.

### Capabilities

| Capability | How to Trigger | Example |
|-----------|---------------|---------|
| Create an epic | `github` skill | "Create an epic for the User Auth System in myorg/myservice" |
| Create a user story | `github` skill | "Create a story under epic #42 for JWT refresh token endpoint" |
| Create a bug ticket | `github` skill | "File a bug: orders with negative quantities are accepted" |
| Read a ticket | `github` skill | "Read ticket #15 from myorg/myservice" |
| List/sort tickets | `github` skill | "List all open stories in myorg/myservice" |
| Update ticket status | `github` skill | "Close ticket #23 as completed" |
| Add a comment | `github` skill | "Comment on #15: PR is ready for review" |
| Implement from ticket | `github` or `write-code` | "Implement ticket #15 from myorg/myservice" |
| Review PR by URL | `code-review` | `/devskillslearning-pipeline:code-review https://github.com/myorg/myservice/pull/128` |
| Review PR by ticket ID | `code-review` | `/devskillslearning-pipeline:code-review review PR for ticket #15 in myorg/myservice` |
| Create PR linked to issue | `github` skill | "Create a PR from branch feature/15-oauth to main, closing #15" |
| Submit review to GitHub | automatic after remote review | (done automatically) |

---

## End-to-End Workflow Examples

### Example 1: New Feature from Ticket

```
User: Read ticket #42 from myorg/order-service

Claude: [reads issue]
  Epic: Payment Integration
  Story: "As a customer, I want to pay with stored credit card"
  AC: Given valid card, when POST /api/v1/payments, then 201 with payment ID
  Assigned to: devangchauhan

  Starting implementation. Creating branch feature/42-stored-card-payment...

User: 

Claude: [implements the feature using write-code conventions]
  ✓ Entity Payment, migration V3__create_payments.sql
  ✓ PaymentController, PaymentService, PaymentRepository
  ✓ DTOs: PaymentRequest, PaymentResponse
  ✓ Unit tests, web layer tests, integration test
  ✓ Build passes: mvn clean verify

  Creating PR...

  ✓ PR #67 created: "Add stored card payment endpoint"
  ✓ Linked to issue #42
  Ready for review.

User: /devskillslearning-pipeline:code-review review PR #67 in myorg/order-service

Claude: [fetches PR diff, runs 100+ checks]
  ## Review Summary
  BLOCKER: 0 | HIGH: 1 | MEDIUM: 3 | LOW: 2

  HIGH: PaymentService.java:45 — Missing @Transactional on processPayment()
  MEDIUM: PaymentController.java:20 — Missing @Timed annotation
  ...

  Submitted review to GitHub as REQUEST_CHANGES.
```

### Example 2: Greenfield Project with GitHub Tracking

```
User: Create a new project called "inventory-service" for com.acme.
      Also create an epic in myorg/inventory-service for it.

Claude: [scaffolds project]
  ✓ Maven project bootstrapped: Java 21, Spring Boot 3.3, PostgreSQL, Flyway
  ✓ Package structure, base classes, HealthController
  ✓ Build passes

  [creates epic]
  ✓ Epic #1: "Inventory Service — Initial Implementation"

  Ready. Health endpoint at GET /api/v1/health.
  Epic tracks all work at: https://github.com/myorg/inventory-service/issues/1

  Create your first story with:
  /devskillslearning-pipeline:github
  Create a story under epic #1 in myorg/inventory-service for "Add product CRUD endpoints"
```

### Example 3: PR Review via URL

```
User: /devskillslearning-pipeline:code-review https://github.com/myorg/payment-service/pull/89

Claude: [parses URL: owner=myorg, repo=payment-service, pr=89]
  [fetches diff, changed files, check runs]
  [fetches existing reviews to avoid duplicate feedback]
  [applies 100+ checks against all changed files]

  ## Code Review — PR #89

  | Severity | File:Line | Issue | Fix |
  |----------|-----------|-------|-----|
  | BLOCKER  | PaymentService.java:12 | javax.persistence on Spring Boot 3.x | Replace with jakarta.persistence |
  | HIGH     | PaymentConsumer.java:30 | N+1: repository call in forEach | Use @EntityGraph |
  | HIGH     | PaymentController.java:50 | Missing @Valid on request body | Add @Valid |
  | MEDIUM   | PaymentService.java:55 | Uses Double for monetary amount | Change to BigDecimal |

  CI checks: ✓ build (passed), ✓ test (passed), ⚠ security-scan (3 medium CVEs)

  [submits review to GitHub with REQUEST_CHANGES + inline comments]
```

---

## What Each Skill Auto-Discovers

You don't need to provide these — all skills detect them automatically:

- **Build system**: Maven vs Gradle, single vs multi-module
- **Spring Boot version**: 2.x (javax) vs 3.x (jakarta)
- **Architecture type**: Monolith, REST microservices, event-driven, gRPC, GraphQL
- **Execution model**: Servlet/blocking vs Reactive/WebFlux
- **Package layout**: Package-by-layer vs package-by-feature
- **Error handling**: Base exception, error codes, response wrappers
- **Migration tool**: Flyway vs Liquibase
- **Libraries in use**: Lombok, MapStruct, Testcontainers, WireMock, Micrometer
- **Testing stack**: JUnit 5, Mockito, AssertJ, Awaitility, RestAssured
- **Database**: PostgreSQL, MySQL, H2, embedded
- **Message broker**: Kafka, RabbitMQ

---

## Skill Input Reference (Quick)

| Skill | Minimal Input | Full Input |
|-------|--------------|------------|
| `scaffold` | "Create order-service for com.acme" | Group ID, artifact ID, architecture, DB, integrations |
| `write-code` | "Add CRUD for orders" | Entity fields, business rules, API contract |
| `code-review` | (nothing — reviews local changes) | PR URL or ticket ID for remote review |
| `write-tests` | "Write tests for OrderService" | Specific scenarios, test type |
| `refactor` | "Extract PricingService from OrderService" | Why — helps me understand intent |
| `diagnose` | (paste stack trace) | What you were doing, when it started |
| `secure` | "Add OAuth2 JWT with Keycloak" | Public endpoints, identity provider URL |
| `deploy` | "Generate K8s manifests" | Target environment, container registry |
| `document` | "Generate OpenAPI spec" | Audience, specific endpoints |
| `migrate` | "Upgrade Spring Boot 2.7 to 3.3" | Module, known tricky areas |
| `github` | "Create epic in owner/repo" / "Review PR URL" | Ticket details, PR URL |
| `monitor` | "Add Prometheus metrics" | Metrics backend, SLO targets |
| `design-api` | "Design REST API for the order service" | Resources, operations, consumers |
| `database` | "Design schema for payment service" | Database engine, data volumes |
| `resilience` | "Add circuit breaker to PaymentClient" | Downstream dependencies, thresholds |
| `perf-test` | "Load test the checkout endpoint" | Target RPS, p99 SLO, OpenAPI spec |
| `release` | "Release v1.3.0" | Target version, version bump type |
| `dependency` | "Scan for vulnerabilities" | Specific CVE or dependency concern |

---

## Installation

```bash
# Clone and install
git clone https://github.com/DevangChauhan/devskillslearning-plugins.git
cd devskillslearning-plugins
./install.sh /path/to/your-java-project

# In your project's Claude Code session:
/reload-plugins
```

To update:
```bash
cd devskillslearning-plugins
git pull
# In your project session:
claude plugins update devskillslearning-pipeline
```

---

## Next Steps After Reading

1. **Set up GitHub MCP** (one-time, 3 minutes) — see [GitHub Integration](#github-integration) above
2. **Try scaffolding a test project**: `/devskillslearning-pipeline:scaffold`
3. **Try reviewing a PR**: `/devskillslearning-pipeline:code-review <PR-URL>`
4. **Try reading a ticket**: `/devskillslearning-pipeline:github` → "Read ticket #1 from myorg/myrepo"
