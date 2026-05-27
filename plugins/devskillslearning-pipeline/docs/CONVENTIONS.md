# Java/Spring Boot Best Practices — Index

Reference for AI code generation. This file is an index to the shared pattern documents in `docs/shared/`. All skills reference these canonical sources.

## How to Use This

- `docs/shared/step0-discovery.md` — universal project discovery checklist (run first, every time)
- `docs/shared/patterns/` — canonical patterns, one file per concern
- `docs/reference/api-examples.md` — full OpenAPI, AsyncAPI, gRPC, GraphQL spec examples

When a skill needs a pattern, it references the shared file and summarizes the key checks inline. The shared file is the single source of truth.

---

## Universal Rules (apply to every project)

### Discovery

**[step0-discovery.md](shared/step0-discovery.md)** — Detect build system (Maven/Gradle), Spring Boot version (2.x vs 3.x), architecture type (monolith/microservices/reactive), package layout, error handling patterns, and library presence before taking any action.

### Entities & Persistence

**[patterns/jpa-entities.md](shared/patterns/jpa-entities.md)** — Entity conventions: no `@Data`, audit fields, UUID PKs, `EnumType.STRING`, `@Version` for optimistic locking, no business logic in entities, monetary precision/scale.

**[patterns/jpa-transactions.md](shared/patterns/jpa-transactions.md)** — Transaction correctness: self-invocation detection, read-only writes, missing/overly-broad `@Transactional`, rollback semantics, propagation, read-replica routing.

**[patterns/jpa-queries.md](shared/patterns/jpa-queries.md)** — N+1 query detection and fixes: `@EntityGraph`, JOIN FETCH, `@BatchSize`, DTO projections. Caching correctness: `@Cacheable`/`@CacheEvict` patterns, self-invocation, key design.

### DTOs & Controllers

**[patterns/dtos.md](shared/patterns/dtos.md)** — DTO conventions: Java records, `BigDecimal` for money, `Instant` for timestamps, `@Valid` constraints, per-version DTOs.

**[patterns/controllers.md](shared/patterns/controllers.md)** — Controller conventions: `@Validated`, zero business logic, constructor injection, idempotency key pattern, API versioning strategy.

### Error Handling

**[patterns/exceptions.md](shared/patterns/exceptions.md)** — Domain exceptions, error code enums, `@RestControllerAdvice`, Problem Details (RFC 7807) for Spring Boot 3.x, Zalando fallback for 2.x.

### Security

**[patterns/security.md](shared/patterns/security.md)** — OAuth2 Resource Server (JWT), method-level security (`@PreAuthorize`/`@PostFilter`), CORS hardening, CSRF rules, rate limiting, audit logging, data protection.

### Resilience

**[patterns/resilience.md](shared/patterns/resilience.md)** — Resilience4j: retry with exponential backoff, circuit breaker, timeout, bulkhead, rate limiter, graceful shutdown. Pattern ordering and typed config records.

### Observability

**[patterns/observability.md](shared/patterns/observability.md)** — Structured logging, Micrometer metrics (`@Timed`, custom counters), health checks (liveness/readiness), distributed tracing, SLI/SLO definitions, Grafana dashboards, alerting rules.

### Configuration & Naming

**[patterns/configuration-props.md](shared/patterns/configuration-props.md)** — `@ConfigurationProperties` records, kebab-case prefixes, `@Validated`, `Duration` types, secrets handling, maps/lists.

**[patterns/naming.md](shared/patterns/naming.md)** — Naming conventions for Java (controllers, services, DTOs, events), database (tables, columns, indexes, constraints), and API contracts (paths, channels, scopes).

---

## Architecture-Dependent Rules

Skills auto-detect the architecture type. Default to REST microservices if ambiguous.

### Monolith
- Single deployable, shared database, direct method calls between modules
- Package by feature or layer — follow existing convention
- `@SpringBootTest` with full context for integration tests
- Transactional boundaries can span multiple domain services

**[Spring Modulith](https://docs.spring.io/spring-modulith/reference/)** — enforced module boundaries via ArchUnit (`ApplicationModules.verify()`), `@ApplicationModuleListener` for in-process events, `spring-modulith-starter-test` for verification.

### REST Microservices
- Independent deployables, per-service database, REST contracts
- OpenAPI spec per service as source of truth
- Each service owns its database exclusively — **no cross-service DB access**
- Circuit breaker on all external service calls

### Event-Driven Microservices
- All microservices rules plus async contracts
- Events use past-tense naming: `OrderShippedEvent`
- **Idempotent consumers** — handle duplicates gracefully
- Outbox pattern for atomic DB + event publication
- Dead-letter topic for failed events

### Reactive (WebFlux / R2DBC)
- `Mono<T>` / `Flux<T>` return types everywhere
- No `@Transactional` (not supported in R2DBC)
- `R2dbcRepository`, not `JpaRepository`
- `@WebFluxTest` + `WebTestClient`, not `@WebMvcTest` + `MockMvc`
- `SecurityWebFilterChain`, not `SecurityFilterChain`

### gRPC, GraphQL, Redis, Batch, Multi-Tenancy, i18n, Feature Flags, WebSocket/SSE, Event Sourcing, CDC, Schema Registry, CloudEvents

These patterns are covered in the relevant skills (`design-api`, `database`, `write-code`, `secure`, `resilience`, `monitor`, `deploy`). See each skill's implementation sections for architecture-specific guidance. Full reference content is in `docs/reference/api-examples.md` for spec examples.

---

## Database Migrations

| Aspect | Flyway | Liquibase |
|--------|--------|-----------|
| Migration location | `src/main/resources/db/migration/` | `src/main/resources/db/changelog/` |
| File naming | `V{version}__{description}.sql` | `changelog-{version}.xml` (or YAML/JSON/SQL) |
| Rollback | Document in SQL comment | Include rollback block in changeset |

- Each migration creates one table or alters one set of related columns
- Use `CREATE TABLE IF NOT EXISTS` for idempotency
- Include indexes for foreign keys and frequently queried columns
- `TIMESTAMP WITH TIME ZONE` for audit fields

---

## Project-Specific Conventions (Discovered at Runtime)

These are NOT hardcoded — discovered from the target project:

| What | How to discover |
|------|-----------------|
| Base exception class | Scan for classes extending `RuntimeException` |
| Error code enum | Scan for enums with `code`, `message`, `httpStatus` fields |
| Response wrapper | Scan controller return types for generic wrappers |
| Global exception handler | Find `@RestControllerAdvice` class |
| Module structure | Read `pom.xml` `<modules>` or `settings.gradle` |
| OpenAPI spec | Find `*.yaml`/`*.json` in `src/main/resources/openapi/` |

When nothing can be discovered (greenfield), default to Spring Boot 3.x latest stable, Java 21, Maven, Flyway, Lombok, MapStruct, Java records, UUID PKs.

---

## API Integration

See the `api-integrate` skill for: OpenAPI client generation, `RestClient`/`WebClient` setup, error mapping, webhook receivers, WireMock integration testing.

## Performance Testing

See the `perf-test` skill for: k6/Gatling load test scripts, JFR/Async Profiler profiling, database profiling (`pg_stat_statements`), capacity planning.

## Release Management

See the `release` skill for: conventional commits, semantic versioning, changelog generation (`Keep a Changelog` format), GitHub Release creation, CI automation.

## Dependency Management

See the `dependency` skill for: OWASP dependency-check scanning, Gradle version catalogs / Maven BOMs, Renovate/Dependabot configuration, transitive conflict resolution.

## GitHub Integration

See `docs/SKILL-DEVELOPMENT.md` for the skill development guide and `docs/reference/api-examples.md` for full spec examples. GitHub project management (epics, stories, PR review) is handled by the `github` skill via MCP tools.
