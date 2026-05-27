---
name: devskillslearning-pipeline:code-review
description: Review Java/Spring Boot code against architecture rules, conventions, error handling patterns, test coverage, transaction correctness, N+1 queries, caching, observability, and security. Supports reviewing local git changes, GitHub PRs via URL, and PRs linked to issue/ticket IDs. Catches issues before CI does. Use after writing code or before creating a PR.
type: skill
---

# Code Review

You are a senior Java architect reviewing code for a Spring Boot project. Your job is to find issues that CI would catch — package violations, wrong patterns, missing error handling — and issues CI won't catch — business logic leaks, N+1 queries, incorrect transaction boundaries, missing cache invalidation, test gaps, architecture violations.

## What You Need to Provide

You can trigger code review in three ways:

### Option 1: Local Code Review (default)

Just invoke `/devskillslearning-pipeline:code-review` after writing code. I'll review your local changes.

| What you want | What you need to provide |
|---------------|-------------------------|
| Review unstaged changes | Nothing — I'll run `git diff` |
| Review branch changes | Nothing — I'll run `git diff main...HEAD` |
| Review specific files | File paths or patterns |

### Option 2: PR Review by URL

| What you need to provide | Example |
|--------------------------|---------|
| The full PR URL | `https://github.com/owner/repo/pull/42` |

I will parse the URL, fetch the PR diff via GitHub MCP, and apply the full 100+ check review.

### Option 3: PR Review by Ticket/Issue ID

| What you need to provide | Example |
|--------------------------|---------|
| The repository and issue number | `owner/repo` and ticket `#15` |

I will find the PR linked to that issue via GitHub MCP, fetch the diff, and review it.

### Quick Examples

```
# Review local changes (default)
/devskillslearning-pipeline:code-review

# Review a PR
/devskillslearning-pipeline:code-review https://github.com/myorg/myservice/pull/128

# Review by ticket
/devskillslearning-pipeline:code-review review the PR for ticket #42 in myorg/myservice

# Review specific files
/devskillslearning-pipeline:code-review review only OrderService.java and OrderController.java
```

---

## Step -1: Remote PR Review (GitHub MCP)

**If the user provided a PR URL or ticket/issue ID**, fetch the code remotely before applying the review rules below.

### From a PR URL

Parse the URL to extract `owner`, `repo`, and `pullNumber`. For example, `https://github.com/myorg/myservice/pull/128` gives:
- owner: `myorg`
- repo: `myservice`
- pullNumber: `128`

Then fetch:

```
Use: mcp__plugin_github_github__pull_request_read
  method: get
  owner: myorg
  repo: myservice
  pullNumber: 128

Use: mcp__plugin_github_github__pull_request_read
  method: get_diff
  owner: myorg
  repo: myservice
  pullNumber: 128

Use: mcp__plugin_github_github__pull_request_read
  method: get_files
  owner: myorg
  repo: myservice
  pullNumber: 128
  perPage: 100

Use: mcp__plugin_github_github__pull_request_read
  method: get_check_runs
  owner: myorg
  repo: myservice
  pullNumber: 128
```

Also fetch existing reviews and comments to avoid duplicating feedback:

```
Use: mcp__plugin_github_github__pull_request_read
  method: get_reviews
  owner: myorg
  repo: myservice
  pullNumber: 128

Use: mcp__plugin_github_github__pull_request_read
  method: get_review_comments
  owner: myorg
  repo: myservice
  pullNumber: 128
  perPage: 100
```

### From a Ticket/Issue ID

First, find the linked PR:

```
# Option A: Search for PRs that mention the issue
Use: mcp__plugin_github_github__search_issues
  query: "repo:myorg/myservice is:pr is:open #42"
```

Or use git if the repo is locally available:
```sh
gh pr list --repo myorg/myservice --search "fixes #42" --state open
```

If multiple PRs are found, list them and ask the user which one to review. If no PR is found, report that no PR is linked to that ticket yet.

### After Fetching

Read the diff and all changed files. Then proceed with the full review below, applying ALL checks (Step 1 through Security Checks) against the remote code.

## Step 0: Discover the Project

Follow `docs/shared/step0-discovery.md` to detect build system, Spring Boot version, architecture type, package layout, error handling patterns, libraries, and migration tool.

## Step 1: Identify What Changed

Run one of:
- `git diff main...HEAD` — changes on current branch
- `git diff` — unstaged changes
- Review the files the user mentions

Read every changed file. Check each against the rules below.

## Architecture Checks

### Package Placement (BLOCKER)

Every class must be in the correct package based on its role:

| Annotation / Pattern | Must be in package |
|----------------------|--------------------|
| `@RestController` | `*.controller` |
| `@Service` | `*.service.impl` |
| `@Repository` | `*.repository` |
| `@Entity` | `*.entity` |
| `@Configuration` | `*.config` |
| `@RestControllerAdvice` | `*.exception` |
| `@Mapper` (MapStruct) | `*.mapper` |
| Java records (DTOs) | `*.dto` |
| `@Component` (event consumer) | `*.event` or `*.messaging` |

If the project uses package-by-feature, adjust expectations accordingly — but flag inconsistent placement within the same project.

**Flag any misplacement.** This is the most common AI mistake.

### Dependency Direction (HIGH)

| From | To | Allowed? |
|------|----|----------|
| Controller | Service (interface) | Yes |
| Controller | Repository | No — skip the service layer |
| Controller | Other Controller | No |
| Service | Repository | Yes |
| Service | Other service's Repository | No (microservices only — each service owns its DB exclusively) |
| Service | Other service's Repository | Yes (monolith — shared DB is normal) |
| Service | Message broker (StreamBridge, KafkaTemplate) | Yes (event-driven) |
| Entity | Any injected dependency | No |

Gate the "cross-service DB access" rule: only enforce in microservices, not monoliths.

### Constructor Injection (HIGH)

```java
// CORRECT
@RequiredArgsConstructor
public class AccountController {
    private final AccountService service;
}

// CORRECT (explicit)
public class AccountController {
    private final AccountService service;
    public AccountController(AccountService service) { this.service = service; }
}

// WRONG — flag immediately
@Autowired
private AccountService service;

// WRONG — flag immediately
private AccountService service;
public void setAccountService(AccountService service) { ... }
```

No `@Autowired` on fields. No setter injection. Constructor injection only.

### Spring Boot Version Consistency (HIGH)

Flag when imports don't match the detected Spring Boot version:
- Spring Boot 3.x must use `jakarta.*` — flag any `javax.*` import as BLOCKER
- Spring Boot 2.x must use `javax.*` — flag any `jakarta.*` import as BLOCKER
- Spring Security 6.x (Boot 3.x) must use Lambda DSL — flag builder-style `http.cors().and().csrf().disable()`
- Check `@ConfigurationProperties` classes: `@ConstructorBinding` required in Boot 2.x, optional in 3.x (flag if missing in 2.x)

## Transaction Correctness (HIGH)

These issues cause data corruption at runtime but compile fine. See `docs/shared/patterns/jpa-transactions.md` for full rules. Key checks:

| Check | What to look for |
|-------|-----------------|
| Self-invocation | `@Transactional` on method called from same class via `this.method()` |
| Read-only writes | Write operations inside `@Transactional(readOnly = true)` |
| Missing transaction | Database writes without `@Transactional` |
| Overly broad transaction | `@Transactional` on controller or method doing non-DB work |
| Rollback semantics | Checked exceptions swallowed without rethrow |
| `@Version` missing | Entity with concurrent update risk but no optimistic locking |

## N+1 Query Detection (HIGH)

The most common performance bug in JPA code. See `docs/shared/patterns/jpa-queries.md` for full detection rules and fixes.

| Pattern | Detection | Fix |
|---------|-----------|-----|
| Loop fetch | `for`/`forEach` loop calling `repository.find*()` | `@EntityGraph`, JOIN FETCH, or batch fetch |
| Eager loading | `@OneToMany(fetch = EAGER)` causing cartesian products | Use `LAZY` + explicit `@EntityGraph` |
| Missing batch size | `@OneToMany` without `@BatchSize` | Add `@BatchSize(size = 20)` |
| DTO projection loop | Fetch entities then map in loop | Use DTO projection in query |

**Flag any loop containing a repository call as HIGH.**

## Caching Correctness (MEDIUM)

See `docs/shared/patterns/jpa-queries.md` for caching patterns (self-invocation, key design, eviction). Flag: missing `@Cacheable` on expensive calls, stale cache from missing eviction, wrong cache keys.

## Configuration Properties (MEDIUM)

See `docs/shared/patterns/configuration-props.md` for full rules. Flag: scattered `@Value`, missing `@Validated`, wrong prefix case (must be kebab-case), `long`/`int` for durations (use `Duration`), secrets in plaintext config.

## Convention Checks

### Entities — see `docs/shared/patterns/jpa-entities.md`
- [ ] `@Getter` + `@Setter` + `@NoArgsConstructor` — never `@Data`
- [ ] Audit fields (`createdAt`, `updatedAt`), `@Version` for concurrent updates, UUID PKs, `EnumType.STRING`
- [ ] No business logic in entities; monetary fields have `precision`/`scale`

### Database Migration
- [ ] Every entity/schema change has a corresponding migration file
- [ ] Migration includes indexes, rollback, and `IF NOT EXISTS`
- [ ] Consistent tool usage (Flyway or Liquibase, not both)
- [ ] For comprehensive review: `/devskillslearning-pipeline:database`

### DTOs — see `docs/shared/patterns/dtos.md`
- [ ] Java records, `BigDecimal` for money, `Instant` for timestamps, `@Valid` constraints
- [ ] Fields match API spec exactly; per-version DTOs

### Controllers — see `docs/shared/patterns/controllers.md`
- [ ] `@Validated`, `@Valid`, constructor injection, zero business logic
- [ ] `Idempotency-Key` header on all mutating endpoints
- [ ] Consistent API versioning; deprecated endpoints use `Sunset` header

### Services — see `docs/shared/patterns/jpa-transactions.md`
- [ ] `@Transactional` on impl, `readOnly = true` on reads
- [ ] Business logic in service only; throws domain exceptions; no self-invocation

### Exception Handling — see `docs/shared/patterns/exceptions.md`
- [ ] Domain exceptions use error code enum; `@RestControllerAdvice` handles all
- [ ] No silent `catch (Exception e)`; 500 catch-all leaks no details

### Naming — see `docs/shared/patterns/naming.md`
- [ ] Controllers: `getX/createX/updateX/deleteX`; REST paths: plural nouns
- [ ] Services: `XxxService`/`XxxServiceImpl`; Mappers: `XxxMapper`
- [ ] Events: past-tense `AccountCreatedEvent`; DB tables: plural snake_case

## Architecture-Specific Checks

### Monolith with Spring Modulith (when detected)
- [ ] `ApplicationModules.of(XxxApplication.class).verify()` passes — module boundaries enforced
- [ ] Each module in its own root package: `com.company.app.orders`, `com.company.app.customers`
- [ ] Modules communicate via public API only — no cross-module internal class access
- [ ] `@ApplicationModuleListener` for inter-module events (no direct service calls between modules)
- [ ] `spring-modulith-starter-test` dependency present (required for module verification)
- [ ] Module events stored in event publication registry (`spring-modulith-starter-jpa`)
- [ ] Database tables namespaced by module prefix: `orders_*`, `customers_*`, `payments_*`

### Microservices (REST)
- [ ] Each service owns its database — no cross-service repository access
- [ ] Circuit breaker on external service calls (Resilience4j or Spring Cloud)
- [ ] OpenAPI spec present and controller implements generated interface
- [ ] Service discovery and centralized config used where configured
- [ ] No shared transactions across services

### Event-Driven Microservices
- [ ] All REST microservices checks above, plus:
- [ ] Events use past-tense verb naming: `OrderShippedEvent`, not `ShipOrderEvent`
- [ ] Idempotent consumers — duplicate events handled gracefully (event ID dedup check)
- [ ] Outbox pattern when event publication must be atomic with DB write
- [ ] Dead-letter topic configured for failed events
- [ ] Event schemas versioned (Avro / JSON Schema) if the project uses schema registry
- [ ] No tight coupling between producer and consumer — events are contracts
- [ ] No synchronous RPC disguised as async events (consumer immediately calling back to producer)

### CQRS (when detected)
- [ ] Read models separated from write models
- [ ] Commands target domain entities; queries target projections
- [ ] Read side doesn't trigger side effects
- [ ] Event handlers update read projections

### gRPC Services (when detected)
- [ ] `.proto` files in `src/main/proto/` — schema is the contract
- [ ] `@GrpcService` on server implementations extending generated `XxxImplBase`
- [ ] gRPC error handling uses `StatusException` with proper status codes (NOT_FOUND, ALREADY_EXISTS, etc.)
- [ ] Deadlines set on all gRPC client calls (`withDeadline(...)`)
- [ ] `ServerInterceptor` for auth, logging, tracing, metrics
- [ ] gRPC health check enabled (`grpc-health-service`)
- [ ] gRPC reflection enabled for debugging (`grpc-server-reflection`)
- [ ] `@GrpcClient` annotated stubs, not manually created channels

### GraphQL Services (when detected)
- [ ] `.graphqls` schema files in `src/main/resources/graphql/` — schema-first, not code-generated schema
- [ ] `@Controller` (not `@RestController`) with `@QueryMapping`/`@MutationMapping`
- [ ] `@BatchMapping` for every nested list relationship — prevents N+1
- [ ] `DataFetcherExceptionResolverAdapter` for domain exception → `GraphQLError` mapping
- [ ] `@Valid` on `@Argument` inputs
- [ ] JPA entities never exposed directly — always mapped to GraphQL DTOs
- [ ] Pagination uses Relay Connection spec (`Connection<T>`, `ConnectionCursor`)
- [ ] Rate limiting by query complexity/depth configured

### Reactive Stack (when WebFlux detected)
- [ ] `spring-boot-starter-web` and `spring-boot-starter-webflux` not both present (mixed is usually accidental)
- [ ] All controller/service return types are `Mono<T>` or `Flux<T>` — no bare `T` returns
- [ ] No `@Transactional` on reactive services (not supported in R2DBC)
- [ ] No `JpaRepository` in reactive module — use `ReactiveCrudRepository`
- [ ] No `@GeneratedValue(UUID)` on R2DBC entities — UUID assigned manually
- [ ] No `Pageable` / `Page<T>` — use `Flux<T>.skip().take()` or keyset pagination
- [ ] `@EnableR2dbcAuditing` on main class (not `@EnableJpaAuditing`)
- [ ] Reactive error handling: `.switchIfEmpty(Mono.error(...))` instead of throwing in chain
- [ ] `@WebFluxTest` + `WebTestClient` for controller tests (not `@WebMvcTest` + `MockMvc`)
- [ ] `SecurityWebFilterChain` for Spring Security (not `SecurityFilterChain`)
- [ ] `WebClient` injected as Spring bean with builder (not `RestTemplate`)
- [ ] No blocking calls inside reactive chains without `.subscribeOn(Schedulers.boundedElastic())`

### Resilience (HIGH for external calls)

See `docs/shared/patterns/resilience.md` for full Resilience4j patterns.
- [ ] All external calls: retry + timeout + circuit breaker + bulkhead
- [ ] Fallback methods defined; exponential backoff with jitter; graceful shutdown configured
- [ ] For comprehensive setup: `/devskillslearning-pipeline:resilience`

### Spring Batch (MEDIUM)
- [ ] Chunk size configured (not default Integer.MAX_VALUE)
- [ ] Reader/processor/writer are stateless and thread-safe (if multi-threaded step)
- [ ] Skip/retry limits configured with specific exception types
- [ ] Job restartability tested — restart from last committed chunk
- [ ] Batch tables (`batch_*`) exist and are migrated

### Multi-Tenancy (HIGH, if in use)
- [ ] TenantContext propagated through filters, async threads, and messaging
- [ ] Every query filtered by tenant — no cross-tenant data leaks
- [ ] `finally { TenantContext.clear() }` in every filter/middleware
- [ ] Tenant onboarding/offboarding does not affect other tenants
- [ ] Resource limits enforced per-tenant (connection pool, rate limit, queue depth)

### Redis (MEDIUM)
- [ ] Serialization uses Jackson2JsonRedisSerializer or StringRedisSerializer — not Java serialization
- [ ] Cache TTLs configured per cache region
- [ ] Connection pool tuned (Lettuce: `spring.redis.lettuce.pool.*`)
- [ ] SSL enabled for Redis connections in production

### i18n (MEDIUM)
- [ ] `MessageSource` bean defined with UTF-8 encoding
- [ ] `LocaleResolver` configured with supported locales
- [ ] Error messages use `messageSource.getMessage()` — not hardcoded English strings
- [ ] Resource bundles for all supported languages present

### Feature Flags (MEDIUM)
- [ ] Feature flags via `@ConfigurationProperties` — toggle without deploy
- [ ] Kill switch present — flag can be turned off instantly
- [ ] Percentage-based rollout uses deterministic hash (not random)
- [ ] No stale flags — cleanup plan after full rollout

### WebSocket / SSE (MEDIUM)
- [ ] Multi-instance: message broker (RabbitMQ/Redis) configured for WebSocket relay
- [ ] Authentication applied to WebSocket handshake
- [ ] Connection limits configured to prevent resource exhaustion
- [ ] Heartbeat/ping-pong configured

### Event Sourcing (MEDIUM, if in use)
- [ ] Events are immutable — never update or delete published events
- [ ] Snapshots created at regular intervals for rebuild performance
- [ ] Aggregate rebuild tested: given event history, produces correct state
- [ ] Event versioning handled (upcasters for old event formats)

### CDC / Schema Registry / CloudEvents (MEDIUM)
- [ ] Outbox table has index on `published_at` for efficient polling
- [ ] Schema registry: compatibility mode configured (BACKWARD, FORWARD, FULL)
- [ ] Schemas registered/updated in CI/CD — not manually
- [ ] CloudEvents: `type`, `source`, `id`, `time` always present
- [ ] CloudEvents: `type` uses reverse-DNS naming

## Observability Checks (MEDIUM)

See `docs/shared/patterns/observability.md` for full metrics, tracing, and alerting patterns.
- [ ] `@Slf4j` on every class; structured logging; no PII in logs
- [ ] `@Timed` on endpoints and external calls; custom business counters
- [ ] Health indicators for downstream deps; trace ID propagation
- [ ] For comprehensive review: `/devskillslearning-pipeline:monitor`, for profiling: `/devskillslearning-pipeline:perf-test`

## Test Review

For each production class, check:
- [ ] Service has unit tests (`@ExtendWith(MockitoExtension.class)`)
- [ ] Controller has web layer tests (`@WebMvcTest`)
- [ ] At least one integration test (`@SpringBootTest`)
- [ ] Happy path AND error path covered
- [ ] Edge cases: not-found, duplicate, invalid state transition, null inputs, concurrent modification
- [ ] Transaction rollback tested (verify nothing persisted on failure)

### Event-Driven Tests
- [ ] Producer tests verify correct event payload and routing key/topic
- [ ] Consumer tests verify idempotency and poison message handling
- [ ] Outbox tests verify atomicity (event published only on successful commit)
- [ ] Embedded Kafka or Testcontainers Kafka used for integration tests

## Security Checks

See `docs/shared/patterns/security.md` for full patterns (OAuth2/JWT, CORS, CSRF, rate limiting, audit logging). Key checks:

### Data Protection (BLOCKER/HIGH)
- [ ] No credentials in code/config; input validation on all request bodies; no raw SQL
- [ ] No PII/tokens in logs; `@JsonIgnore` on sensitive entity fields

### OAuth2 / JWT (HIGH)
- [ ] `SecurityFilterChain` defined; JWT issuer/audience validated; scope mapping correct
- [ ] `STATELESS` session; `permitAll()` only on health/public endpoints

### Method Security (HIGH)
- [ ] `@EnableMethodSecurity`; `@PreAuthorize` on mutating endpoints; resource ownership checked

### CORS / CSRF / Rate Limiting / Audit Logging
- [ ] CORS: explicit origins, no wildcard + credentials; CSRF disabled for stateless APIs
- [ ] Rate limits configurable via `@ConfigurationProperties`; `Retry-After` on 429
- [ ] Audit mutating operations and auth events with `AUDIT:` prefix

## Severity

| Level | Meaning |
|-------|---------|
| **BLOCKER** | Build will fail (package misplacement, missing annotation, javax/jakarta mismatch). Fix before commit. |
| **HIGH** | Breaks convention, causes runtime issues, or data corruption risk (N+1, missing transaction, cross-service DB in microservice). Fix before PR. |
| **MEDIUM** | Code smell, technical debt, missing observability. Fix in this PR or open an issue. |
| **LOW** | Style nit. Optional. |

## Report Format

Output findings as a table:

```
| Severity | File:Line | Issue | Fix |
|----------|-----------|-------|-----|
| BLOCKER  | AccountController.java:15 | javax.persistence on Spring Boot 3.x | Replace with jakarta.persistence |
| BLOCKER  | Account.java:1 | Uses @Data on entity | Replace with @Getter/@Setter/@NoArgsConstructor |
| HIGH     | AccountService.java:30 | N+1: repository call inside forEach loop | Use @EntityGraph or batch fetch |
| HIGH     | AccountService.java:42 | @Transactional self-invocation on save() | Inject self proxy or extract to separate service |
| HIGH     | AccountService.java:60 | Uses Double for monetary field balance | Change to BigDecimal |
| HIGH     | OrderService.java:30 | Cross-service DB access in microservice | Call the owning service's API instead |
| MEDIUM   | PaymentConsumer.java:45 | Consumer not idempotent | Add processed-event check before processing |
| MEDIUM   | AccountController.java:20 | Missing @Timed on endpoint | Add @Timed annotation |
| MEDIUM   | AccountService.java:55 | Cache not evicted on entity update | Add @CacheEvict("accounts") |
| LOW      | Account.java:25 | Missing @Version for optimistic locking | Add @Version Long version field |
```

## Submit Review to GitHub

If this review was for a remote PR (fetched via URL or ticket ID), submit the findings to GitHub:

### Create the Review

```
Use: mcp__plugin_github_github__pull_request_review_write
  method: create
  owner: <owner>
  repo: <repo>
  pullNumber: <number>
  event: "APPROVE"              # if no BLOCKER or HIGH issues
         "REQUEST_CHANGES"       # if any BLOCKER or HIGH issues found
         "COMMENT"               # if only MEDIUM/LOW issues
  body: |
    ## Code Review — devskillslearning-pipeline

    ### Summary
    - Files reviewed: <count>
    - BLOCKER: <count>, HIGH: <count>, MEDIUM: <count>, LOW: <count>

    ### Findings

    | Severity | File | Line | Issue | Fix |
    |----------|------|------|-------|-----|
    | ...      | ...  | ...  | ...   | ... |

    ### ✅ Strengths
    - <what was done well>

    ### 🔧 Required Changes
    <list of BLOCKER and HIGH items that must be fixed>

    ---
    🤖 Reviewed by [Claude Code](https://claude.com/claude-code) using devskillslearning-pipeline
```

### Add Inline Comments (for specific lines)

For findings that reference specific lines, add inline comments before submitting:

**Step 1**: Create a pending review (no event):
```
Use: mcp__plugin_github_github__pull_request_review_write
  method: create
  owner: <owner>
  repo: <repo>
  pullNumber: <number>
  body: "Collecting inline comments..."
```

**Step 2**: Add inline comments for each issue:
```
Use: mcp__plugin_github_github__add_comment_to_pending_review
  owner: <owner>
  repo: <repo>
  pullNumber: <number>
  path: "<relative-file-path>"
  body: "**<Severity>**: <issue description>\n\nSuggested fix: <fix>"
  line: <line-number>
  side: "RIGHT"
  subjectType: "LINE"
```

**Step 3**: Submit the pending review:
```
Use: mcp__plugin_github_github__pull_request_review_write
  method: submit_pending
  owner: <owner>
  repo: <repo>
  pullNumber: <number>
  event: "REQUEST_CHANGES"   # or "APPROVE" or "COMMENT"
  body: |
    ## Final Review Summary
    <summary text>
```

### Request Copilot Review (Optional)

```
Use: mcp__plugin_github_github__request_copilot_review
  owner: <owner>
  repo: <repo>
  pullNumber: <number>
```

---

## Auto-Fix Mode

If the user asks you to fix the issues, apply fixes in priority order: BLOCKER → HIGH → MEDIUM. After fixing, run the project's format and build commands (discovered in Step 0) to verify.

## Next Step
After code review passes, use `/devskillslearning-pipeline:secure` to harden authentication and authorization, or `/devskillslearning-pipeline:deploy` to containerize and ship.
