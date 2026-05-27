---
name: devskillslearning-pipeline:write-tests
description: Generate comprehensive tests for existing Java/Spring Boot code. Use when the user asks to write tests, add test coverage, or test a specific class/module. Covers unit, web layer, integration, contract, and architecture tests with systematic edge case coverage.
type: skill
---

# Write Tests

You are an expert in testing Java/Spring Boot applications. Generate comprehensive tests that cover happy paths, error paths, edge cases, and architecture invariants. Adapt to the testing stack already in use.

## What You Need to Provide

| Input | Required? | Example | Notes |
|-------|-----------|---------|-------|
| What to test | Yes | `OrderServiceImpl` class | Specific class, module, or "all uncovered code" |
| Test type | No | Unit / Web Layer / Integration / All | I default to "all relevant layers" |
| Specific scenarios | No | "Make sure to test concurrent updates" | Any concerns you want covered |

**Examples**:
- "Write tests for OrderServiceImpl" → Full unit test suite
- "Add tests for the new order endpoints" → Controller + service + integration
- "Add test coverage for the payment module" → All test layers for the module
- "Write tests for ticket #15" → Reads ticket, finds changed files, writes tests

**I auto-discover**: Build system, test frameworks (JUnit 5, Mockito, AssertJ, Testcontainers, WireMock), database type, message broker, Spring Boot version. I match the patterns in your existing tests.

## Step 0: Discover the Project

Follow `docs/shared/step0-discovery.md` to detect build system, Spring Boot version, test frameworks (JUnit 5, Mockito, Testcontainers, RestAssured, ArchUnit, AssertJ, Awaitility), database type, and message broker. Then read the class(es) to test and check existing tests for style patterns to match.

## Step 1: Determine Scope

Based on what the user asked for:
- **Specific class** → full test suite for that class
- **New feature** → all tests for all new classes (service + controller + repository + integration)
- **Existing uncovered code** → scan for uncovered classes and fill gaps
- **Regression suite** → integration tests and contract tests

## Step 2: Generate Tests by Layer

### 2a. Unit Tests — Service Layer

Test every public method. Cover every branch.

```java
@ExtendWith(MockitoExtension.class)
class OrderServiceImplTest {

    @Mock private OrderRepository repository;
    @Mock private OrderMapper mapper;
    @Mock private MeterRegistry meterRegistry;
    @InjectMocks private OrderServiceImpl service;

    // --- Happy path ---

    @Test
    void shouldCreateOrder() {
        var request = new CreateOrderRequest(UUID.randomUUID(), List.of(item("SKU1", 2)));
        var entity = new Order();
        var response = new OrderResponse(UUID.randomUUID(), /* ... */);

        when(repository.existsByOrderNumber(any())).thenReturn(false);
        when(mapper.toEntity(request)).thenReturn(entity);
        when(repository.save(entity)).thenReturn(entity);
        when(mapper.toResponse(entity)).thenReturn(response);

        var result = service.createOrder(request);

        assertThat(result).isNotNull();
        assertThat(result.customerId()).isEqualTo(request.customerId());
        verify(repository).save(entity);
        verify(mapper).toResponse(entity);
    }

    // --- Not found ---

    @Test
    void shouldThrowWhenOrderNotFound() {
        when(repository.findById(any())).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.getOrder(UUID.randomUUID()))
            .isInstanceOf(ResourceNotFoundException.class)
            .hasMessageContaining("Order not found");
    }

    // --- Duplicate / conflict ---

    @Test
    void shouldThrowWhenDuplicateOrderNumber() {
        when(repository.existsByOrderNumber(any())).thenReturn(true);

        assertThatThrownBy(() -> service.createOrder(request))
            .isInstanceOf(ConflictException.class);
    }

    // --- Invalid state transitions ---

    @Test
    void shouldThrowWhenCancellingAlreadyShippedOrder() {
        var entity = new Order();
        entity.setStatus(OrderStatus.SHIPPED);
        when(repository.findById(any())).thenReturn(Optional.of(entity));

        assertThatThrownBy(() -> service.cancelOrder(UUID.randomUUID()))
            .isInstanceOf(IllegalStateException.class)
            .hasMessageContaining("Cannot cancel shipped order");
    }

    // --- Null/empty inputs ---

    @Test
    void shouldThrowWhenRequestIsNull() {
        assertThatThrownBy(() -> service.createOrder(null))
            .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void shouldThrowWhenItemsListIsEmpty() {
        var request = new CreateOrderRequest(UUID.randomUUID(), List.of());
        assertThatThrownBy(() -> service.createOrder(request))
            .isInstanceOf(BadRequestException.class);
    }

    // --- Boundary conditions ---

    @Test
    void shouldHandleMaximumOrderAmount() {
        var request = new CreateOrderRequest(UUID.randomUUID(),
            List.of(item("SKU1", 999)));
        // verify no overflow or unexpected behavior
        var result = service.createOrder(request);
        assertThat(result).isNotNull();
    }

    // --- Transaction rollback ---

    @Test
    void shouldNotPersistWhenRepositoryThrows() {
        when(repository.save(any())).thenThrow(new DataIntegrityViolationException("constraint violation"));

        assertThatThrownBy(() -> service.createOrder(request))
            .isInstanceOf(DataIntegrityViolationException.class);
        verify(repository, never()).flush();
    }
}
```

**Edge case checklist for every service method**:
- [ ] Null input → `IllegalArgumentException` or `BadRequestException`
- [ ] Empty collections → `BadRequestException` or empty result
- [ ] Resource not found → `ResourceNotFoundException`
- [ ] Duplicate/conflict → `ConflictException`
- [ ] Invalid state transition → `IllegalStateException`
- [ ] Maximum/minimum values → handled correctly
- [ ] Concurrent modification → `@Version` field tested via `ObjectOptimisticLockingFailureException`
- [ ] Repository/dependency throws → exception propagated or wrapped correctly

### 2b. Web Layer Tests — Controllers

Test every endpoint for HTTP status, response body, and validation.

```java
@WebMvcTest(OrderController.class)
class OrderControllerTest {

    @Autowired private MockMvc mockMvc;
    @MockBean private OrderService service;

    private static final String BASE_URL = "/api/v1/orders";

    // --- Happy path ---

    @Test
    void shouldReturnOrder() throws Exception {
        var response = new OrderResponse(UUID.randomUUID(), /* ... */);
        when(service.getOrder(any())).thenReturn(response);

        mockMvc.perform(get(BASE_URL + "/{id}", UUID.randomUUID()))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.success").value(true))
            .andExpect(jsonPath("$.data.id").isNotEmpty());
    }

    @Test
    void shouldCreateOrder() throws Exception {
        var request = """
            {
                "customerId": "%s",
                "items": [{"sku": "SKU1", "quantity": 2}]
            }
            """.formatted(UUID.randomUUID());
        when(service.createOrder(any())).thenReturn(response);

        mockMvc.perform(post(BASE_URL)
                .contentType(MediaType.APPLICATION_JSON)
                .content(request))
            .andExpect(status().isCreated())
            .andExpect(header().exists("Location"));
    }

    // --- Validation errors ---

    @Test
    void shouldReturn400OnMissingRequiredField() throws Exception {
        mockMvc.perform(post(BASE_URL)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{}"))
            .andExpect(status().isBadRequest());
    }

    @Test
    void shouldReturn400OnInvalidUUID() throws Exception {
        mockMvc.perform(get(BASE_URL + "/{id}", "not-a-uuid"))
            .andExpect(status().isBadRequest());
    }

    @Test
    void shouldReturn400OnNegativeQuantity() throws Exception {
        var request = """
            {"customerId": "%s", "items": [{"sku": "SKU1", "quantity": -1}]}
            """.formatted(UUID.randomUUID());

        mockMvc.perform(post(BASE_URL)
                .contentType(MediaType.APPLICATION_JSON)
                .content(request))
            .andExpect(status().isBadRequest());
    }

    // --- Error responses ---

    @Test
    void shouldReturn404WhenNotFound() throws Exception {
        when(service.getOrder(any()))
            .thenThrow(new ResourceNotFoundException(ErrorCode.RESOURCE_NOT_FOUND, "Not found"));

        mockMvc.perform(get(BASE_URL + "/{id}", UUID.randomUUID()))
            .andExpect(status().isNotFound())
            .andExpect(jsonPath("$.errorCode").value("RESOURCE_NOT_FOUND"));
    }

    @Test
    void shouldReturn409OnConflict() throws Exception {
        when(service.createOrder(any()))
            .thenThrow(new ConflictException(ErrorCode.CONFLICT, "Duplicate"));

        mockMvc.perform(post(BASE_URL)
                .contentType(MediaType.APPLICATION_JSON)
                .content(validRequest))
            .andExpect(status().isConflict());
    }

    // --- Content type / Accept header ---

    @Test
    void shouldReturn415OnWrongContentType() throws Exception {
        mockMvc.perform(post(BASE_URL)
                .contentType(MediaType.TEXT_PLAIN)
                .content("text"))
            .andExpect(status().isUnsupportedMediaType());
    }
}
```

**Edge case checklist for every controller**:
- [ ] Missing required fields → 400
- [ ] Invalid data types (string for UUID, negative for @Positive) → 400
- [ ] Malformed JSON → 400
- [ ] Wrong content type → 415
- [ ] Not found → 404
- [ ] Conflict / duplicate → 409
- [ ] Invalid state → 422 (or 409)
- [ ] Missing auth token (if secured) → 401/403
- [ ] Large payload → handled or 413

**Reactive variant** (`@WebFluxTest` + `WebTestClient`):
```java
@WebFluxTest(AccountController.class)
class AccountControllerTest {
    @Autowired private WebTestClient webTestClient;
    @MockBean private AccountService service;

    @Test
    void shouldReturnAccount() {
        when(service.getAccount(any())).thenReturn(Mono.just(response));

        webTestClient.get().uri("/api/v1/accounts/{id}", UUID.randomUUID())
            .exchange()
            .expectStatus().isOk()
            .expectBody()
            .jsonPath("$.success").isEqualTo(true)
            .jsonPath("$.data.id").isNotEmpty();
    }

    @Test
    void shouldReturnEmptyBodyOn404() {
        when(service.getAccount(any())).thenReturn(Mono.empty());

        webTestClient.get().uri("/api/v1/accounts/{id}", UUID.randomUUID())
            .exchange()
            .expectStatus().isNotFound();
    }
}
```

### 2c. Integration Tests

Test the full stack with a real database and message broker.

**Spring Boot 3.1+** — use `@ServiceConnection` (auto-configures Testcontainers, no boilerplate):
```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Testcontainers
class OrderIntegrationTest {

    @Container
    @ServiceConnection  // auto-configures spring.datasource.* from the container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @Autowired private TestRestTemplate restTemplate;
```

**Spring Boot 3.0 and below** — use `@DynamicPropertySource`:
```java
@Container
static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

@DynamicPropertySource
static void configure(DynamicPropertyRegistry registry) {
    registry.add("spring.datasource.url", postgres::getJdbcUrl);
    registry.add("spring.datasource.username", postgres::getUsername);
    registry.add("spring.datasource.password", postgres::getPassword);
}
```

**Integration test examples:**
```java
    @Autowired private TestRestTemplate restTemplate;

    // --- End-to-end happy path ---

    @Test
    void shouldCreateAndRetrieveOrder() {
        // Create
        var request = new CreateOrderRequest(UUID.randomUUID(), List.of(item));
        var createResponse = restTemplate.postForEntity(
            "/api/v1/orders", request, ApiResponse.class);
        assertThat(createResponse.getStatusCode()).isEqualTo(HttpStatus.CREATED);

        // Retrieve
        var location = createResponse.getHeaders().getLocation();
        var getResponse = restTemplate.getForEntity(location, ApiResponse.class);
        assertThat(getResponse.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    // --- Database constraints ---

    @Test
    void shouldRejectDuplicateOrderNumber() {
        var request = new CreateOrderRequest(UUID.randomUUID(), List.of(item));
        restTemplate.postForEntity("/api/v1/orders", request, ApiResponse.class);

        // Try again — should fail
        var duplicate = restTemplate.postForEntity(
            "/api/v1/orders", request, ApiResponse.class);
        assertThat(duplicate.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
    }

    // --- Transaction rollback ---

    @Test
    void shouldRollbackOnFailure() {
        var countBefore = restTemplate.getForObject(
            "/api/v1/orders/count", Long.class);

        // Attempt to create with invalid data that passes validation but fails at DB
        // Verify count hasn't changed

        var countAfter = restTemplate.getForObject(
            "/api/v1/orders/count", Long.class);
        assertThat(countAfter).isEqualTo(countBefore);
    }

    // --- Concurrency ---

    @Test
    void shouldHandleConcurrentUpdates() throws Exception {
        var id = createOrder();
        var executor = Executors.newFixedThreadPool(2);

        var futures = IntStream.range(0, 2).mapToObj(i ->
            executor.submit(() -> restTemplate.exchange(
                "/api/v1/orders/" + id + "/status",
                HttpMethod.PUT,
                new HttpEntity<>(new UpdateStatusRequest(OrderStatus.CONFIRMED)),
                ApiResponse.class))
        ).toList();

        // One should succeed, one should fail with optimistic lock
        var results = futures.stream().map(f -> {
            try { return f.get(5, TimeUnit.SECONDS); }
            catch (Exception e) { return null; }
        }).toList();

        assertThat(results.stream().filter(r -> r != null && r.getStatusCode().is2xxSuccessful()))
            .hasSize(1);
    }
}
```

### 2d. WireMock — Stub External HTTP Dependencies

When the service calls external REST APIs, use WireMock to stub them in integration tests:

```java
@SpringBootTest(webEnvironment = RANDOM_PORT)
@WireMockTest(httpPort = 9090)
class OrderServiceIntegrationTest {

    @Autowired private TestRestTemplate restTemplate;

    @Test
    void shouldCallPaymentService() {
        // Stub the external service
        stubFor(post(urlPathEqualTo("/payments"))
            .withHeader("Authorization", containing("Bearer"))
            .willReturn(aResponse()
                .withStatus(201)
                .withHeader("Content-Type", "application/json")
                .withBody("{\"paymentId\": \"pay-123\", \"status\": \"COMPLETED\"}")));

        // Act
        var response = restTemplate.postForEntity("/api/v1/orders", request, ApiResponse.class);

        // Assert
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);

        // Verify the external call was made exactly once
        verify(1, postRequestedFor(urlPathEqualTo("/payments")));
    }

    @Test
    void shouldHandlePaymentServiceTimeout() {
        stubFor(post(urlPathEqualTo("/payments"))
            .willReturn(aResponse()
                .withStatus(200)
                .withFixedDelay(6000)));  // simulate timeout

        var response = restTemplate.postForEntity("/api/v1/orders", request, ApiResponse.class);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
    }

    @Test
    void shouldHandlePaymentService500() {
        stubFor(post(urlPathEqualTo("/payments"))
            .willReturn(aResponse().withStatus(500)));

        var response = restTemplate.postForEntity("/api/v1/orders", request, ApiResponse.class);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_GATEWAY);
    }
}
```

Rules:
- `@WireMockTest(httpPort = 9090)` — use fixed port; configure client base URL via `@ConfigurationProperties` to point to `localhost:9090`
- Stub before every test; use `stubFor(...)` for reusable stubs or `wireMock.register(...)` in `@BeforeEach`
- Verify interactions: `verify(count, postRequestedFor(...))` — ensures the external call actually happened
- Test failure modes: timeout (`withFixedDelay`), 5xx, connection refused, malformed response
- Use `WireMock.stubFor()` with `urlPathMatching` for dynamic URLs

### 2e. Test Slices — Lightweight Integration Tests

Spring Boot test slices start only the beans relevant to a specific layer — much faster than `@SpringBootTest`:

**`@DataJpaTest`** — JPA repository tests with embedded or Testcontainers DB:
```java
@DataJpaTest
@AutoConfigureTestDatabase(replace = NONE)  // use real DB, not H2
@Testcontainers
class OrderRepositoryTest {
    @Container @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @Autowired private OrderRepository repository;
    @Autowired private TestEntityManager em;

    @Test
    void shouldFindByCustomerId() { ... }
}
```

**`@RestClientTest`** — REST client tests with MockRestServiceServer:
```java
@RestClientTest(PaymentClient.class)
class PaymentClientTest {
    @Autowired private PaymentClient client;
    @Autowired private MockRestServiceServer server;

    @Test
    void shouldCallPaymentService() {
        server.expect(requestTo("http://localhost:9090/payments"))
            .andRespond(withSuccess("{\"paymentId\":\"123\"}", MediaType.APPLICATION_JSON));

        var result = client.processPayment(request);
        assertThat(result.paymentId()).isEqualTo("123");
    }
}
```

**`@JsonTest`** — JSON serialization/deserialization tests:
```java
@JsonTest
class OrderJsonTest {
    @Autowired private JacksonTester<OrderResponse> json;

    @Test
    void shouldSerializeOrder() throws Exception {
        var order = new OrderResponse(UUID.randomUUID(), /* ... */);
        assertThat(json.write(order))
            .hasJsonPathStringValue("@.id")
            .hasJsonPathNumberValue("@.totalAmount");
    }

    @Test
    void shouldDeserializeCreateRequest() throws Exception {
        var content = """
            {"customerId": "%s", "items": [{"sku": "SKU1", "quantity": 2}]}
            """.formatted(UUID.randomUUID());
        assertThat(json.parse(content))
            .hasFieldOrPropertyWithValue("items[0].quantity", 2);
    }
}
```

**`@WebMvcTest`** — Controller layer (already covered in 2b above).

**`@JdbcTest`** — JDBC queries without JPA overhead.

Rules:
- Prefer test slices over `@SpringBootTest` when only testing a single layer
- `@DataJpaTest` + `@ServiceConnection` + Testcontainers for repository tests (real DB, no mocking)
- `@RestClientTest` + `MockRestServiceServer` for HTTP client tests (no real HTTP calls)
- `@JsonTest` for verifying serialization/deserialization of DTOs
- Test slices start in ~1-2 seconds vs ~15-30 seconds for `@SpringBootTest`

### 2f. Event-Driven Tests

When the project uses message brokers:

```java
@SpringBootTest
@Testcontainers
class OrderEventIntegrationTest {

    @Container
    @ServiceConnection  // auto-configures spring.kafka.bootstrap-servers
    static KafkaContainer kafka = new KafkaContainer(
        DockerImageName.parse("confluentinc/cp-kafka:7.6.0"));

    @Autowired private KafkaTemplate<String, Object> kafkaTemplate;
    @Autowired private OrderRepository repository;

    @Test
    void shouldConsumeOrderShippedEvent() {
        var order = createOrderInDB();
        var event = new OrderShippedEvent(order.getId(), Instant.now());

        kafkaTemplate.send("order-events", order.getId().toString(), event);

        await().atMost(5, TimeUnit.SECONDS)
            .untilAsserted(() -> {
                var updated = repository.findById(order.getId()).orElseThrow();
                assertThat(updated.getStatus()).isEqualTo(OrderStatus.SHIPPED);
            });
    }

    @Test
    void shouldHandleDuplicateEvent() {
        var event = new OrderShippedEvent(UUID.randomUUID(), Instant.now());

        // Send twice
        kafkaTemplate.send("order-events", event.orderId().toString(), event);
        kafkaTemplate.send("order-events", event.orderId().toString(), event);

        // Should not fail, should only process once
        await().during(2, TimeUnit.SECONDS)
            .untilAsserted(() -> { /* no error logged */ });
    }

    @Test
    void shouldSendToDeadLetterOnPoisonMessage() {
        kafkaTemplate.send("order-events", "invalid-key", "invalid-json");
        // Verify consumer doesn't crash, message routed to DLT
    }
}
```

**Event-driven test checklist**:
- [ ] Producer: correct topic, payload, key, headers
- [ ] Consumer: idempotency (duplicate events)
- [ ] Consumer: poison message → dead-letter topic
- [ ] Atomicity: event published only on successful DB commit (outbox)
- [ ] Ordering: events within same partition processed in order (if required)
- [ ] Schema: event matches Avro/JSON Schema if schema registry is used

### 2g. Repository Tests

```java
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Testcontainers
class OrderRepositoryTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @Autowired private OrderRepository repository;

    @Test
    void shouldFindByCustomerIdWithPagination() {
        var customerId = UUID.randomUUID();
        repository.saveAll(IntStream.range(0, 15)
            .mapToObj(i -> createOrder(customerId)).toList());

        var page = repository.findByCustomerId(customerId, PageRequest.of(0, 10));

        assertThat(page.getContent()).hasSize(10);
        assertThat(page.getTotalElements()).isEqualTo(15);
        assertThat(page.getTotalPages()).isEqualTo(2);
    }

    @Test
    void shouldReturnEmptyForNonExistentCustomer() {
        var page = repository.findByCustomerId(
            UUID.randomUUID(), PageRequest.of(0, 10));
        assertThat(page.getContent()).isEmpty();
    }

    @Test
    void shouldFindWithEntityGraph() {
        var order = createOrderWithItems();
        var found = repository.findWithItemsById(order.getId());
        assertThat(found).isPresent();
        // Items should be loaded without additional query (verify via SQL count or Hibernate statistics)
        assertThat(found.get().getItems()).isNotEmpty();
    }
}
```

### 2h. Architecture Tests

```java
@AnalyzeClasses(packages = "com.<company>.<artifact>")
public class ArchitectureTest {

    @ArchTest
    static final ArchRule noAutowiredFields = noFields()
        .should().beAnnotatedWith(Autowired.class);

    @ArchTest
    static final ArchRule controllersShouldNotAccessRepositories = noClasses()
        .that().resideInAPackage("..controller..")
        .should().dependOnClassesThat().resideInAPackage("..repository..");

    @ArchTest
    static final ArchRule serviceInterfacesInServicePackage = classes()
        .that().areInterfaces().and().haveSimpleNameEndingWith("Service")
        .should().resideInAPackage("..service..");

    @ArchTest
    static final ArchRule noDataOnEntities = noClasses()
        .that().areAnnotatedWith(Entity.class)
        .should().beAnnotatedWith(Data.class);

    @ArchTest
    static final ArchRule entitiesMustHaveAuditFields = fields()
        .that().areDeclaredInClassesThat().areAnnotatedWith(Entity.class)
        .and().haveName("createdAt").or().haveName("updatedAt")
        .should().exist();

    @ArchTest
    static final ArchRule noJavaxOnSpringBoot3 = noClasses()
        .should().dependOnClassesThat().resideInAPackage("javax..");
}
```

### 2i. Contract Tests (when OpenAPI is present)

If the project has OpenAPI specs, add contract tests using Spring Cloud Contract or manual verification:

```java
@SpringBootTest(webEnvironment = RANDOM_PORT)
class OrderApiContractTest {

    @Autowired private TestRestTemplate restTemplate;

    @Test
    void getOrderResponseMatchesSchema() {
        var id = createOrder();
        var response = restTemplate.getForEntity("/api/v1/orders/" + id, JsonNode.class);

        // Verify response matches OpenAPI schema
        assertThat(response.getBody().has("id")).isTrue();
        assertThat(response.getBody().has("status")).isTrue();
        assertThat(response.getBody().has("items")).isTrue();
        assertThat(response.getBody().get("items").isArray()).isTrue();
        // Verify field types match spec
        assertThat(response.getBody().get("totalAmount").isNumber()).isTrue();
    }
}
```

## Step 3: Test Data Factories

Generate test data builders/factories for the domain objects:

```java
public class OrderTestFactory {

    public static CreateOrderRequest createOrderRequest() {
        return new CreateOrderRequest(
            UUID.randomUUID(),
            List.of(new OrderItemRequest("SKU-001", 2, new BigDecimal("29.99")))
        );
    }

    public static Order orderEntity() {
        var order = new Order();
        order.setId(UUID.randomUUID());
        order.setOrderNumber("ORD-" + UUID.randomUUID().toString().substring(0, 8));
        order.setCustomerId(UUID.randomUUID());
        order.setStatus(OrderStatus.PENDING);
        order.setTotalAmount(new BigDecimal("59.98"));
        order.setCreatedAt(Instant.now());
        order.setUpdatedAt(Instant.now());
        return order;
    }
}
```

## Step 4: Verify

Run the tests:

```sh
# Maven
mvn test -pl :module-name
mvn test -pl :module-name -Dtest=OrderServiceImplTest
mvn test -pl :module-name -Dtest=OrderServiceImplTest#shouldCreateOrder

# Gradle
./gradlew :module-name:test
./gradlew :module-name:test --tests "com.x.OrderServiceImplTest"
./gradlew :module-name:test --tests "com.x.OrderServiceImplTest.shouldCreateOrder"
```

## Coverage Targets

Aim for these minimums per layer:

| Layer | Line Coverage | Branch Coverage | Notes |
|-------|--------------|-----------------|-------|
| Service | 90%+ | 85%+ | Every public method tested; every exception path covered |
| Controller | 85%+ | 80%+ | Every endpoint, every status code, validation errors |
| Entity | 80%+ | — | Business methods, not getters/setters |
| Repository | 60%+ | — | Custom queries only; derived queries rely on Spring Data correctness |
| Integration | — | — | Full happy path + at least one failure path per endpoint |

## Checklist

Before finishing:
- [ ] Every public method has at least one test
- [ ] Happy path covered for every method
- [ ] Not-found error case covered
- [ ] Duplicate/conflict error case covered
- [ ] Invalid state transition covered
- [ ] Null/empty input edge cases covered
- [ ] Validation errors covered (every `@NotNull`, `@Valid` constraint)
- [ ] Tests use proper assertion library (AssertJ preferred over JUnit assertions)
- [ ] No `Thread.sleep()` — use `Awaitility` for async tests
- [ ] Test data isolated — no shared mutable state between tests
- [ ] `@Transactional` on integration tests that modify data (rollback after each test)
- [ ] Tests compile and pass

## Next Step
After tests are written and passing, use `/devskillslearning-pipeline:code-review` to review the code before merging.
