---
name: devskillslearning-pipeline:write-code
description: Write Java/Spring Boot implementation code following best practices. Use when the user asks to implement an endpoint, feature, or service. Auto-detects project architecture (monolith, REST microservices, event-driven), discovers conventions from the codebase, and generates controller, service, repository, entity, DTO, mapper, migration scripts, event handlers, observability, and tests as appropriate.
type: skill
---

# Write Code

You are an expert Java/Spring Boot developer implementing features. Follow the conventions discovered from the target project. When the project has no established convention, default to the best practices in `docs/CONVENTIONS.md`.

## What You Need to Provide

| Input | Required? | Example | Notes |
|-------|-----------|---------|-------|
| What to build | Yes | "Add an endpoint to create and retrieve orders" | Be as specific as possible |
| Entity/domain model | Recommended | "Order has: customerId, items, totalAmount, status" | If you have a rough idea |
| API contract | If available | Link to OpenAPI spec or describe endpoints | I can generate one otherwise |
| Business rules | Recommended | "Orders under $10 get free shipping" | Edge cases I should handle |
| Target module | Multi-module only | `:order-service` | I auto-detect for single-module |

**Minimal prompt**: "Create a CRUD REST API for orders with fields: id, customerId, items, totalAmount, status."

**I auto-discover everything else**: Spring Boot version, build system, architecture type, package layout, error handling patterns, response wrappers, migration tool, Lombok/MapStruct usage. You don't need to tell me — I read the codebase.

**For GitHub-linked work**, mention the ticket: "Implement ticket #15 from owner/repo" and I'll read the issue, understand the requirements, implement, and link the PR.

## Step 0: Discover the Project

Before writing any code, understand the target project.

### 0a. Read project-level documentation
- `CLAUDE.md` at the project root — the primary source of project conventions
- `.cursor/rules/` or `.github/copilot-instructions.md` if present

### 0b. Detect build system
- Look for `pom.xml` (Maven) or `build.gradle` / `build.gradle.kts` (Gradle)
- Check if multi-module: `<modules>` in root `pom.xml` or `include` directives in `settings.gradle`
- Note the build command and module-specific syntax for later verification

### 0c. Detect architecture type
Scan the codebase and determine:
- **Monolith**: Single deployable, shared DB, no service discovery, direct method calls between modules
- **REST Microservices**: Per-service DB, OpenAPI specs, REST clients (`@FeignClient`, `RestTemplate`, `WebClient`), service discovery
- **Event-Driven Microservices**: Message broker dependencies (Kafka, RabbitMQ), `@KafkaListener`, `StreamBridge`, event classes, outbox tables
- **gRPC services**: `grpc-spring-boot-starter` or `grpc-server-spring-boot-starter` on classpath — use `.proto` files, `@GrpcService`, protobuf stubs
- **GraphQL services**: `spring-boot-starter-graphql` on classpath — use `.graphqls` schema, `@QueryMapping`/`@MutationMapping`

Ask the user if ambiguous.

### 0d. Detect execution model
- **Servlet/Blocking** (default): `spring-boot-starter-web` on classpath — use `JpaRepository`, `@Transactional`, standard return types
- **Reactive/Non-blocking**: `spring-boot-starter-webflux` on classpath (without `spring-boot-starter-web`) — use `R2dbcRepository`, `Mono<T>`/`Flux<T>`, no `@Transactional`, `WebTestClient` for tests
- If both `web` and `webflux` starters are present, ask the user which model the project uses — mixed is unusual
- Reactive stack implications: R2DBC instead of JDBC, Netty instead of Tomcat, `ReactiveCrudRepository` instead of `JpaRepository`, manual UUID assignment instead of `@GeneratedValue`, no `Pageable` support

### 0e. Detect Spring Boot version (CRITICAL)
- Read `<version>` from `spring-boot-starter-parent` in `pom.xml`, or `springBootVersion` / plugin version in `build.gradle`
- **Spring Boot 3.x** → all imports use `jakarta.*` (`jakarta.persistence.*`, `jakarta.validation.*`, `jakarta.servlet.*`)
- **Spring Boot 2.x** → all imports use `javax.*` (`javax.persistence.*`, `javax.validation.*`, `javax.servlet.*`)
- **Spring Security 6.x** (Spring Boot 3.x) → Lambda DSL: `http.cors(c -> {}).csrf(c -> c.disable())`
- **Spring Security 5.x** (Spring Boot 2.x) → Builder DSL: `http.cors().and().csrf().disable()`
- Default to 3.x / Jakarta for greenfield projects

### 0f. Discover project conventions
- **Package root**: Find `@SpringBootApplication` class, note its package
- **Sub-package layout**: Check if the project uses package-by-layer (`*.controller`, `*.service`, etc.) or package-by-feature
- **Base exception**: Scan for classes extending `RuntimeException` used across the project
- **Error code enum**: Look for enums with `code`, `message`, `httpStatus` fields
- **Response wrapper**: Scan controller return types — is there a generic wrapper (e.g., `ApiResponse<T>`) or bare `ResponseEntity<T>`?
- **Global exception handler**: Find `@RestControllerAdvice` class
- **Migration tool**: Check for `flyway-core` or `liquibase-core` in dependencies
- **MapStruct usage**: Check if `@Mapper(componentModel = "spring")` exists in the codebase
- **Lombok usage**: Check if Lombok annotations are used or if explicit code is preferred
- **Java version**: From `pom.xml` `<java.version>` or `build.gradle` `sourceCompatibility`
- **Observability stack**: Check for Micrometer, Sleuth, OpenTelemetry dependencies

### 0g. Locate API contracts (if any)
- OpenAPI specs: search for `*.yaml`, `*.json` in `src/main/resources/openapi/` or `api/` directories
- Generated interfaces: check `target/generated-sources/openapi/` or build plugin config
- Async API specs (event-driven projects): search for `asyncapi.yaml` or event schema files
- If no API specs exist, the skill works from user descriptions and applies REST best practices

### 0h. Understand the target service/module
- Read existing code in the module's `controller/`, `service/`, `repository/`, `entity/` packages
- Note the patterns already in use — match them
- If the module is new/empty, establish conventions consistent with sibling modules

### 0i. Discovery Fallback — Greenfield Projects

If the project is brand new (no `@SpringBootApplication`, no entities, no controllers):

1. **Do not error out** — bootstrap the project structure first
2. **Establish conventions before implementing features** (see Step 1b)
3. **Assume sensible defaults** and state them to the user:
   - Spring Boot 3.x (Jakarta)
   - Maven if `pom.xml` exists, else ask Maven vs Gradle
   - Flyway for migrations
   - Lombok + MapStruct for boilerplate reduction
   - Java records for DTOs
   - UUID PKs with `GenerationType.UUID`
   - Package-by-layer layout
4. **Create a minimal `CLAUDE.md`** documenting the decisions so future invocations stay consistent

## Step 1: Bootstrapping and Scope

### 1a. Determine what to build

Based on what the user asked for and what was discovered:
- Single endpoint? → full stack for that endpoint
- New entity/aggregate? → entity + migration + repository + service + controller + mapper + DTOs
- New feature spanning multiple entities? → all layers for all affected endpoints
- Event producer/consumer? → event class + producer/consumer + outbox if transactional
- CQRS read model? → query service + projection + controller (optional)
- Brand new project? → see Step 1b

If OpenAPI specs exist, the spec is the **source of truth**. Controllers implement the generated interface.

### 1b. Bootstrap a greenfield project (when 0h triggered)

Before implementing any feature, create these foundation files:

1. **Build file** with required dependencies (Spring Boot starter parent, web, data-jpa, validation, actuator, Flyway/Liquibase, Postgres driver, Lombok, MapStruct, Testcontainers for tests)
2. **Application config** (`application.yml`): datasource, Flyway/Liquibase, server port, actuator endpoints, logging level
3. **Main class** (`@SpringBootApplication` + `@EnableJpaAuditing`)
4. **Base exception class** extending `RuntimeException` with an `ErrorCode` field
5. **Error code enum** with at minimum: `RESOURCE_NOT_FOUND`, `CONFLICT`, `BAD_REQUEST`, `INTERNAL_ERROR`
6. **Response wrapper** (`ApiResponse<T>`) with `status`, `message`, `data`, `timestamp`
7. **Global exception handler** (`@RestControllerAdvice`) mapping error codes to HTTP statuses
8. **Health indicator** for critical downstream dependencies

Then proceed with feature implementation.

## Step 2: Implement Bottom-Up

Build in dependency order — each layer depends on the one before.

### 2a. Entity (`entity/` or discovered package)

```java
// Spring Boot 3.x (jakarta.*)
@Entity
@Table(name = "accounts")
@Getter
@Setter
@NoArgsConstructor
public class Account {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(nullable = false, unique = true)
    private String accountNumber;

    @Enumerated(EnumType.STRING)
    private AccountType accountType;

    @Column(nullable = false, precision = 19, scale = 4)
    private BigDecimal balance;

    @CreatedDate
    @Column(updatable = false)
    private Instant createdAt;

    @LastModifiedDate
    private Instant updatedAt;

    @Version
    private Long version;
}
```

For Spring Boot 2.x, replace `jakarta.persistence.*` with `javax.persistence.*`.

Rules:
- `@Getter` + `@Setter` + `@NoArgsConstructor` individually (or `@Getter` + `@NoArgsConstructor` for read-only). Never `@Data`.
- Table name: plural snake_case (`@Table(name = "accounts")`)
- Audit fields on every entity: `createdAt`, `updatedAt` with `@CreatedDate` / `@LastModifiedDate`
- Add `@Version` for optimistic locking on entities that may experience concurrent updates
- `@Enumerated(EnumType.STRING)` for all enums
- UUID PK with `GenerationType.UUID` (or `GenerationType.IDENTITY` for MySQL)
- `BigDecimal` with explicit `precision` and `scale` for monetary columns
- No business logic in entities

**Reactive variant (R2DBC)**: Identical entity class, but `@GeneratedValue(UUID)` is NOT supported in R2DBC. Assign UUID manually before save: `entity.setId(UUID.randomUUID())`. Use `@Id` without `@GeneratedValue`. Use `@CreatedDate` + `@EnableR2dbcAuditing` (same annotations, different auditing enabler).

### 2b. Database Migration (ALWAYS — right after entity)

Generate the migration script alongside the entity. Auto-detect the tool:

**Flyway** — `src/main/resources/db/migration/V{next}__create_{table_name}.sql`:
```sql
CREATE TABLE IF NOT EXISTS accounts (
    id UUID NOT NULL,
    account_number VARCHAR(50) NOT NULL,
    account_type VARCHAR(20) NOT NULL,
    balance NUMERIC(19,4) NOT NULL DEFAULT 0,
    customer_id UUID NOT NULL,
    status VARCHAR(20) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (id),
    CONSTRAINT uq_accounts_account_number UNIQUE (account_number)
);

CREATE INDEX idx_accounts_customer_id ON accounts(customer_id);
CREATE INDEX idx_accounts_status ON accounts(status);
-- Rollback: DROP TABLE IF EXISTS accounts CASCADE;
```

**Liquibase** — add a changeset to `db/changelog/db.changelog-master.yaml`:
```yaml
- changeSet:
    id: {next-id}
    author: ai-generated
    changes:
      - createTable:
          tableName: accounts
          columns:
            - column: { name: id, type: UUID, constraints: { primaryKey: true } }
            - column: { name: account_number, type: VARCHAR(50), constraints: { nullable: false, unique: true } }
            # ...
    rollback:
      - dropTable: { tableName: accounts }
```

**If neither tool is configured**: default to Flyway, generate the SQL, and tell the user to add `flyway-core` + `flyway-database-postgresql` (or the appropriate DB variant) to the build file.

Rules:
- Each migration creates one table or alters one set of related columns
- Include indexes for foreign keys and frequently queried columns
- Use `CREATE TABLE IF NOT EXISTS` for idempotency
- Always document the rollback (Flyway: comment; Liquibase: `<rollback>` block)
- `TIMESTAMP WITH TIME ZONE` for audit fields — never `TIMESTAMP WITHOUT TIME ZONE`

### 2c. Repository (`repository/`)

```java
@Repository
public interface AccountRepository extends JpaRepository<Account, UUID> {
    Optional<Account> findByAccountNumber(String accountNumber);
    Page<Account> findByCustomerId(UUID customerId, Pageable pageable);
    boolean existsByCustomerId(UUID customerId);

    // For N+1 prevention: use @EntityGraph or JOIN FETCH
    @EntityGraph(attributePaths = {"customer"})
    Optional<Account> findWithCustomerById(UUID id);
}
```

Rules:
- Extends `JpaRepository<Entity, UUID>`, annotated `@Repository`
- `Pageable` for list queries, derived query methods for lookups
- Use `@EntityGraph` or `@Query` with JOIN FETCH for eager-loading relationships — prevent N+1
- In CQRS read side: can use custom `@Query` with projections or native SQL for performance
- `@Query` methods for complex queries with explicit JPQL, never string concatenation

**Reactive variant**: Use `ReactiveCrudRepository<Entity, UUID>` instead of `JpaRepository`. Return types: `Mono<T>` for single lookups, `Flux<T>` for collections. No `Pageable` — use `Flux<T>.skip().take()` or keyset pagination.

### 2d. DTO (`dto/`)

Use Java **records** for DTOs:

```java
public record AccountResponse(
    UUID id,
    String accountNumber,
    AccountType accountType,
    BigDecimal balance,
    UUID customerId,
    AccountStatus status,
    Instant createdAt,
    Instant updatedAt
) {}

public record CreateAccountRequest(
    @NotNull AccountType accountType,
    @Size(max = 200) String branchAddress,
    @NotNull UUID customerId
) {}

public record AccountPage(
    List<AccountResponse> content,
    int page,
    int size,
    long totalElements,
    int totalPages
) {}
```

Rules:
- Records for DTOs (immutable); classes only when mutability is required
- `@NotNull`, `@Valid`, `@Size`, `@Positive`, `@NotBlank`, `@Email` on request DTOs
- Match API schema fields exactly (OpenAPI spec if present, user description otherwise)
- `BigDecimal` for monetary values — never `Double` or `float`
- `Instant` for timestamps, not `Date`

### 2e. Mapper (`mapper/` — if MapStruct is in use)

```java
@Mapper(componentModel = "spring")
public interface AccountMapper {
    AccountResponse toResponse(Account entity);
    List<AccountResponse> toResponseList(List<Account> entities);
    Account toEntity(CreateAccountRequest request);
    void updateEntity(@MappingTarget Account entity, UpdateAccountRequest request);
}
```

If MapStruct is not on the classpath, write a manual mapper class or add mapping methods directly in the service. If the project is greenfield, use MapStruct.

### 2f. Service Interface (`service/`)

```java
public interface AccountService {
    AccountResponse createAccount(CreateAccountRequest request);
    AccountResponse getAccount(UUID id);
    AccountPage listAccounts(int page, int size, String sort);
    AccountResponse updateAccount(UUID id, UpdateAccountRequest request);
    void closeAccount(UUID id);
}
```

Design service interfaces around aggregates. One interface per aggregate.

### 2g. Service Implementation (`service/impl/`)

```java
@Service
@RequiredArgsConstructor
@Transactional
@Slf4j
public class AccountServiceImpl implements AccountService {
    private final AccountRepository repository;
    private final AccountMapper mapper;
    private final MeterRegistry meterRegistry;  // if Micrometer is on classpath

    @Override
    @Transactional(readOnly = true)
    public AccountResponse getAccount(UUID id) {
        return repository.findById(id)
            .map(mapper::toResponse)
            .orElseThrow(() -> new ResourceNotFoundException(ErrorCode.RESOURCE_NOT_FOUND, "Account not found: " + id));
    }

    @Override
    @Timed(value = "accounts.create", histogram = true, percentiles = {0.5, 0.95, 0.99})
    public AccountResponse createAccount(CreateAccountRequest request) {
        if (repository.existsByAccountNumber(request.accountNumber())) {
            throw new ConflictException(ErrorCode.CONFLICT, "Account already exists");
        }
        var entity = mapper.toEntity(request);
        entity.setAccountNumber(generateAccountNumber());
        entity.setBalance(BigDecimal.ZERO);
        entity.setStatus(AccountStatus.ACTIVE);
        var saved = repository.save(entity);

        // Observability: increment counter
        if (meterRegistry != null) {
            meterRegistry.counter("accounts.created", "type", request.accountType().name()).increment();
        }

        log.info("Account created: id={}, type={}", saved.getId(), saved.getAccountType());
        return mapper.toResponse(saved);
    }

    // Event-driven: emit event after save (outbox or StreamBridge)
}
```

Rules:
- Constructor injection via `@RequiredArgsConstructor` or explicit constructor
- `@Transactional` on class, `@Transactional(readOnly = true)` on read methods
- `@Transactional` on write methods that need specific isolation or timeout
- Business logic ONLY in service — never in controller
- Throw domain exceptions using the project's error code enum
- Validate business rules: balance checks, status transitions, uniqueness, etc.
- `@Timed` on methods that call external systems or are latency-sensitive
- Structured logging with `@Slf4j`: `log.info("message {}", value)` — never string concatenation
- Counters for significant business events (entity created, status changed)

**Reactive variant**: No `@Transactional` (not supported in R2DBC). Use `Mono<AccountResponse>` return types. Use reactive operators: `.flatMap()`, `.switchIfEmpty()`, `.onErrorMap()`. Wrap blocking meterRegistry in `Mono.fromRunnable()`. Assign UUID manually before save: `entity.setId(UUID.randomUUID())`.

**Event-driven addition** — If the operation must publish an event:

Use outbox pattern for guaranteed delivery:
```java
// Save entity + outbox event in same transaction
repository.save(entity);
outboxRepository.save(new OutboxEvent("account-created", eventPayload));
// Outbox processor publishes to Kafka asynchronously
```

Or StreamBridge for non-transactional fire-and-forget:
```java
streamBridge.send("account-created-out-0", event);
```

### 2h. Controller (`controller/`)

If OpenAPI-generated interfaces exist, the controller implements one:

```java
@RestController
@RequiredArgsConstructor
@Validated
@Slf4j
public class AccountController implements AccountsApi {
    private final AccountService service;

    @Override
    @Timed(value = "accounts.create.http", histogram = true)
    public ResponseEntity<ApiResponse<AccountResponse>> createAccount(
            @Valid @RequestBody CreateAccountRequest request) {
        log.info("Creating account: type={}", request.accountType());
        var result = service.createAccount(request);
        return ResponseEntity.status(HttpStatus.CREATED)
            .body(ApiResponse.success(result));
    }
}
```

If no generated interfaces, define endpoints directly:

```java
@RestController
@RequestMapping("/api/v1/accounts")
@RequiredArgsConstructor
@Validated
@Slf4j
public class AccountController {
    private final AccountService service;

    @PostMapping
    @Timed(value = "accounts.create.http", histogram = true)
    public ResponseEntity<ApiResponse<AccountResponse>> createAccount(
            @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
            @Valid @RequestBody CreateAccountRequest request) {
        log.info("Creating account: type={}, idempotencyKey={}", request.accountType(), idempotencyKey);
        var result = service.createAccount(idempotencyKey, request);
        var response = ResponseEntity.status(HttpStatus.CREATED)
            .body(ApiResponse.success(result));
        if (result.replayed()) {
            response.getHeaders().add("Idempotency-Replayed", "true");
        }
        return response;
    }

    @GetMapping("/{id}")
    public ResponseEntity<ApiResponse<AccountResponse>> getAccount(@PathVariable UUID id) {
        return ResponseEntity.ok(ApiResponse.success(service.getAccount(id)));
    }
}
```

Rules:
- Implements generated API interface when it exists
- `@Validated` on class, `@Valid` on request bodies
- Constructor injection only
- Zero business logic — validate input, delegate, wrap and return
- Wrap in the project's response wrapper (discovered) or `ResponseEntity<T>`
- `@Timed` on every endpoint
- Structured logging at request boundaries (sanitize payloads — no PII, no request bodies)
- **Idempotency key** on mutating endpoints (POST/PUT/PATCH): accept `Idempotency-Key` header, delegate to service for dedup, return `Idempotency-Replayed: true` header on replayed responses

### 2i. Exception Handling (`exception/`)

```java
@RestControllerAdvice
@Slf4j
public class ServiceExceptionHandler extends GlobalExceptionHandler {
    // Base class handles common exceptions (ResourceNotFoundException, ConflictException, etc.)

    @ExceptionHandler(IllegalStateException.class)
    public ResponseEntity<ApiResponse<Void>> handleIllegalState(IllegalStateException ex) {
        log.error("Illegal state: {}", ex.getMessage(), ex);
        return ResponseEntity.status(HttpStatus.CONFLICT)
            .body(ApiResponse.error(ErrorCode.CONFLICT, ex.getMessage()));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiResponse<Void>> handleUnexpected(Exception ex) {
        log.error("Unexpected error", ex);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
            .body(ApiResponse.error(ErrorCode.INTERNAL_ERROR, "An unexpected error occurred"));
    }
}
```

If no base handler exists, create a standalone `@RestControllerAdvice` that:
- Maps domain exceptions to appropriate HTTP status codes
- Returns errors using the project's error code enum
- Includes a catch-all for unexpected exceptions (500)
- Logs full stack trace at ERROR for unexpected exceptions, WARN for expected domain exceptions

### 2j. Event Handlers (event-driven projects only)

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class AccountEventConsumer {
    private final SomeService service;

    @Bean
    public Consumer<AccountCreatedEvent> accountCreated() {
        return event -> {
            log.info("Consuming AccountCreatedEvent: accountId={}", event.accountId());
            // Idempotency check
            if (service.isEventProcessed(event.eventId())) {
                log.warn("Duplicate event ignored: eventId={}", event.eventId());
                return;
            }
            service.handleAccountCreated(event);
            log.info("Processed AccountCreatedEvent: eventId={}", event.eventId());
        };
    }
}
```

Or with `@KafkaListener` if the project uses that pattern.

Rules:
- Idempotent consumers — check if event was already processed before acting
- Dead-letter handling for poison messages (configure in binder or listener error handler)
- Consumer maps to a single responsibility
- Structured logging with event ID for traceability

### 2k. Observability Instrumentation

Every new class should include basic instrumentation. **For comprehensive observability (Prometheus, Grafana, distributed tracing, alerting, SLI/SLO definitions), use `/devskillslearning-pipeline:monitor`** — the monitor skill handles the full production observability stack. This section covers the minimum instrumentation every class needs.

Every new class should include:

- **`@Slf4j`** on all classes (or `LoggerFactory.getLogger(Xxx.class)` if Lombok not in use)
- **`@Timed`** on controllers (every endpoint) and service methods that call external systems
- **Custom counters** for business events: `meterRegistry.counter("name", "tag", value).increment()`
- **Health indicator** if the service depends on an external system not already covered by actuator auto-configuration:

```java
@Component
public class DownstreamServiceHealthIndicator implements HealthIndicator {
    private final DownstreamClient client;

    @Override
    public Health health() {
        try {
            client.ping();
            return Health.up().withDetail("latency", /* ms */).build();
        } catch (Exception e) {
            return Health.down().withException(e).build();
        }
    }
}
```

### 2l. Configuration Properties (`config/`)

When the feature needs externalized configuration (timeouts, retry settings, feature flags, external URLs, rate limits), generate a typed `@ConfigurationProperties` class alongside the `application.yml` block. Never use `@Value` scattered across the codebase.

**Spring Boot 3.x** (Jakarta, records — no `@ConstructorBinding` needed):
```java
package com.<company>.<artifact>.config;

import jakarta.validation.constraints.Positive;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;
import java.time.Duration;
import java.util.Set;

@Validated
@ConfigurationProperties(prefix = "orders.retry")
public record OrderRetryConfig(
    @Positive int maxAttempts,
    Duration backoff,
    Set<String> retryableStatuses
) {}
```

**Spring Boot 2.x** (Javax — requires `@ConstructorBinding` on record):
```java
import javax.validation.constraints.Positive;
import org.springframework.boot.context.properties.ConstructorBinding;

@Validated
@ConstructorBinding
@ConfigurationProperties(prefix = "orders.retry")
public record OrderRetryConfig(
    @Positive int maxAttempts,
    Duration backoff,
    Set<String> retryableStatuses
) {}
```

**Corresponding `application.yml` block:**
```yaml
orders:
  retry:
    max-attempts: 3
    backoff: 2s
    retryable-statuses:
      - SERVICE_UNAVAILABLE
      - GATEWAY_TIMEOUT
```

Rules:
- **Records for config properties** (immutable by design, perfect fit)
- `@Validated` on the class — activates validation annotations
- `@Positive`, `@NotNull`, `@DurationMin`, `@NotEmpty` on fields
- Prefix in **kebab-case** matching the YAML structure
- `@ConfigurationPropertiesScan` on the main class (or `@EnableConfigurationProperties` on the consuming config)
- Inject via constructor — never use `@Value` for grouped configuration
- Place in `*.config` package
- For nested/map config: use nested records, e.g., `Map<String, NestedServiceConfig> clients`

**When to generate:**
- External service calls → generate client config (base URL, timeout, retry)
- Feature toggles → generate feature config
- Rate limiting → generate rate limit config
- Business parameters (thresholds, limits) → generate business config

**Injecting into service:**
```java
@Service
@RequiredArgsConstructor
public class OrderServiceImpl implements OrderService {
    private final OrderRetryConfig retryConfig;
    // use retryConfig.maxAttempts(), retryConfig.backoff(), etc.
}
```

## Step 3: Write Tests

Adapt to what the project uses. Discover from existing tests:

### 3a. Unit Tests
```java
@ExtendWith(MockitoExtension.class)
class AccountServiceImplTest {
    @Mock private AccountRepository repository;
    @Mock private AccountMapper mapper;
    @Mock private MeterRegistry meterRegistry;
    @InjectMocks private AccountServiceImpl service;

    @Test
    void shouldCreateAccount() { /* arrange, act, assert */ }

    @Test
    void shouldThrowWhenAccountAlreadyExists() { /* ... */ }

    @Test
    void shouldThrowWhenInvalidStateTransition() { /* ... */ }

    @Test
    void shouldHandleNullInput() { /* ... */ }
}
```

### 3b. Web Layer Tests
```java
@WebMvcTest(AccountController.class)
class AccountControllerTest {
    @Autowired private MockMvc mockMvc;
    @MockBean private AccountService service;

    @Test
    void shouldReturnAccount() throws Exception {
        when(service.getAccount(any())).thenReturn(response);
        mockMvc.perform(get("/api/v1/accounts/{id}", UUID.randomUUID()))
            .andExpect(status().isOk());
    }

    @Test
    void shouldReturn404WhenNotFound() throws Exception {
        when(service.getAccount(any()))
            .thenThrow(new ResourceNotFoundException(ErrorCode.RESOURCE_NOT_FOUND, "Not found"));
        mockMvc.perform(get("/api/v1/accounts/{id}", UUID.randomUUID()))
            .andExpect(status().isNotFound());
    }

    @Test
    void shouldReturn400OnInvalidRequest() throws Exception {
        mockMvc.perform(post("/api/v1/accounts")
            .contentType(MediaType.APPLICATION_JSON)
            .content("{}"))
            .andExpect(status().isBadRequest());
    }
}
```

### 3c. Integration Tests
```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Testcontainers
class AccountIntegrationTest {
    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
    }
}
```

### 3d. Event-Driven Tests
- Embedded Kafka or Testcontainers Kafka module for integration tests
- `@MockBean StreamBridge` or `@MockBean KafkaTemplate` for unit-level producer testing
- Verify events are published with correct payload, key, and topic
- Test idempotency by sending duplicate events
- Test dead-letter behavior for poison messages

## Step 4: Verify

Run the project's build command (discovered in Step 0b):

```sh
# Maven single-module
mvn clean verify

# Maven multi-module (specific module)
mvn clean verify -pl :module-name

# Gradle single-module
./gradlew build

# Gradle multi-module
./gradlew :module-name:build
```

If the project uses Spotless, run formatting first:
```sh
mvn spotless:apply
# or
./gradlew spotlessApply
```

## Checklist

Before finishing, verify:
- [ ] Spring Boot version detected and correct import prefix used (jakarta vs javax)
- [ ] Architecture type correctly detected and appropriate patterns applied
- [ ] Package structure matches existing conventions
- [ ] Database migration generated alongside entity (Flyway or Liquibase)
- [ ] Indexes created for foreign keys and frequently queried columns
- [ ] Constructor injection on all classes (if Lombok: `@RequiredArgsConstructor`)
- [ ] `@Transactional(readOnly = true)` on read methods, `@Transactional` on writes
- [ ] `@Version` on entities susceptible to concurrent updates
- [ ] Project's error code enum used (not ad-hoc strings)
- [ ] Project's response wrapper used (or `ResponseEntity<T>`)
- [ ] `BigDecimal` for money, not `Double`
- [ ] Audit fields on entities (`createdAt`, `updatedAt`)
- [ ] Records for DTOs
- [ ] No `@Data` on entities
- [ ] No business logic in controllers
- [ ] If OpenAPI: controller implements generated interface
- [ ] If event-driven: events published/consumed correctly, outbox if transactional, idempotent consumers
- [ ] If CQRS: read/write paths separated
- [ ] Observability: `@Slf4j` on all classes, `@Timed` on endpoints and external calls, business counters
- [ ] Health indicator for critical downstream dependencies
- [ ] Tests cover happy path AND error cases (not-found, conflict, invalid input, null input)
- [ ] Build passes

## Next Step
After implementing, use `/devskillslearning-pipeline:code-review` to review the code against 100+ architectural and security checks, or `/devskillslearning-pipeline:write-tests` to add comprehensive test coverage.
