# Java/Spring Boot Best Practices

Reference for AI code generation. These rules are enforced by the `write-code` and `code-review` skills.

Rules are organized in three tiers:
- **Universal** — always apply, regardless of project type
- **Architecture-dependent** — apply based on detected project architecture
- **Project-specific** — discovered at runtime from the target codebase

---

## Universal Rules

These apply to every Java/Spring Boot project.

### Dependency Injection

- Constructor injection always — no `@Autowired` on fields.
- No setter injection for required dependencies.
- Use `@RequiredArgsConstructor` (Lombok) or explicit constructors.

### Entities

- `@Getter` + `@Setter` + `@NoArgsConstructor` individually — never `@Data` on JPA entities.
- Audit fields on every entity: `createdAt`, `updatedAt` (use `@CreatedDate` / `@LastModifiedDate` with `@EnableJpaAuditing`).
- UUID primary keys with `GenerationType.UUID` (preferred) or `GenerationType.IDENTITY` for MySQL.
- `@Enumerated(EnumType.STRING)` for all enum fields.
- No business logic in entities (no `@Transactional`, no service calls).

### DTOs

- Java **records** for DTOs unless mutability is required.
- `BigDecimal` for monetary values — never `Double` or `float`.
- `@NotNull`, `@Valid` on request DTO fields.
- Instant for timestamps, not Date.

### Controllers

- `@Validated` on controller class, `@Valid` on request bodies.
- Zero business logic — validate input, delegate to service, return response.
- Constructor injection only.
- **Idempotency key** for POST/PUT/PATCH that mutate state: accept `Idempotency-Key` header, deduplicate server-side, return `409 Conflict` on conflicting keys with different bodies.

#### Idempotency Key Pattern

For mutating endpoints (POST, PUT, PATCH), support safe retries with an idempotency key:

```
Client: POST /api/v1/orders  with  Idempotency-Key: abc-123
Server: Processes request, stores (key → response) mapping
Client: Same request again (network timeout retry)
Server: Returns cached response, does NOT process twice
```

Rules:
- Accept `Idempotency-Key: <UUID>` header on mutating endpoints
- Store mapping: `idempotency_key → (status, response_body_hash)` with TTL (24h)
- First request: process, store response, return `201`/`200`
- Duplicate with same body hash: return stored response (same status code), no side effects
- Duplicate with different body: return `422 Unprocessable Entity`
- Concurrent requests with same key: one wins, others get `409 Conflict`
- Add `Idempotency-Replayed: true` response header when returning a cached response
- Clean up expired keys via scheduled job or TTL index

### Services

- `@Transactional` on implementation class.
- Business logic in service layer only — never in controllers.
- One service interface per aggregate.

### Error Handling

- Domain exceptions extend a project base exception (or `RuntimeException` if none exists).
- Use an error code enum for consistent error categorization — never ad-hoc strings.
- `@RestControllerAdvice` handles all domain exceptions centrally.
- Never `catch (Exception e)` that swallows silently.

#### Problem Details (RFC 7807) — Spring Boot 3.x

Spring Boot 3.x has built-in `ProblemDetail` support. Prefer this over custom error response classes for 3.x projects:

```java
@RestControllerAdvice
@Slf4j
public class GlobalExceptionHandler {

    @ExceptionHandler(ResourceNotFoundException.class)
    public ProblemDetail handleNotFound(ResourceNotFoundException ex) {
        var problem = ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, ex.getMessage());
        problem.setTitle("Resource Not Found");
        problem.setProperty("errorCode", ex.getErrorCode().name());
        problem.setProperty("timestamp", Instant.now());
        return problem;
    }

    @ExceptionHandler(ConflictException.class)
    public ProblemDetail handleConflict(ConflictException ex) {
        var problem = ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT, ex.getMessage());
        problem.setTitle("Conflict");
        problem.setProperty("errorCode", ex.getErrorCode().name());
        problem.setProperty("timestamp", Instant.now());
        return problem;
    }

    @ExceptionHandler(Exception.class)
    public ProblemDetail handleUnexpected(Exception ex) {
        log.error("Unexpected error", ex);
        var problem = ProblemDetail.forStatusAndDetail(
            HttpStatus.INTERNAL_SERVER_ERROR, "An unexpected error occurred");
        problem.setTitle("Internal Server Error");
        problem.setProperty("timestamp", Instant.now());
        return problem;
    }
}
```

This produces standardized responses:
```json
{
    "type": "about:blank",
    "title": "Resource Not Found",
    "status": 404,
    "detail": "Order not found: abc-123",
    "instance": "/api/v1/orders/abc-123",
    "errorCode": "RESOURCE_NOT_FOUND",
    "timestamp": "2026-05-15T10:30:00Z"
}
```

Rules:
- `ProblemDetail.forStatusAndDetail(status, detail)` as factory — never construct manually
- Add custom properties with `problem.setProperty("key", value)` — they appear alongside standard fields
- `type` field: use `about:blank` (default) or a custom URI pointing to error documentation
- `instance` field: set to the request path for traceability
- For Spring Boot 2.x: use `zalando/problem-spring-web` library or stick with custom `ApiResponse`
- Validation errors (400): use `ErrorResponse.builder()` with `BindingResult` errors
- Always `log.error()` for 500s, `log.warn()` for 4xx expected errors — never log stack traces for client errors

### Naming

### Naming

| What | Convention |
|------|-----------|
| Controller methods | `getX`, `createX`, `updateX`, `deleteX` |
| REST paths | Plural nouns |
| DB tables | Plural snake_case |
| Service interface | `XxxService` |
| Service impl | `XxxServiceImpl` |
| Mapper (MapStruct) | `XxxMapper` |

### Configuration Properties

Type-safe configuration using `@ConfigurationProperties` — never scatter `@Value` across the codebase.

- Use Java **records** for `@ConfigurationProperties` (Spring Boot 3.x auto-detects, no `@ConstructorBinding` needed):
```java
@ConfigurationProperties(prefix = "orders.retry")
public record OrderRetryConfig(
    @Positive int maxAttempts,
    @DurationMin(seconds = 1) Duration backoff,
    Set<HttpStatus> retryableStatuses
) {}
```
- For Spring Boot 2.x, add `@ConstructorBinding` on the record or constructor.
- `@Validated` on the properties class, standard validation annotations on fields.
- Prefix always uses **kebab-case** (`orders.retry`, not `ordersRetry` or `orders_retry`).
- Inject `@ConfigurationProperties` beans via constructor — never use `@Value` except for one-off values.
- Register with `@ConfigurationPropertiesScan` on `@SpringBootApplication` (or `@EnableConfigurationProperties(XxxConfig.class)` on the consuming `@Configuration`).
- For maps/lists: `Map<String, ServiceConfig> services` with `ServiceConfig` as a nested record.
- Place in `*.config` package.

### Security

#### Data Protection
- No credentials or secrets in code or config files. Use `spring-config-encrypt`, Vault, or K8s Secrets.
- Input validation on all request bodies.
- No raw SQL (use JPQL, Criteria API, or named queries).
- Sanitize user input in log messages — never log request bodies, tokens, or PII.
- `@JsonIgnore` on sensitive entity fields (passwords, tokens, SSN).

#### OAuth2 Resource Server (JWT)

Standard pattern for securing REST APIs:

```java
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        return http
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/actuator/health/**", "/api/v1/health").permitAll()
                .requestMatchers(HttpMethod.GET, "/api/v1/**").hasAuthority("SCOPE_read")
                .requestMatchers(HttpMethod.POST, "/api/v1/**").hasAuthority("SCOPE_write")
                .requestMatchers(HttpMethod.PUT, "/api/v1/**").hasAuthority("SCOPE_write")
                .requestMatchers(HttpMethod.DELETE, "/api/v1/**").hasAuthority("SCOPE_admin")
                .anyRequest().authenticated()
            )
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt.jwtAuthenticationConverter(jwtAuthenticationConverter()))
            )
            .sessionManagement(session -> session.sessionCreationPolicy(STATELESS))
            .csrf(csrf -> csrf.disable())  // stateless APIs only
            .cors(cors -> cors.configurationSource(corsConfigurationSource()))
            .build();
    }

    private JwtAuthenticationConverter jwtAuthenticationConverter() {
        var converter = new JwtAuthenticationConverter();
        converter.setJwtGrantedAuthoritiesConverter(jwt -> {
            var claims = jwt.getClaimAsStringList("scope");
            return claims.stream()
                .map(scope -> new SimpleGrantedAuthority("SCOPE_" + scope))
                .collect(Collectors.toSet());
        });
        return converter;
    }
}
```

**Spring Boot 2.x**: Replace `oauth2ResourceServer(oauth2 -> oauth2.jwt(...))` with `oauth2ResourceServer(OAuth2ResourceServerConfigurer::jwt)`. Replace `csrf(csrf -> csrf.disable())` with `csrf().disable()`.

Rules:
- Stateless (no `HttpSession`) for REST APIs — tokens carry all context
- Validate `iss` (issuer), `aud` (audience), and `exp` (expiration) via `spring.security.oauth2.resourceserver.jwt.*` properties
- Map scopes/permissions correctly from JWT claims to `GrantedAuthority`
- Never accept tokens without signature verification
- `permitAll()` only for health endpoints and public endpoints — everything else authenticated by default
- Use HTTPS everywhere — enforce in production via redirect or HSTS

#### Method-Level Security

```java
@RestController
public class OrderController {

    @PreAuthorize("hasAuthority('SCOPE_write') and #request.customerId == authentication.principal.claims['sub']")
    @PostMapping
    public ResponseEntity<...> createOrder(@Valid @RequestBody CreateOrderRequest request) { ... }

    @PreAuthorize("hasAuthority('SCOPE_admin') or @orderSecurity.isOwner(#id, authentication)")
    @GetMapping("/{id}")
    public ResponseEntity<...> getOrder(@PathVariable UUID id) { ... }

    @PostFilter("filterObject.customerId == authentication.principal.claims['sub']")
    @GetMapping
    public List<OrderResponse> listOrders() { ... }
}
```

Rules:
- `@PreAuthorize` on mutating endpoints and endpoints returning sensitive data
- `@PostFilter` for filtering collection results to only authorized records
- Complex rules extracted to `@Component` beans (e.g., `@orderSecurity` SpEL bean)
- Always use `hasAuthority` / `hasRole` — never rely solely on path-based security

#### Keycloak Integration

For projects using Keycloak as IdP:

```yaml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: ${KEYCLOAK_ISSUER_URI:http://localhost:8080/realms/my-realm}
          jwk-set-uri: ${KEYCLOAK_ISSUER_URI:http://localhost:8080/realms/my-realm}/protocol/openid-connect/certs
```

- Use realm roles for coarse-grained access, client roles for fine-grained
- Configure `KeycloakJwtAuthenticationConverter` if using Keycloak's custom claim format
- Use Keycloak Admin Client for programmatic user/role management
- Test with `@WithMockUser` or Testcontainers Keycloak module

#### API Key Auth (Machine-to-Machine)

For service-to-service communication without user context:

```java
@Component
public class ApiKeyAuthFilter extends OncePerRequestFilter {
    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                     FilterChain chain) throws ServletException, IOException {
        var apiKey = request.getHeader("X-API-Key");
        if (apiKey != null && apiKeyValidator.isValid(apiKey)) {
            SecurityContextHolder.getContext().setAuthentication(
                new PreAuthenticatedAuthenticationToken(apiKey, null, apiKeyValidator.getAuthorities(apiKey))
            );
        }
        chain.doFilter(request, response);
    }
}
```

Rules:
- API keys stored hashed (bcrypt) in DB or Vault — never plaintext
- API keys scoped to specific services with limited permissions
- Rotate keys regularly; support key revocation

#### CORS Hardening

```java
@Bean
public CorsConfigurationSource corsConfigurationSource() {
    var config = new CorsConfiguration();
    config.setAllowedOrigins(List.of("https://app.example.com"));  // explicit, never "*"
    config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE"));
    config.setAllowedHeaders(List.of("Authorization", "Content-Type", "Idempotency-Key"));
    config.setAllowCredentials(true);
    config.setMaxAge(3600L);
    var source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/api/**", config);
    return source;
}
```

Rules:
- Never `allowedOrigins("*")` with `allowCredentials(true)` — browsers reject it
- List allowed origins explicitly, use `allowedOriginPatterns` for dynamic subdomains
- Only expose headers clients actually need

#### Audit Logging

```java
@Aspect
@Component
@Slf4j
public class AuditAspect {

    @Around("@annotation(auditable)")
    public Object audit(ProceedingJoinPoint joinPoint, Auditable auditable) throws Throwable {
        var auth = SecurityContextHolder.getContext().getAuthentication();
        var start = Instant.now();
        try {
            var result = joinPoint.proceed();
            log.info("AUDIT: user={}, action={}, target={}, status=SUCCESS, duration={}ms",
                auth != null ? auth.getName() : "anonymous",
                auditable.action(),
                auditable.target(),
                Duration.between(start, Instant.now()).toMillis());
            return result;
        } catch (Exception e) {
            log.warn("AUDIT: user={}, action={}, target={}, status=FAILURE, reason={}",
                auth != null ? auth.getName() : "anonymous",
                auditable.action(), auditable.target(), e.getMessage());
            throw e;
        }
    }
}

@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface Auditable {
    String action();
    String target();
}
```

Rules:
- Audit: who (user/service), what (action), what-on (resource), when (timestamp), result (success/failure)
- Audit mutating operations (create, update, delete) and auth events (login, logout, token refresh)
- Log audits at INFO level with `AUDIT:` prefix for easy filtering
- Never log tokens, passwords, or full request bodies in audit

#### CSRF
- Stateless REST APIs: disable CSRF (tokens replace cookies for auth)
- Session-based (MVC + Thymeleaf): keep CSRF enabled with `CsrfTokenRepository`
- Only serve cookies with `SameSite=Strict` or `SameSite=Lax`

### Testing

- **Unit**: `@ExtendWith(MockitoExtension.class)`, `@Mock` + `@InjectMocks`
- **Web layer**: `@WebMvcTest`, `@MockBean` services, `MockMvc`
- Happy path AND error path covered for every endpoint.
- Edge cases: not-found, duplicate, invalid state transitions, null inputs.

---

## Architecture-Dependent Rules

The skill auto-detects the architecture type. If detection is ambiguous, it asks.

### Monolith

Single deployable, shared database, direct method calls between modules.

- Package by feature or by layer — be consistent with what exists.
- `@SpringBootTest` with full application context for integration tests.
- Shared database — no cross-module DB access rules needed.
- OpenAPI specs optional (often absent in monoliths).
- Transactional boundaries can span multiple "domain" services.
- Use `@Profile` for environment-specific beans.

#### Spring Modulith (recommended for monoliths)

Spring Modulith enforces module boundaries in a monolith, provides async eventing between modules (in-process), and supports gradual extraction to microservices. Detect it: check for `spring-modulith-starter-core` dependency.

- **Dependencies**: `spring-modulith-starter-core`, `spring-modulith-starter-test`, `spring-modulith-starter-jpa` (for event publication registry)
- **Module structure**: Package-per-module at the root: `com.company.app.orders`, `com.company.app.customers`, `com.company.app.payments`
- **Module API**: Each module exposes a public API — classes in non-exported packages are inaccessible to other modules
- **Module events**: `@ApplicationModuleListener` for async, transactional in-process events (no message broker needed)
- **Module verification**: ArchUnit-based `ApplicationModules.of(XxxApplication.class).verify()` enforces module boundaries at test time
- **Module documentation**: `new Documenter(modules).writeDocumentation()` generates PlantUML diagrams and docs
- **Migration path**: Modulith modules can be extracted to microservices by moving the package to a new project and wiring via REST/messaging
- **Database**: Each module can own its database tables, but they still share the DB instance. Use naming conventions: `orders_*`, `customers_*`, `payments_*`
- **Test**: `@ApplicationModuleTest` for module-internal tests, `@SpringBootTest` for full-context

### REST Microservices

Independent deployables, per-service database, REST contracts.

- Package root: `com.<company>.<service>`.
- OpenAPI spec per service — the source of truth for API contracts.
- Controllers implement OpenAPI-generated interfaces when using `openapi-generator-maven-plugin`.
- Each service owns its database exclusively — no cross-service DB access.
- Service-to-service communication via REST or gRPC clients.
- Integration tests: `@SpringBootTest` (RANDOM_PORT) + Testcontainers for real DB.
- Circuit breaker (Resilience4j / Spring Cloud Circuit Breaker) for external service calls.
- Centralized config (Spring Cloud Config) and service discovery if present.

#### API Versioning

Choose one strategy per project and apply consistently:

| Strategy | Example | Pros | Cons |
|----------|---------|------|------|
| **URI path** (recommended) | `/api/v1/orders`, `/api/v2/orders` | Simple, visible, easy to route | URI pollution, breaks HATEOAS |
| **Header** | `Accept: application/vnd.company.v2+json` | Clean URIs, content negotiation | Harder to test in browser, less visible |
| **Query param** | `/api/orders?version=2` | Easy to default | Not RESTful, ignored by caches |
| **Content type** | `Content-Type: application/vnd.company.v2+json` | Fine-grained per resource | Complex for clients, cache issues |

**Rules:**
- Default to **URI path versioning** (`/api/v1/...`) for REST APIs — simplest and most widely supported
- Major version in path; minor/patch versions via headers if needed
- Only version when making **breaking changes** (field removal, type change, semantic change). Additive changes (new field, new endpoint) don't require a version bump.
- Support N-1 version for a deprecation window (e.g., 6 months). Announce deprecation via `Sunset` HTTP header: `Sunset: Sat, 31 Dec 2026 23:59:59 GMT`
- Use `Deprecation: true` header on deprecated endpoints
- Separate controller per version: `OrderControllerV1`, `OrderControllerV2` in sub-packages `controller/v1/`, `controller/v2/`
- Each version gets its own DTOs — never share DTOs between versions (they diverge)
- OpenAPI spec per version: `openapi-v1.yaml`, `openapi-v2.yaml`

### Event-Driven Microservices

Async communication via message broker, per-service database, eventual consistency.

- All microservices rules above, plus:
- Events are first-class API contracts alongside REST endpoints.
- Event producers: use `StreamBridge` (Spring Cloud Stream) or `KafkaTemplate`.
- Event consumers: `@Bean Function<EventType, ...>` (functional) or `@KafkaListener`.
- Outbox pattern for transactional event publishing (Debezium or transactional outbox table).
- Saga pattern for distributed transactions spanning services.
- Idempotent consumers — handle duplicate events gracefully.
- Dead-letter topic for failed events.
- Integration tests: Testcontainers for DB + embedded Kafka or Testcontainers Kafka module.
- Event schemas use Avro or JSON Schema where applicable.

### CQRS (optional, layered on any architecture)

- Separate read models from write models.
- Commands (write) use domain entities; queries (read) use projections or direct SQL/JPQL.
- Read side can bypass the service layer for performance (direct repository/custom query use).
- Event handlers update read projections asynchronously.

### Reactive Stack (WebFlux / R2DBC)

When the project uses `spring-boot-starter-webflux` instead of `spring-boot-starter-web`, the reactive (non-blocking) paradigm applies. Detect and adapt.

**Detection**: Check for `spring-boot-starter-webflux` in dependencies. If both `webflux` and `web` are present, ask the user — mixed servlet + reactive is unusual and usually accidental.

| Aspect | Servlet (Blocking) | Reactive (Non-Blocking) |
|--------|-------------------|------------------------|
| Starter | `spring-boot-starter-web` | `spring-boot-starter-webflux` |
| Return types | `T`, `ResponseEntity<T>` | `Mono<T>`, `Flux<T>`, `Mono<ResponseEntity<T>>` |
| Database | `spring-boot-starter-data-jpa`, `JpaRepository` | `spring-boot-starter-data-r2dbc`, `R2dbcRepository` |
| Auditing | `@EnableJpaAuditing`, `@CreatedDate` on `Instant` | `@EnableR2dbcAuditing`, `@CreatedDate` on `Instant` (same) |
| HTTP client | `RestTemplate`, `WebClient` | `WebClient` (non-blocking by default) |
| Messaging | `KafkaTemplate` (blocking send) | `ReactiveKafkaProducerTemplate` |
| Error handling | `@RestControllerAdvice` (same) | `@RestControllerAdvice` (same), plus `onErrorResume`/`onErrorMap` operators |
| Security | `SecurityFilterChain` (same) | `SecurityWebFilterChain` (different path configurer) |
| Test | `@WebMvcTest`, `MockMvc` | `@WebFluxTest`, `WebTestClient` |
| Scheduler | Tomcat (thread-per-request) | Netty (event-loop) |
| `@Transactional` | Yes | Not supported — use `DatabaseClient` with explicit transaction operators |
| `Pageable` | Yes (offset-based) | Manual `LIMIT OFFSET` (R2DBC doesn't support `Page`; use `Flux<T>.take()` or keyset pagination) |
| Entity IDs | `@GeneratedValue(UUID)` via JPA | Manual UUID assignment via `@Id` + `UUID.randomUUID()` in constructor or `@PrePersist` callback |

**Reactive controller example:**
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
    public Mono<ResponseEntity<ApiResponse<AccountResponse>>> createAccount(
            @Valid @RequestBody Mono<CreateAccountRequest> request) {
        return request
            .doOnNext(r -> log.info("Creating account: type={}", r.accountType()))
            .flatMap(service::createAccount)
            .map(result -> ResponseEntity.status(HttpStatus.CREATED)
                .body(ApiResponse.success(result)));
    }

    @GetMapping("/{id}")
    public Mono<ResponseEntity<ApiResponse<AccountResponse>>> getAccount(@PathVariable UUID id) {
        return service.getAccount(id)
            .map(result -> ResponseEntity.ok(ApiResponse.success(result)))
            .switchIfEmpty(Mono.error(new ResourceNotFoundException(ErrorCode.RESOURCE_NOT_FOUND, "Not found")));
    }
}
```

**Reactive service:**
```java
@Service
@RequiredArgsConstructor
@Slf4j
public class AccountServiceImpl implements AccountService {
    private final R2dbcAccountRepository repository;
    private final AccountMapper mapper;

    public Mono<AccountResponse> createAccount(CreateAccountRequest request) {
        return repository.existsByAccountNumber(request.accountNumber())
            .filter(exists -> !exists)
            .switchIfEmpty(Mono.error(new ConflictException(ErrorCode.CONFLICT, "Account already exists")))
            .then(Mono.fromCallable(() -> {
                var entity = mapper.toEntity(request);
                entity.setId(UUID.randomUUID());
                entity.setBalance(BigDecimal.ZERO);
                return entity;
            }))
            .flatMap(repository::save)
            .map(mapper::toResponse)
            .doOnSuccess(response -> log.info("Account created: id={}", response.id()));
    }
}
```

**Reactive repository (R2DBC):**
```java
@Repository
public interface AccountRepository extends ReactiveCrudRepository<Account, UUID> {
    Mono<Boolean> existsByAccountNumber(String accountNumber);
    Flux<Account> findByCustomerId(UUID customerId);  // no Page — use limit + offset or keyset
}
```

**Reactive error handling — global advice stays the same**, but service-level operators matter:
- `switchIfEmpty(Mono.error(...))` — transform empty to error
- `onErrorMap(...)` — wrap exceptions
- `onErrorResume(...)` — fallback behavior
- Always return `Mono.error(...)` not `throw`, inside reactive chains

**Reactive test:**
```java
@WebFluxTest(AccountController.class)
class AccountControllerTest {
    @Autowired private WebTestClient webTestClient;
    @MockBean private AccountService service;
}
```

### gRPC (Spring gRPC)

gRPC is increasingly common for internal service-to-service communication. Detect it: `grpc-spring-boot-starter` or `grpc-server-spring-boot-starter` dependency.

- **Dependency**: `net.devh:grpc-spring-boot-starter` or `net.devh:grpc-server-spring-boot-starter`
- **Contract**: `.proto` files in `src/main/proto/` — the source of truth for API
- **Generated stubs**: Maven `protobuf-maven-plugin` or Gradle `protobuf-gradle-plugin` generates Java classes in `target/generated-sources/protobuf/`
- **Server**: `@GrpcService` annotation on service implementations extending generated `XxxImplBase`
- **Client**: `@GrpcClient` annotation injecting blocking or async stubs
- **Error handling**: `StatusException` with gRPC status codes (NOT_FOUND, ALREADY_EXISTS, INVALID_ARGUMENT, INTERNAL)
- **Interceptors**: `ServerInterceptor` and `ClientInterceptor` for auth, logging, tracing, metrics
- **Deadlines**: Always set deadlines on gRPC calls: `stub.withDeadline(Deadline.after(5, SECONDS)).createOrder(...)`
- **Health**: `grpc-health-service` exposes gRPC health checking protocol
- **Reflection**: `grpc-server-reflection-spring-boot-starter` for `grpcurl` debugging

**proto example:**
```protobuf
syntax = "proto3";
package com.company.orders.v1;
option java_multiple_files = true;

service OrderService {
    rpc CreateOrder(CreateOrderRequest) returns (OrderResponse);
    rpc GetOrder(GetOrderRequest) returns (OrderResponse);
}

message CreateOrderRequest {
    string customer_id = 1;
    repeated OrderItem items = 2;
}

message OrderResponse {
    string id = 1;
    string customer_id = 2;
    double total_amount = 3;
    string status = 4;
}
```

**Server implementation:**
```java
@GrpcService
@RequiredArgsConstructor
@Slf4j
public class OrderGrpcService extends OrderServiceGrpc.OrderServiceImplBase {
    private final OrderService service;

    @Override
    public void createOrder(CreateOrderRequest request,
                            StreamObserver<OrderResponse> responseObserver) {
        try {
            var result = service.createOrder(toDomain(request));
            responseObserver.onNext(toProto(result));
            responseObserver.onCompleted();
        } catch (ConflictException e) {
            responseObserver.onError(Status.ALREADY_EXISTS
                .withDescription(e.getMessage()).asRuntimeException());
        }
    }
}
```

**Client:**
```java
@GrpcClient("order-service")
private OrderServiceGrpc.OrderServiceBlockingStub orderStub;

public OrderResponse createOrder(CreateOrderRequest request) {
    return orderStub.withDeadline(Deadline.after(5, SECONDS)).createOrder(request);
}
```

**gRPC-vs-REST decision guidance:**
- Use gRPC for: internal service-to-service (low latency, binary), streaming, polyglot environments
- Use REST for: external APIs, browser clients, webhooks, simpler debugging
- Both can coexist — each serves different consumers

### GraphQL (Spring for GraphQL)

GraphQL is common for BFF (Backend-for-Frontend) layers and mobile APIs. Detect it: `spring-boot-starter-graphql` dependency.

- **Dependency**: `spring-boot-starter-graphql` (server), `spring-graphql-test` (test)
- **Schema**: `.graphqls` files in `src/main/resources/graphql/` — schema-first approach
- **Controllers**: `@Controller` with `@QueryMapping`, `@MutationMapping`, `@SubscriptionMapping` (NOT `@RestController`)
- **Data loaders**: `@BatchMapping` or `MappedBatchLoader` for N+1 prevention (graphql-java `DataLoader`)
- **Error handling**: `DataFetcherExceptionResolverAdapter` → map domain exceptions to `GraphQLError`
- **Validation**: `@Validated` on controller, `@Valid` on input types
- **Pagination**: Relay Connection spec (`Connection<T>`, `ConnectionCursor`)
- **Security**: `@PreAuthorize` on `@QueryMapping`/`@MutationMapping` methods
- **Testing**: `@GraphQlTest`, `GraphQlTester` for query/mutation testing
- **Subscriptions**: RSocket or WebSocket transport for real-time GraphQL

**Schema example:**
```graphql
type Query {
    order(id: ID!): Order
    orders(customerId: ID!, first: Int, after: String): OrderConnection
}

type Mutation {
    createOrder(input: CreateOrderInput!): Order
    cancelOrder(id: ID!): Order
}

type Order {
    id: ID!
    customerId: ID!
    items: [OrderItem!]!
    totalAmount: BigDecimal!
    status: OrderStatus!
    createdAt: DateTime!
}

input CreateOrderInput {
    customerId: ID!
    items: [OrderItemInput!]!
}
```

**Controller:**
```java
@Controller
@RequiredArgsConstructor
@Slf4j
public class OrderGraphQlController {
    private final OrderService service;

    @QueryMapping
    public Mono<Order> order(@Argument UUID id) {
        return service.getOrder(id).map(mapper::toGraphQl);
    }

    @MutationMapping
    @PreAuthorize("hasAuthority('SCOPE_write')")
    public Mono<Order> createOrder(@Valid @Argument CreateOrderInput input) {
        return service.createOrder(toRequest(input)).map(mapper::toGraphQl);
    }

    @BatchMapping
    public Mono<Map<Order, List<OrderItem>>> items(List<Order> orders) {
        // Batch-load items for all orders in one query — prevents N+1
        return service.findItemsForOrders(orders.stream().map(Order::getId).toList())
            .collectMap(Item::getOrderId, Function.identity());
    }
}
```

**GraphQL error handling:**
```java
@Component
public class GraphQlExceptionResolver extends DataFetcherExceptionResolverAdapter {
    @Override
    protected GraphQLError resolveToSingleError(Throwable ex, DataFetchingEnvironment env) {
        if (ex instanceof ResourceNotFoundException) {
            return GraphqlErrorBuilder.newError(env)
                .message(ex.getMessage())
                .errorType(ErrorType.NOT_FOUND)
                .build();
        }
        return null;  // let other resolvers handle
    }
}
```

Rules:
- Schema-first: `.graphqls` files are the contract — never generate schema from code
- `@QueryMapping` for reads, `@MutationMapping` for writes, `@SubscriptionMapping` for real-time
- `@BatchMapping` for every `@OneToMany` / nested list — prevents N+1 in GraphQL
- Input validation: `@Valid` on `@Argument` inputs, standard Jakarta annotations
- Return `Mono<T>` or `Flux<T>` for reactive (WebFlux), or bare `T` for servlet
- Paginate with Relay Connection spec for forward/backward cursor pagination
- Rate-limit GraphQL queries by complexity/depth — not just count
- Never expose JPA entities directly in GraphQL — always map to DTOs

### Spring Data Redis

Redis is the go-to for caching, session storage, rate limiting, and distributed locks. Detect it: `spring-boot-starter-data-redis` dependency.

- **Dependencies**: `spring-boot-starter-data-redis`, `spring-session-data-redis` (HTTP session), `redisson-spring-boot-starter` (distributed locks)
- **Config**: `spring.data.redis.host`, `spring.data.redis.port`, `spring.data.redis.password`, `spring.data.redis.ssl`
- **Serialization**: Use `Jackson2JsonRedisSerializer` or `StringRedisSerializer` — never Java serialization
- **Cache**: `@Cacheable` → Redis-backed via `RedisCacheManager`
- **Sessions**: `spring.session.store-type=redis` for distributed HTTP session (session-based apps)
- **Rate limiting**: Store rate counters in Redis with TTL — atomic via `INCR` + `EXPIRE`
- **Distributed locks**: `RedissonClient.getLock("order:" + orderId)` for cross-instance locking
- **Pub/Sub**: `RedisTemplate.convertAndSend("channel", message)` for lightweight messaging
- **Connection**: Use Lettuce (default, non-blocking) for reactive; Jedis for blocking
- **Test**: `@ServiceConnection` with Testcontainers `redis:7-alpine`

```java
@Configuration
@EnableCaching
public class RedisConfig {
    @Bean
    public RedisCacheManagerBuilderCustomizer cacheManagerBuilderCustomizer() {
        return builder -> builder
            .withCacheConfiguration("orders",
                RedisCacheConfiguration.defaultCacheConfig().entryTtl(Duration.ofMinutes(10)))
            .withCacheConfiguration("accounts",
                RedisCacheConfiguration.defaultCacheConfig().entryTtl(Duration.ofHours(1)));
    }
}
```

### Read Replica / Read-Write Splitting

For scaling read-heavy applications, route writes to the primary DB and reads to read replicas:

```java
@Component
public class RoutingDataSource extends AbstractRoutingDataSource {
    @Override
    protected Object determineCurrentLookupKey() {
        return TransactionSynchronizationManager.isCurrentTransactionReadOnly() ? "read" : "write";
    }
}

@Configuration
public class DataSourceConfig {
    @Bean
    @Primary
    public DataSource dataSource(
            @Qualifier("writeDataSource") DataSource writeDs,
            @Qualifier("readDataSource") DataSource readDs) {
        var routing = new RoutingDataSource();
        routing.setDefaultTargetDataSource(writeDs);
        var targets = Map.of("write", writeDs, "read", (Object) readDs);
        routing.setTargetDataSources(Map.of("write", writeDs, "read", (Object) readDs));
        return new LazyConnectionDataSourceProxy(routing);
    }
}
```

Rules:
- `@Transactional(readOnly = true)` → automatically routes to read replica
- `@Transactional` (no `readOnly`) → routes to primary/write
- Use `LazyConnectionDataSourceProxy` to defer connection acquisition until first SQL — avoids grabbing write connection for read-only methods
- Replication lag: design for eventual consistency on reads (don't read your own writes immediately)
- For critical read-after-write: use `@Transactional` (no `readOnly`) or force-read-primary hint
- Monitor replication lag; alert if > N seconds
- Test with `tc-loom` or `tc-repl` for Testcontainers-based replica simulation
- Not needed for monoliths with moderate traffic — add when read volume exceeds single DB capacity

### Resilience Patterns

Beyond circuit breaker, production systems need layered resilience:

#### Retry with Backoff
```java
@Retry(name = "orderService", fallbackMethod = "createOrderFallback")
public OrderResponse createOrder(CreateOrderRequest request) { ... }

public OrderResponse createOrderFallback(CreateOrderRequest request, Exception e) {
    log.error("Order creation failed after retries", e);
    throw new ServiceUnavailableException(ErrorCode.SERVICE_UNAVAILABLE, "Order service unavailable");
}
```

```yaml
resilience4j:
  retry:
    instances:
      orderService:
        max-attempts: 3
        wait-duration: 1s
        exponential-backoff-multiplier: 2
        retry-exceptions:
          - java.net.SocketTimeoutException
          - org.springframework.web.client.ResourceAccessException
```

#### Timeout
```yaml
resilience4j:
  timelimiter:
    instances:
      orderService:
        timeout-duration: 5s
        cancel-running-future: true
```

#### Bulkhead
```yaml
resilience4j:
  bulkhead:
    instances:
      orderService:
        max-concurrent-calls: 10
        max-wait-duration: 500ms
```

#### Rate Limiter
```yaml
resilience4j:
  ratelimiter:
    instances:
      orderService:
        limit-for-period: 100
        limit-refresh-period: 1s
        timeout-duration: 500ms
```

#### Graceful Shutdown
```yaml
server:
  shutdown: graceful
spring:
  lifecycle:
    timeout-per-shutdown-phase: 30s
```

Rules:
- Always configure all four: retry + timeout + bulkhead + circuit breaker for external calls
- Fallback method: either throw a domain exception or return a cached/stale response
- Circuit breaker opens after 50% failure rate in a rolling window
- Retry with exponential backoff + jitter to avoid thundering herd
- Rate limit at both API gateway AND service level for defense-in-depth
- Graceful shutdown: drain in-flight requests before closing the context

#### Pattern Ordering

Stack patterns outside-in from outermost to innermost: `Retry → CircuitBreaker → TimeLimiter → Bulkhead → actual call`.

```java
@Bulkhead(name = "payment")
@TimeLimiter(name = "payment")
@CircuitBreaker(name = "payment")
@Retry(name = "payment")
public PaymentResponse processPayment(ChargeRequest request) { ... }
```

#### Retryable vs Ignored Exceptions

- **Retry on**: `ConnectException`, `SocketTimeoutException`, `ResourceAccessException`, HTTP 503
- **Never retry on**: `BadRequestException`, `ResourceNotFoundException`, HTTP 400/404/409/422
- Configure `record-exceptions` and `ignore-exceptions` explicitly per circuit breaker instance

#### Feign Client Resilience

Feign client names auto-map to Resilience4j instance names:

```yaml
resilience4j:
  circuitbreaker:
    instances:
      payment-service:   # matches @FeignClient(name = "payment-service")
        sliding-window-size: 50
        failure-rate-threshold: 50
```

#### Typed Configuration Records

Use `@ConfigurationProperties` records for per-downstream resilience config — never hardcode thresholds:

```java
@ConfigurationProperties(prefix = "resilience.payment")
public record PaymentResilienceConfig(
    int retryMaxAttempts,
    Duration retryBackoff,
    int circuitBreakerFailureThreshold,
    Duration circuitBreakerOpenDuration,
    int circuitBreakerHalfOpenCalls,
    Duration timeout,
    int bulkheadMaxConcurrent,
    Duration bulkheadMaxWait
) {}
```

#### Resilience Audit

Systematically audit every downstream call: circuit breaker, retry, timeout, bulkhead. Priority: critical path (all 4 mandatory) > semi-critical (CB + timeout minimum) > non-critical (timeout + bulkhead so they don't block critical paths).

### Spring Batch

For enterprise batch processing (ETL, reconciliation, bulk operations). Detect: `spring-boot-starter-batch` dependency.

- **Dependencies**: `spring-boot-starter-batch`; for persistence: `spring-boot-starter-data-jpa`
- **Job**: `@Configuration` class with `Job` bean built from `JobBuilderFactory`
- **Step**: Chunk-oriented: `ItemReader<I>` → `ItemProcessor<I, O>` → `ItemWriter<O>`
- **Chunk size**: Typically 100-1000 — configurable; commit after each chunk
- **Job repository**: Stores job/step execution metadata in DB — requires `batch_*` tables
- **Restartability**: Failed jobs restart from last committed chunk — idempotent processing required
- **Job parameters**: `JobParameters` for parameterized runs (date ranges, file paths)
- **Listeners**: `JobExecutionListener`, `StepExecutionListener`, `ChunkListener`
- **Skip/Retry**: Configure `skipLimit` and `retryLimit` per step for transient failures
- **Scheduling**: `@Scheduled` triggers batch jobs; use `JobLauncher.run(job, params)`
- **Test**: `@SpringBatchTest`, `JobLauncherTestUtils`

```java
@Configuration
@RequiredArgsConstructor
public class OrderReconciliationJob {
    private final JobRepository jobRepository;
    private final PlatformTransactionManager txManager;

    @Bean
    public Job reconcileOrdersJob() {
        return new JobBuilder("reconcileOrders", jobRepository)
            .start(reconcileStep())
            .build();
    }

    @Bean
    public Step reconcileStep() {
        return new StepBuilder("reconcileStep", jobRepository)
            .<Order, Order>chunk(500, txManager)
            .reader(orderReader(null))      // JdbcPagingItemReader
            .processor(reconciliationProcessor())
            .writer(orderWriter())
            .faultTolerant()
            .skip(DataIntegrityViolationException.class)
            .skipLimit(100)
            .retry(TransientDataAccessException.class)
            .retryLimit(3)
            .build();
    }
}
```

### `@Scheduled` and `@Async`

For background task execution:

```java
@Configuration
@EnableScheduling
@EnableAsync
public class AsyncConfig implements AsyncConfigurer {
    @Bean
    public Executor taskExecutor() {
        var executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(4);
        executor.setMaxPoolSize(8);
        executor.setQueueCapacity(100);
        executor.setThreadNamePrefix("async-");
        executor.setRejectedExecutionHandler(new CallerRunsPolicy());
        executor.initialize();
        return executor;
    }
}

@Component
@Slf4j
public class ScheduledTasks {
    @Scheduled(cron = "0 0 3 * * ?")  // 3 AM daily
    public void purgeExpiredTokens() { ... }

    @Scheduled(fixedRate = 60000, initialDelay = 30000)
    public void refreshCache() { ... }
}

@Service
@Slf4j
public class NotificationService {
    @Async
    public CompletableFuture<Void> sendEmailAsync(EmailRequest request) {
        // non-blocking — fire and forget
        emailClient.send(request);
        return CompletableFuture.completedFuture(null);
    }
}
```

Rules:
- `@Async` methods must be `public` and called from outside the class (AOP proxy limitation)
- Always configure explicit `ThreadPoolTaskExecutor` — never use default `SimpleAsyncTaskExecutor` in production
- `@Scheduled` cron: use sparingly — prefer external schedulers (K8s CronJob, Airflow) for critical jobs
- `@Scheduled` methods must be idempotent — if the app restarts mid-execution, it should be safe to re-run
- Async methods should handle their own exceptions — uncaught exceptions are silently swallowed by `AsyncUncaughtExceptionHandler`
- Set `spring.task.scheduling.pool.size` and `spring.task.execution.pool.size` in `application.yml`

### Multi-Tenancy

Enterprise applications often serve multiple tenants from the same deployment. Choose a strategy:

| Strategy | How it works | Pros | Cons |
|----------|-------------|------|------|
| **Database-per-tenant** | Separate DB per tenant | Strongest isolation, easy backup/restore per tenant | Connection pool per tenant, harder to scale |
| **Schema-per-tenant** | Shared DB, separate schema per tenant | Good isolation, shared connection pool | Schema migration across all schemas |
| **Discriminator column** | Shared tables, `tenant_id` column everywhere | Simplest, single DB | Weakest isolation, every query must filter |

**Implementation pattern (discriminator):**
```java
@Component
public class TenantContext {
    private static final ThreadLocal<String> CURRENT_TENANT = new ThreadLocal<>();
    public static void set(String tenant) { CURRENT_TENANT.set(tenant); }
    public static String get() { return CURRENT_TENANT.get(); }
    public static void clear() { CURRENT_TENANT.remove(); }
}

@Component
public class TenantFilter extends OncePerRequestFilter {
    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                     FilterChain chain) throws ServletException, IOException {
        var tenant = request.getHeader("X-Tenant-Id");
        if (tenant != null) TenantContext.set(tenant);
        try { chain.doFilter(request, response); }
        finally { TenantContext.clear(); }
    }
}

// Hibernate filter for automatic tenant filtering
@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "tenantId", type = String.class))
@Filter(name = "tenantFilter", condition = "tenant_id = :tenantId")
@Entity
public class Order { ... }
```

Rules:
- Tenant context propagated through all async/messaging boundaries
- Never let tenant A access tenant B's data — this is a security boundary
- Multi-tenancy strategy chosen at project start — hard to change later
- Migrations must be applied to ALL tenants atomically (schema-per-tenant) or per-DB
- Tenant onboarding/offboarding automated via admin API
- Rate limit and resource quotas per-tenant to prevent noisy-neighbor

### Internationalization (i18n)

For multi-language applications:

```java
@Configuration
public class I18nConfig {
    @Bean
    public MessageSource messageSource() {
        var source = new ReloadableResourceBundleMessageSource();
        source.setBasename("classpath:messages");
        source.setDefaultEncoding("UTF-8");
        source.setFallbackToSystemLocale(false);
        source.setUseCodeAsDefaultMessage(true);  // show code if message missing
        return source;
    }

    @Bean
    public LocaleResolver localeResolver() {
        var resolver = new AcceptHeaderLocaleResolver();
        resolver.setDefaultLocale(Locale.ENGLISH);
        resolver.setSupportedLocales(List.of(Locale.ENGLISH, Locale.FRENCH, Locale.GERMAN));
        return resolver;
    }
}
```

- Error messages: `messageSource.getMessage("error.order.not-found", new Object[]{id}, locale)`
- Resource bundles: `messages.properties`, `messages_fr.properties`, `messages_de.properties`
- Accept `Accept-Language` header from clients
- Default to English, fallback to code if message missing
- Static messages in resource bundles; dynamic content via DB with locale column

### Feature Flags

Control feature rollout without redeploying:

```java
@ConfigurationProperties(prefix = "features")
public record FeatureFlags(
    boolean newCheckoutFlow,
    boolean aiRecommendations,
    @DefaultValue("0.1") double betaUserPercentage
) {}

@Service
public class CheckoutService {
    private final FeatureFlags flags;
    private final CheckoutServiceV2 v2Service;
    private final CheckoutServiceV1 v1Service;

    public OrderResponse checkout(CheckoutRequest request) {
        if (flags.newCheckoutFlow() && isBetaUser(request.customerId())) {
            return v2Service.checkout(request);
        }
        return v1Service.checkout(request);
    }
}
```

Rules:
- Feature flags via `@ConfigurationProperties` (can be overridden by env vars / Spring Cloud Config)
- Percentage rollouts: hash customer ID to deterministically assign to flag group
- Always have a kill switch: flag can be turned off without deploy
- Clean up flags after full rollout — stale flags are technical debt
- For advanced use cases, consider LaunchDarkly or Flagsmith SDK

### WebSocket / SSE

For real-time updates:

- **WebSocket**: `spring-boot-starter-websocket`, STOMP for pub/sub, `@MessageMapping`/`@SendTo`
- **SSE (Server-Sent Events)**: `SseEmitter` or returning `Flux<ServerSentEvent<T>>` from controller
- WebSocket requires sticky sessions or a message broker (RabbitMQ/Redis) for multi-instance
- SSE is simpler (HTTP-based), works through proxies, auto-reconnect built into browsers
- Use WebSocket for bidirectional (chat, collaboration); SSE for unidirectional (dashboards, notifications)

```java
// SSE example — reactive
@GetMapping(value = "/orders/{id}/events", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
public Flux<ServerSentEvent<OrderEvent>> streamOrderEvents(@PathVariable UUID id) {
    return orderEventService.stream(id)
        .map(event -> ServerSentEvent.<OrderEvent>builder()
            .id(event.eventId().toString())
            .event(event.type().name())
            .data(event)
            .build());
}
```

### Event Sourcing

Store state changes as an immutable sequence of events rather than current state:

- Event store table: `events(id, aggregate_id, aggregate_type, event_type, payload, sequence_number, created_at)`
- Rebuild current state by replaying events: `aggregate = replay(events)`
- Snapshots at intervals to speed up rebuilding: `snapshot(id, aggregate_id, state, sequence_number)`
- CQRS is the natural companion: events feed read-model projections
- Use with: Axon Framework or custom implementation
- Testing: given `[EventA, EventB]`, when `command X`, then `[EventC]`

### CDC with Debezium

Capture database changes as events without modifying application code:

- Debezium connects to DB WAL (PostgreSQL) or binlog (MySQL)
- Emits events to Kafka: `{"before": {...}, "after": {...}, "op": "c|u|d|r", "source": {...}}`
- Use for: feeding search indexes (Elasticsearch), audit logs, cache invalidation, data warehouse sync
- Outbox pattern alternative: Debezium reads the outbox table and publishes to Kafka
- Connect via `debezium-connector-postgres` on Kafka Connect (not in-app)
- Application only needs to write to the outbox table — Debezium handles the rest

### Schema Registry

When using Avro/Protobuf with Kafka:

- **Confluent Schema Registry**: REST API for schema storage, compatibility checks
- **Apicurio Registry**: Open-source alternative, supports Avro/Protobuf/JSON Schema
- Always use a schema registry for event-driven systems — enforces backward/forward compatibility
- Register schemas in CI/CD or at startup via `schema-registry-maven-plugin`
- Schema evolution rules: add optional fields (FORWARD), never remove required fields, never change field types
- In tests: use `@Container` with `confluentinc/cp-schema-registry` or Apicurio Testcontainers module

### CloudEvents

Standardized event envelope for cross-system interoperability:

```json
{
    "specversion": "1.0",
    "type": "com.company.orders.OrderCreated",
    "source": "/orders-service",
    "subject": "order-123",
    "id": "evt-abc-456",
    "time": "2026-05-15T10:30:00Z",
    "datacontenttype": "application/json",
    "data": { "orderId": "...", "customerId": "..." }
}
```

- Spring Cloud Stream supports CloudEvents via `spring-cloud-stream-binder-kafka` with `cloud-events` header mode
- Use CloudEvents when events cross team/boundary (not needed for internal-only events)
- Always set `type`, `source`, `id`, `time` — these are required fields
- `subject` for the entity identity, `data` for the payload

---

## Build System Detection

The skill auto-detects and adapts:

| Aspect | Maven | Gradle |
|--------|-------|--------|
| Build command | `mvn clean verify` | `./gradlew build` |
| Single module | `mvn clean verify` | `./gradlew build` |
| Multi-module (specific) | `mvn clean verify -pl :module-name` | `./gradlew :module-name:build` |
| Formatting | `mvn spotless:apply` | `./gradlew spotlessApply` |
| Test (single module) | `mvn test -pl :module-name` | `./gradlew :module-name:test` |
| Test (single test) | `mvn test -pl :module-name -Dtest=ClassName#methodName` | `./gradlew :module-name:test --tests "com.x.ClassName.methodName"` |

If Spotless is not configured, skip formatting. If no build wrapper exists, use system `mvn` or `gradle`.

---

## Package Structure Discovery

The skill discovers the actual package structure — do not assume:

1. Find the root package by scanning `@SpringBootApplication` class location.
2. Detect sub-packages: `controller`, `service`, `service.impl`, `repository`, `entity`, `dto`, `mapper`, `config`, `exception`.
3. If a different convention is used (e.g., package-by-feature), follow the existing pattern.
4. If no structure exists yet, default to the layered layout above under the root package.

---

## Project-Specific Conventions (Discovered at Runtime)

These are NOT hardcoded — they are discovered from the target project:

| What | How to discover |
|------|-----------------|
| Base exception class | Scan for classes extending `RuntimeException` used across services |
| Error code enum | Scan for enums with fields like `code`, `message`, `httpStatus` |
| Response wrapper | Scan controller return types for a generic wrapper class (e.g., `ApiResponse<T>`, `ResponseEntity<T>`) |
| Global exception handler | Find `@RestControllerAdvice` class |
| Module/service directory layout | Read `pom.xml` `<modules>` or `settings.gradle` |
| OpenAPI spec location | Find `*.yaml`/`*.json` files in `src/main/resources/openapi/` or similar |
| MapStruct usage | Check for `@Mapper(componentModel = "spring")` in existing code |
| Lombok usage | Check for Lombok annotations in existing code |
| Test framework | Check `@SpringBootTest` vs `@MicronautTest`, Testcontainers, RestAssured presence |
| Database | Check `application.yml` / `application.properties` for datasource config |
| Java version | Read `java.version` from `pom.xml` or `sourceCompatibility` from `build.gradle` |
| Spring Boot version | Read `spring-boot-starter-parent` or plugin version |

When a convention cannot be discovered (greenfield project), default to the universal rules above and apply Spring Boot idiomatic patterns.

---

## Spring Boot Version Awareness

Spring Boot 2.x and 3.x have breaking API differences. Detect the version and adapt.

| Aspect | Spring Boot 2.x | Spring Boot 3.x |
|--------|----------------|-----------------|
| Package prefix | `javax.*` | `jakarta.*` |
| Validation imports | `javax.validation.*` | `jakarta.validation.*` |
| Persistence imports | `javax.persistence.*` | `jakarta.persistence.*` |
| Servlet imports | `javax.servlet.*` | `jakarta.servlet.*` |
| Spring Security | `http.cors().and().csrf().disable()` builder | `http.cors(c -> {}).csrf(c -> c.disable())` Lambda DSL |
| Java baseline | Java 8-17 | Java 17+ |
| Observability | Sleuth + Brave (optional) | Micrometer Tracing (built-in) |
| `@ConstructorBinding` | Required on configuration records | Auto-detected, annotation optional |
| Actuator endpoints | `health.show-details` | `health.show-components` and `health.show-details` |
| `spring.factories` | Required for auto-config | `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports` |

**Detection**: Read `<version>` from `spring-boot-starter-parent` in `pom.xml`, or `springBootVersion` / plugin version in `build.gradle`. If version starts with `3.`, use Jakarta; if `2.`, use Javax.

---

## Database Migrations

Every entity change needs a corresponding migration. Detect which tool is in use:

| Aspect | Flyway | Liquibase |
|--------|--------|-----------|
| Dependency | `flyway-core` + `flyway-database-postgresql` | `liquibase-core` |
| Migration location | `src/main/resources/db/migration/` | `src/main/resources/db/changelog/` |
| File naming | `V{version}__{description}.sql` | `changelog-{version}.xml` (or YAML/JSON/SQL) |
| Version format | Sequential: `V1`, `V2`, `V3`... | Timestamp or sequential |
| Baseline | `spring.flyway.baseline-on-migrate=true` | `spring.liquibase.change-log=classpath:db/changelog/db.changelog-master.yaml` |

If neither is configured, default to Flyway with sequential versioning and advise the user to add the dependency.

**Migration content rules**:
- Each migration creates one table or alters one set of related columns
- Include rollback/DOWN section in Liquibase changesets
- For Flyway, document the reverse operation in a comment
- Use `CREATE TABLE IF NOT EXISTS` for idempotency
- Include indexes for foreign keys and frequently queried columns
- `TIMESTAMP WITH TIME ZONE` for audit fields (not `TIMESTAMP WITHOUT TIME ZONE`)

### Schema Naming Conventions
- Tables: plural, snake_case — `orders`, `order_items`, `payment_transactions`
- Columns: singular, snake_case — `customer_id`, `created_at`, `is_active`
- PKs: `id` (UUID) — never composite unless a join table
- FKs: `{referenced_table_singular}_id` — `customer_id` references `customers(id)`
- Indexes: `idx_{table}_{column(s)}` — `idx_orders_status`, `idx_orders_customer_id_status`
- Unique constraints: `uq_{table}_{column(s)}` — `uq_orders_order_number`
- Check constraints: `ck_{table}_{rule}` — `ck_orders_total_positive`
- Entity audit fields: `created_at`, `updated_at`, `version` on every mutating table
- Monetary columns: `NUMERIC(19,4)` — never `DOUBLE` or `FLOAT`
- Use `JSONB` for semi-structured data, not `JSON`
- Use `TEXT` over `VARCHAR` for unbounded strings

### Indexing Strategy
- Index every FK column, every column in WHERE clauses, and every column in ORDER BY
- Composite indexes for columns frequently queried together
- Partial indexes for queries on small subsets: `CREATE INDEX ... WHERE status = 'PENDING'`
- Covering indexes (INCLUDE) to avoid heap fetches for common column sets
- Do NOT index low-cardinality columns (< 5 values) unless using partial indexes
- B-tree is the default; GIN for JSONB/array containment; GiST for geometric; BRIN for very large append-only tables

### No-Downtime Migration Safety
| Operation | Safety | Mitigation |
|-----------|--------|------------|
| `CREATE INDEX` | Requires CONCURRENTLY | `CREATE INDEX CONCURRENTLY` (outside transaction) |
| `ADD COLUMN NOT NULL DEFAULT` | Dangerous — rewrites table | Add nullable → backfill → set NOT NULL in next release |
| `ALTER COLUMN TYPE` | Dangerous — exclusive lock | Create new column → dual-write → backfill → switch reads → drop old |
| `DROP COLUMN` | Safe if unused | Deploy code that stops reading it first, then drop |
| `ADD FOREIGN KEY` | Dangerous | Create NOT VALID → validate in separate transaction |
| `DROP TABLE` | Dangerous | Remove code references first, then drop in next release |

### Query Anti-Patterns
- **N+1 queries**: Use `JOIN FETCH` or `@EntityGraph` for eager-loaded relationships
- **OFFSET pagination on large tables**: Use keyset/seek pagination instead
- **Function on indexed column**: `WHERE LOWER(col) = ?` defeats index; use expression index
- **Missing query timeout**: Set `jakarta.persistence.query.timeout: 5000`

### Connection Pool Tuning (HikariCP)
- Formula: `maximum-pool-size = (CPU cores * 2) + disk count`
- Typical: 10 connections per service instance
- Set `leak-detection-threshold: 60000` (1 minute) to catch connection leaks
- Watch `hikaricp_connections_pending` — if > 0 at steady state, increase pool

---

## Observability

Production applications need structured observability. Apply these patterns.

### Prometheus / OTel Metrics Setup
- Add `micrometer-registry-prometheus` and expose `/actuator/prometheus`
- Configure `management.metrics.distribution.percentiles-histogram` for HTTP and business timers
- Standard metrics every service must emit: `{domain}.created.total`, `{domain}.operation.errors`, `{domain}.operation.duration`, `downstream.{name}.health`
- For OpenTelemetry: `micrometer-registry-otlp` + `micrometer-tracing-bridge-otel`
- Metrics naming convention: `{domain}.{operation}.{unit}` — e.g., `orders.created.total`, `payments.process.duration`

### Structured Logging
- Use `log.info("{}", object)` — never string concatenation or `log.info(object.toString())`
- Include a correlation ID / trace ID in every log message (auto-injected by Micrometer Tracing)
- Log at boundaries: incoming request (controller), outgoing calls (REST clients, message producer), error paths
- Do NOT log request bodies or headers without sanitization
- Use `@Slf4j` (Lombok) or `LoggerFactory.getLogger(Xxx.class)` consistently
- JSON logging for log aggregation: `logstash-logback-encoder` with `traceId`/`spanId` in MDC

### Metrics (Micrometer)
- `@Timed` on every endpoint and every service method that calls an external system
- Custom counters for business events: `meterRegistry.counter("orders.created", "status", status.name()).increment()`
- Gauges for queue depth, connection pool size
- Percentile histograms for latency: `@Timed(histogram = true, percentiles = {0.5, 0.95, 0.99})`

### Health Checks
- Every service needs a health indicator if it depends on external systems
- Custom `HealthIndicator` for DB, message broker, and downstream APIs
- Liveness vs readiness: `/actuator/health/liveness` (JVM alive only) and `/actuator/health/readiness` (all dependencies checked)
- Readiness group should include DB, broker, and critical downstream checks

### Tracing
- Propagation headers: `X-B3-TraceId`, `X-B3-SpanId` (Zipkin) or `traceparent` (W3C)
- Include tracing in `RestTemplate` / `WebClient` builder, Kafka producer/consumer, and JDBC driver
- Inject `Tracer` / `Observation` API for custom spans around significant operations
- Spring Boot 3.x: `micrometer-tracing-bridge-brave`; Spring Boot 2.x: `spring-cloud-starter-sleuth`

### SLI / SLO Definitions
- Define per-endpoint SLIs: availability (% successful requests), latency (p95, p99), error budget
- Error budget calculation: 99.9% availability = 43.2 min downtime/month
- Burn rate alerts: fast burn (14.4x = 1h alert) for critical, slow burn (3x = 6h alert) for warning
- Store SLI/SLO config in version-controlled `.sli/{service}.yaml` files

### Grafana Dashboards
Standard dashboard rows per service: Service Health (up/down, request rate, error rate), Latency (p50/p90/p99, slow endpoints table), Throughput & Saturation (active requests, JVM memory, GC pauses), Dependencies (DB pool, downstream latency, Kafka lag), Business Metrics (domain counters and gauges).

### Alerting Rules
- Service down > 1min → critical
- Error rate > 1% for 5min → critical
- p99 latency > SLO threshold for 5min → warning
- DB connection pool pending > 10 for 2min → warning
- Kafka consumer lag > 10k records for 10min → warning
- Circuit breaker open > 60s → critical
- Every alert must have a runbook link in annotations

---

## Contract-First API Design

Design the API contract before writing implementation code. The spec is the source of truth.

### OpenAPI 3.1 (REST)
- Spec location: `src/main/resources/openapi/{service}-api.yaml`
- All IDs: `string format: uuid`; all monetary values: `string` with `^\d+\.\d{2}$` pattern; all timestamps: `string format: date-time`
- Enums: upper snake_case, explicitly listed
- Pagination: `page` (0-based, default 0), `size` (default 20, max 100), `sort` (field,direction)
- All mutating endpoints accept `Idempotency-Key` header (UUID)
- Error responses: RFC 7807 Problem Details (`application/problem+json`) per status code
- Versioning: URL path prefix `/api/v1/`, `/api/v2/`; version on breaking changes only
- Use `openapi-generator-maven-plugin` with `interfaceOnly: true` to generate controller interfaces
- Controller implements generated interface — spec is always the source of truth

### AsyncAPI 3.0 (Events)
- Spec location: `src/main/resources/asyncapi/{service}-events.yaml`
- Every event MUST have: `eventId` (UUID), `eventType` (constant), `eventVersion` (semver), `occurredAt`
- Channel naming: `{domain}.{action}` — `orders.created`, `payments.charged`
- Event types: past-tense nouns — `OrderCreated`, `PaymentCharged`, `ShipmentDelivered`

### gRPC
- Proto files: `src/main/proto/{service}.proto`
- Monetary values in minor units as `int64`; timestamps as `int64` (epoch millis) or `google.protobuf.Timestamp`
- Enum zero value is always `UNSPECIFIED`; package: `{domain}.v{version}`
- Include `idempotency_key` on all mutating RPCs

### GraphQL
- Schema-first: `.graphqls` files in `src/main/resources/graphql/` — never generate schema from code
- Mutations return payloads with `UserError` — never throw for business errors
- Monetary wrapper type (`Money`) with string amount; `ID` type for all identifiers
- `idempotencyKey` on all mutating inputs

### Security Design (Contract-Level)
- Scopes follow `{action}:{resource}` convention — `read:orders`, `write:orders`, `admin:orders`
- Rate limits defined per endpoint group in `x-rate-limit` extensions
- Every endpoint must have security requirements documented in the spec

---

## Performance Testing

Performance test before production to establish throughput limits, latency profiles, and breaking points.

### Load Testing (k6 Recommended)
- Script location: `src/test/k6/{service}-load-test.js`
- Test critical user journeys as multi-step scenarios, not individual endpoints
- Use realistic payloads with unique `Idempotency-Key` per request
- Configure thresholds: `http_req_duration: ['p(95)<500', 'p(99)<1000']`, `http_req_failed: ['rate<0.01']`
- Test types: smoke (1 VU, 30s), load (target VUs, 2m steady), stress (ramp to breaking), soak (moderate load, 30m+)
- Run in CI: `k6 run` with JSON output archived as build artifact

### JVM Profiling
- **JFR** (Java Flight Recorder): `< 2% overhead, production-safe. Enable with `-XX:StartFlightRecording`
- **Async Profiler** (Linux): CPU, allocation, lock, and wall-clock profiles; generate flame graphs
- Profile during load test, not in isolation — real bottlenecks only appear under load
- Hot methods: wide bars at top of flame graph; deep call chains: tall narrow stacks; red frames: syscalls/IO

### Database Profiling
- Enable `pg_stat_statements` (PostgreSQL) to find slow queries under load
- Watch `shared_blks_read` — high values = disk I/O = missing indexes
- Monitor HikariCP during test: `hikaricp_connections_pending > 0` = pool saturated

### Capacity Planning
- Safe capacity = breaking_point_RPS * 0.6
- Instances needed = target_RPS / safe_capacity_per_instance
- Test at incremental VU levels (10, 25, 50, 100, 150, 200) to find the inflection point
- CPU headroom > 20% at peak load; GC pause p99 < 100ms; DB pool not saturated

---

## Release Management

Automate versioning, changelogs, and releases. Manual releases are error-prone.

### Version Bumping
- **Conventional Commits**: `feat:` → MINOR, `fix:` → PATCH, `feat!:` / `BREAKING CHANGE:` → MAJOR
- Parse commits since last tag to determine bump type automatically
- Use `mvn versions:set` (Maven) or update `gradle.properties` (Gradle)
- Multi-module: bump all modules together

### Changelog Format
- Follow Keep a Changelog: `Added`, `Changed`, `Fixed`, `Security`, `Deprecated`, `Removed`
- Each entry links to the PR: `- Description [#NNN](https://github.com/.../pull/NNN)`
- Generate from git log since last tag, grouped by conventional commit type

### Release Artifacts
- Annotated git tag: `git tag -a v1.3.0 -m "release message"`
- GitHub Release: create via `gh release create` or CI automation with changelog as body
- Release notes: internal version (deployer, CI run, migrations, config changes, rollback plan, monitoring) vs external version (new features, bug fixes, API changes)

### CI Automation
- Trigger on tag push: `on: push: tags: ['v*']`
- Build → generate changelog → create GitHub Release → upload artifacts → notify Slack/Teams
- Semantic release (no manual bumping): `@semantic-release` with plugins for commit analysis, changelog, Maven exec, and GitHub release

---

## Dependency Management

Keep dependencies secure, up-to-date, and conflict-free.

### Vulnerability Scanning
- **OWASP dependency-check**: Maven/Gradle plugin; `failBuildOnCVSS: 7` (fail on HIGH and CRITICAL)
- Register for NVD API key to avoid rate limiting
- False positive suppressions must include: why it doesn't apply to your usage + review date + reviewer
- Run in CI on every PR and on a weekly schedule

### Version Management
- **Gradle**: Use version catalog (`gradle/libs.versions.toml`) — single source of truth for all versions
- **Maven multi-module**: Use `<dependencyManagement>` in parent POM
- **Maven multi-service**: Create a shared BOM (`acme-dependencies`) consumed by all services
- Use `maven-enforcer-plugin` with `dependencyConvergence`, `requireUpperBoundDeps`, `banDuplicatePomDependencyVersions`

### Automated Updates
- **Renovate**: patch updates auto-merge; minor auto-PR; major requires dashboard approval
- **Dependabot**: weekly schedule; group Spring deps, test deps; limit 10 open PRs
- Vulnerability alerts: label `security`, auto-PR immediately

### Transitive Conflict Resolution
- Maven: `<dependencyManagement>` overrides all transitive versions
- Gradle: `resolutionStrategy.force()` or version catalog constraints
- Always prefer the Spring Boot managed version unless explicitly needed otherwise
- Run `mvn dependency:tree -Dverbose` to find conflicts; `mvn dependency:analyze` to find unused/direct deps

### Spring Boot Upgrade Checklist
- Check release notes for breaking changes and deprecated APIs
- Update parent version; check Spring Cloud compatibility matrix
- Verify javax→jakarta implications for cross-version upgrades
- Run `mvn clean verify`; check config property changes with `spring-boot-properties-migrator`
- Review security config — DSL may have changed between versions

---

## API Integration

Consuming external APIs requires client generation, configuration, error mapping, and resilience.

### Client Generation
- Use `openapi-generator-maven-plugin` with `library: restclient` to generate typed clients from OpenAPI specs
- Generated clients go in `*.client.{service}` package; generated DTOs in `*.client.{service}.dto`
- Never hand-write HTTP calls when an OpenAPI/Grpc spec is available — use generated clients
- For gRPC: use `protobuf-maven-plugin` to generate stubs, configure `ManagedChannel` with deadline

### HTTP Client Setup
- **Spring Boot 3.x**: Prefer `RestClient` (sync) or `WebClient` (reactive)
- **Spring Boot 2.x**: `RestTemplate` with `RestTemplateBuilder`
- Configure per-service: base URL, auth headers, connect timeout (3-5s), read timeout (5-30s)
- Inject `X-Trace-Id` header via `ClientHttpRequestInterceptor` for distributed tracing
- Set `User-Agent` header identifying your service and version
- Use `@ConfigurationProperties` records for external API config under `integration.{name}`

### Error Mapping
- Map downstream errors to domain exceptions — never expose raw downstream error bodies to your callers
- Use `onStatus()` (RestClient) / `onStatus()` (WebClient) / `ErrorDecoder` (Feign)
- 4xx → domain exception (e.g., `CardDeclinedException`); 5xx → `ServiceUnavailableException`; 429 → `RateLimitException`
- Log downstream errors at WARN (4xx) or ERROR (5xx) level with context

### Caching
- Cache idempotent GET responses: `@Cacheable("product-details")` with TTL
- Invalidate cache on relevant mutations: `@CacheEvict`
- Local: Caffeine (max size, TTL); Distributed: Redis (multi-instance safe)
- Never cache error responses or empty results (use `unless`)

### Webhook Receivers
- Always verify HMAC signature before processing webhook payload
- Reject invalid signatures with 403 immediately — no processing
- Check idempotency: store processed event IDs, return 200 on duplicates
- Process asynchronously: acknowledge with 202, process in background
- Webhook endpoints need higher timeouts and dedicated rate limits

### Integration Testing
- Use WireMock for all external API calls in tests — never hit real APIs in CI
- Stub: success response, 4xx error, 5xx error, timeout, and retry scenarios
- Verify auth headers are sent, error mapping works, and cache TTL is respected

---

## Discovery Fallback — Greenfield Projects

When the target project is empty or has no discoverable conventions:

1. **Do not error out** — default to the universal rules in this document
2. **Establish conventions explicitly** — create the base classes first before implementing features:
   - Root package (ask the user or derive from `groupId` in build file)
   - Error code enum (`ErrorCode` with `code`, `message`, `httpStatus`)
   - Base exception (`extends RuntimeException`, constructor takes `ErrorCode`)
   - Response wrapper (`ApiResponse<T>` with `status`, `message`, `data`, `timestamp`)
   - Global exception handler (`@RestControllerAdvice`)
3. **Use Spring Boot Latest** — default to the newest stable Spring Boot 3.x with Jakarta
4. **Choose sensible defaults** and tell the user what you're assuming:
   - Maven if `pom.xml` exists, else ask
   - Flyway for migrations
   - Lombok for boilerplate reduction
   - MapStruct for entity-DTO mapping
   - Java records for DTOs
   - UUID PKs with `GenerationType.UUID`
5. **Create a minimal CLAUDE.md** if none exists — document the decisions made so future invocations stay consistent

---

## Gradle Dependency Reference

When working with Gradle projects, use these dependency coordinates:

```groovy
// build.gradle / build.gradle.kts
dependencies {
    // Spring Boot starters
    implementation 'org.springframework.boot:spring-boot-starter-web'
    implementation 'org.springframework.boot:spring-boot-starter-data-jpa'
    implementation 'org.springframework.boot:spring-boot-starter-validation'
    implementation 'org.springframework.boot:spring-boot-starter-actuator'

    // Database
    runtimeOnly 'org.postgresql:postgresql'
    runtimeOnly 'org.flywaydb:flyway-database-postgresql'
    implementation 'org.liquibase:liquibase-core'

    // Messaging
    implementation 'org.springframework.cloud:spring-cloud-stream'
    implementation 'org.springframework.cloud:spring-cloud-stream-binder-kafka'
    implementation 'org.springframework.kafka:spring-kafka'

    // Observability
    implementation 'io.micrometer:micrometer-tracing-bridge-brave'
    implementation 'io.micrometer:micrometer-registry-prometheus'
    runtimeOnly 'io.micrometer:micrometer-tracing-reporter-zipkin'

    // Dev tools
    compileOnly 'org.projectlombok:lombok'
    annotationProcessor 'org.projectlombok:lombok'
    implementation 'org.mapstruct:mapstruct:{mapstruct-version}'
    annotationProcessor 'org.mapstruct:mapstruct-processor:{mapstruct-version}'

    // Testing
    testImplementation 'org.springframework.boot:spring-boot-starter-test'
    testImplementation 'org.springframework.boot:spring-boot-testcontainers'
    testImplementation 'org.testcontainers:postgresql'
    testImplementation 'org.testcontainers:kafka'
    testImplementation 'org.springframework.cloud:spring-cloud-stream-test-binder'
    testImplementation 'io.rest-assured:rest-assured'
    testImplementation 'com.tngtech.archunit:archunit-junit5'
}
```

For Kotlin DSL (`build.gradle.kts`), replace single quotes with double quotes and `implementation` stays the same; use `testImplementation("group:artifact")` form.

---

## GitHub Integration & Project Management

The `github` skill and PR review features integrate with GitHub via MCP tools for full project management automation.

### GitHub MCP Tools

All GitHub operations use the `mcp__plugin_github_github__*` family of tools. The skill auto-detects whether these are available and falls back gracefully if not.

**One-time setup**: Create a GitHub Personal Access Token with `repo`, `read:org`, `workflow` scopes. Configure in `~/.claude/settings.json` under `mcpServers.github`.

### Issue/Project Management

**Epics**: Tracked as GitHub issues with `epic` label. Contain a description, story checklist, success criteria, and dependencies.

**User Stories**: GitHub issues with `story` label. Must include:
- User story format (As a / I want / So that)
- Acceptance criteria (Given/When/Then)
- Technical notes
- Definition of Done
- Link to parent epic via comment

**Bug Tickets**: GitHub issues with `bug` label and severity label (`severity:high`, `severity:medium`, `severity:low`). Must include steps to reproduce, expected vs actual behavior, environment details, and logs/stack traces.

**Label Conventions**:
| Label | Purpose |
|-------|---------|
| `epic` | Large bodies of work spanning multiple stories |
| `story` | Individual user stories |
| `bug` | Defect reports |
| `severity:high` / `severity:medium` / `severity:low` | Bug severity |
| `tech-debt` | Technical debt and refactoring items |
| `documentation` | Documentation tasks |
| `dependencies` | Automated dependency PRs (Renovate/Dependabot) |
| `security` | Vulnerability fixes and security patches |
| `major-upgrade` | Major version upgrades requiring review |
| `needs-review` | PRs awaiting human review |

### PR Review Workflow

PR reviews support two entry points:

1. **PR URL**: Parse `owner`, `repo`, `pullNumber` from the URL. Fetch diff, files, check runs, existing reviews via MCP.
2. **Ticket/Issue ID**: Search for PRs referencing the issue. If one found, review it. If multiple, ask user to choose.

Review submission follows the three-step pending review workflow:
1. Create a pending review (method=create, no event)
2. Add inline comments on specific lines (add_comment_to_pending_review)
3. Submit the review (method=submit_pending, event=APPROVE/REQUEST_CHANGES/COMMENT)

Also request Copilot review via `request_copilot_review` as an automated first pass before human review.

### Ticket-to-Code Workflow

When a user asks to "implement ticket #N":

1. Read the issue (method=get) + comments (method=get_comments)
2. Check for existing linked PRs
3. Assign the user if unassigned
4. Add a progress comment with the branch name
5. Implement following write-code conventions
6. Create PR linked via `Closes #N` or `Refs #N`
7. Update the issue with PR link

### GitHub Releases

Use `/devskillslearning-pipeline:release` to automate release creation:
- Create annotated git tag from version
- Generate changelog from conventional commits
- Create GitHub Release via `gh release create` or CI automation
- Attach build artifacts (JAR, Docker image reference)
- Notify Slack/Teams via webhook

### Dependabot / Renovate Integration

Use `/devskillslearning-pipeline:dependency` to configure:
- **Dependabot**: `.github/dependabot.yml` — group Spring deps, test deps; limit open PRs
- **Renovate**: `.github/renovate.json` — patch auto-merge, minor auto-PR, major approval required
- Both label PRs with `dependencies` and `security` (for vulnerability alerts)

### Webhook Receivers

Use `/devskillslearning-pipeline:api-integrate` for receiving GitHub webhooks in your service:
- Verify HMAC signature before processing
- Check idempotency (GitHub may send same event twice)
- Return 202 quickly, process asynchronously

### Commands Quick Reference

```sh
# Read an issue
gh issue view 15 --repo owner/repo

# List open issues
gh issue list --repo owner/repo --label story --state open

# Find PR linked to issue
gh pr list --repo owner/repo --search "fixes #15"

# Create PR from branch
gh pr create --repo owner/repo --title "Add feature X" --body "Closes #15" --base main --head feature/15-x

# Review PR
gh pr review 128 --repo owner/repo --approve
gh pr review 128 --repo owner/repo --request-changes --body "Issues found..."

# Create release
gh release create v1.3.0 --title "v1.3.0" --notes-file changelog.md --target main

# List releases
gh release list --repo owner/repo

# Check Dependabot alerts
gh api /repos/owner/repo/dependabot/alerts --jq '.[] | select(.security_advisory.severity=="critical") | .security_advisory.summary'
```
