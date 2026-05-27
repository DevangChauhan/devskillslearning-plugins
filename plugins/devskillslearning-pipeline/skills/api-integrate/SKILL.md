---
name: devskillslearning-pipeline:api-integrate
description: [Build] Consume external REST/gRPC/GraphQL APIs in Spring Boot — OpenAPI client generation, RestClient/WebClient setup, error mapping, caching, webhook receivers. Use when: call external API, generate client from OpenAPI, set up webhooks.
type: skill
---

# API Integration

You are an integration engineer consuming third-party APIs from a Java/Spring Boot application. Your goal: build robust, resilient, and cached external API integrations.

## What You Need to Provide

| Input | Required? | Example | Notes |
|-------|-----------|---------|-------|
| What to integrate | Yes | "Integrate the Stripe Payment API" | External service and purpose |
| API spec or docs URL | Recommended | `https://api.stripe.com/openapi.yaml` | I'll generate the client from this |
| Auth method | Recommended | API key / OAuth2 client credentials / mTLS | I'll configure the auth |
| Endpoints to call | If no spec | "POST /v1/charges, GET /v1/charges/{id}, POST /v1/refunds" | The specific operations |
| Caching requirements | No | "Cache product details for 30 minutes" | What to cache and TTL |

**Examples**:
- "Integrate the Stripe API from their OpenAPI spec — charge and refund endpoints"
- "Set up a client for the shipping carrier API with API key auth and retry"
- "Call the internal inventory service gRPC API from the order service"
- "Generate a typed client from the payment service OpenAPI spec"
- "Add caching and circuit breaker to the tax API integration"

**I auto-discover**: Existing HTTP client config (RestClient/WebClient/RestTemplate/Feign), Spring Boot version, resilience config, cache config, existing API integrations as patterns.

## Step 0: Discover the Project

Follow `docs/shared/step0-discovery.md` to detect build system, Spring Boot version, architecture type, package layout, and all project conventions.

## Step 1: Determine Scope

| Request | What to implement |
|---------|-------------------|
| "Generate client from OpenAPI spec" | Generated typed client + HTTP config + auth |
| "Call external REST API" | RestClient/WebClient config + DTOs + error mapping + resilience |
| "Call gRPC service" | gRPC stub + channel config + deadline |
| "Call GraphQL API" | GraphQL client + query/mutation documents |
| "Add caching to API calls" | Caffeine/Redis cache + TTL + cache invalidation |
| "Set up webhook receiver" | Webhook controller + signature verification + idempotency |
| "Full API integration" | Client generation + config + auth + resilience + caching + error mapping |

## Step 2: Implement

### 2a. Client Generation from OpenAPI

**Maven plugin — generate typed client from remote spec:**
```xml
<plugin>
    <groupId>org.openapitools</groupId>
    <artifactId>openapi-generator-maven-plugin</artifactId>
    <version>7.8.0</version>
    <executions>
        <execution>
            <goals><goal>generate</goal></goals>
            <configuration>
                <inputSpec>${project.basedir}/src/main/resources/openapi/stripe-api.yaml</inputSpec>
                <generatorName>java</generatorName>
                <library>restclient</library>
                <generateApis>true</generateApis>
                <generateModels>true</generateModels>
                <apiPackage>com.acme.orderservice.client.stripe</apiPackage>
                <modelPackage>com.acme.orderservice.client.stripe.dto</modelPackage>
                <configOptions>
                    <useJakartaEe>true</useJakartaEe>
                    <openApiNullable>false</openApiNullable>
                </configOptions>
            </configuration>
        </execution>
    </executions>
</plugin>
```

**Download the spec first:**
```sh
curl -o src/main/resources/openapi/stripe-api.yaml https://api.stripe.com/openapi.yaml
```

### 2b. RestClient Setup (Spring Boot 3.x — Recommended)

```java
@Configuration
public class PaymentClientConfig {

    @Bean
    @ConfigurationProperties(prefix = "integration.payment")
    public PaymentClientConfig paymentClientProperties() {
        return new PaymentClientConfig();
    }

    @Bean
    public RestClient paymentRestClient(RestClient.Builder builder,
                                         PaymentClientConfig config) {
        return builder
            .baseUrl(config.baseUrl())
            .defaultHeader("X-API-Key", config.apiKey())
            .defaultHeader("User-Agent", "order-service/1.0")
            .requestInterceptor((request, body, execution) -> {
                // Inject trace ID for distributed tracing
                var traceId = currentTraceId();
                if (traceId != null) request.getHeaders().add("X-Trace-Id", traceId);
                return execution.execute(request, body);
            })
            .requestFactory(clientHttpRequestFactory(config))
            .build();
    }

    private ClientHttpRequestFactory clientHttpRequestFactory(PaymentClientConfig config) {
        var factory = new HttpComponentsClientHttpRequestFactory();
        factory.setConnectTimeout(config.connectTimeout());
        factory.setReadTimeout(config.readTimeout());
        return factory;
    }
}
```

**Config record:**
```java
@ConfigurationProperties(prefix = "integration.payment")
public record PaymentClientConfig(
    @NotBlank String baseUrl,
    @NotBlank String apiKey,
    Duration connectTimeout,
    Duration readTimeout
) {
    public PaymentClientConfig() {
        this("https://api.payment.example.com", "", Duration.ofSeconds(5), Duration.ofSeconds(30));
    }
}
```

**Client class wrapping the generated or manual HTTP calls:**
```java
@Component
@RequiredArgsConstructor
@Slf4j
public class PaymentClient {
    private final RestClient restClient;
    private final PaymentClientConfig config;

    public PaymentResponse charge(ChargeRequest request) {
        log.info("Charging payment: orderId={} amount={}", request.orderId(), request.amount());
        return restClient
            .post()
            .uri("/v1/charges")
            .body(request)
            .retrieve()
            .onStatus(status -> status.value() == 429, (req, res) -> {
                throw new RateLimitException("Payment API rate limited");
            })
            .onStatus(HttpStatusCode::is4xxClientError, (req, res) -> {
                var error = parseError(res);
                log.warn("Payment API client error: {} {}", res.getStatusCode(), error);
                throw new DownstreamClientException(
                    "Payment API error: " + res.getStatusCode(), error);
            })
            .onStatus(HttpStatusCode::is5xxServerError, (req, res) -> {
                log.error("Payment API server error: {}", res.getStatusCode());
                throw new DownstreamServerException("Payment API unavailable");
            })
            .body(PaymentResponse.class);
    }
}
```

### 2c. WebClient Setup (Reactive Stack)

```java
@Configuration
public class InventoryClientConfig {

    @Bean
    public WebClient inventoryWebClient(WebClient.Builder builder,
                                         @Value("${integration.inventory.base-url}") String baseUrl) {
        return builder
            .baseUrl(baseUrl)
            .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
            .filter((request, next) -> {
                log.debug("Calling inventory: {} {}", request.method(), request.url());
                return next.exchange(request);
            })
            .build();
    }
}
```

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class InventoryClient {
    private final WebClient webClient;

    public Mono<InventoryResponse> checkStock(UUID productId) {
        return webClient
            .get()
            .uri("/api/v1/inventory/{productId}", productId)
            .retrieve()
            .onStatus(HttpStatusCode::isError, res ->
                res.bodyToMono(ProblemDetail.class)
                    .flatMap(error -> Mono.error(
                        new DownstreamException("Inventory check failed: " + error.getDetail()))))
            .bodyToMono(InventoryResponse.class)
            .timeout(Duration.ofSeconds(3));
    }
}
```

### 2d. Feign Client (Declarative)

```java
@FeignClient(
    name = "shipping-service",
    url = "${integration.shipping.base-url}",
    configuration = ShippingFeignConfig.class
)
public interface ShippingClient {

    @PostMapping("/api/v1/rates")
    ShippingRateResponse getRates(@RequestBody ShippingRateRequest request);

    @PostMapping("/api/v1/shipments")
    ShipmentResponse createShipment(@RequestBody CreateShipmentRequest request);

    @GetMapping("/api/v1/shipments/{trackingNumber}/track")
    TrackingResponse track(@PathVariable String trackingNumber);
}
```

```java
@Configuration
public class ShippingFeignConfig {

    @Bean
    public RequestInterceptor apiKeyInterceptor(
            @Value("${integration.shipping.api-key}") String apiKey) {
        return request -> request.header("X-API-Key", apiKey);
    }

    @Bean
    public ErrorDecoder errorDecoder() {
        return (methodKey, response) -> {
            return switch (response.status()) {
                case 429 -> new RateLimitException("Shipping API rate limited");
                case 503 -> new DownstreamServerException("Shipping API unavailable");
                default -> new DownstreamClientException("Shipping API error: " + response.status());
            };
        };
    }
}
```

### 2e. gRPC Client

```java
@Configuration
public class InventoryGrpcConfig {

    @Bean
    public InventoryServiceGrpc.InventoryServiceBlockingStub inventoryStub(
            @Value("${integration.inventory.grpc.host}") String host,
            @Value("${integration.inventory.grpc.port}") int port) {
        var channel = ManagedChannelBuilder
            .forAddress(host, port)
            .useTransportSecurity()
            .build();
        return InventoryServiceGrpc.newBlockingStub(channel)
            .withDeadlineAfter(5, TimeUnit.SECONDS);
    }
}
```

**Config:**
```yaml
integration:
  inventory:
    grpc:
      host: ${INVENTORY_GRPC_HOST:inventory.internal}
      port: ${INVENTORY_GRPC_PORT:9090}
```

### 2f. External API Error Mapping

Map downstream errors to domain exceptions — never expose raw downstream errors to callers:

```java
@Component
@Slf4j
public class PaymentClient {
    private final RestClient restClient;
    private final ObjectMapper objectMapper;

    public PaymentResponse charge(ChargeRequest request) {
        try {
            return restClient
                .post()
                .uri("/v1/charges")
                .body(request)
                .retrieve()
                .body(PaymentResponse.class);
        } catch (DownstreamClientException e) {
            // Client errors (4xx): map to domain exceptions based on downstream error code
            var paymentError = e.getErrorBody();
            return switch (paymentError.code()) {
                case "card_declined" -> throw new CardDeclinedException(paymentError.message());
                case "insufficient_funds" -> throw new InsufficientFundsException(paymentError.message());
                case "expired_card" -> throw new ExpiredCardException(paymentError.message());
                default -> throw new PaymentFailedException("Payment failed: " + paymentError.message());
            };
        } catch (DownstreamServerException e) {
            // Server errors (5xx): circuit breaker should kick in after threshold
            log.error("Payment API unavailable", e);
            throw new ServiceUnavailableException("Payment service temporarily unavailable");
        } catch (RateLimitException e) {
            log.warn("Payment API rate limited");
            throw new ServiceUnavailableException("Payment service busy — please retry");
        }
    }
}
```

**Downstream error DTO:**
```java
public record PaymentError(String code, String message, String param) {}

public class DownstreamClientException extends RuntimeException {
    @Getter private final PaymentError errorBody;
    public DownstreamClientException(String message, PaymentError errorBody) {
        super(message);
        this.errorBody = errorBody;
    }
}
```

### 2g. Caching External API Responses

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class ProductService {
    private final ProductClient productClient;
    private final CacheManager cacheManager;

    @Cacheable(value = "product-details", key = "#productId", unless = "#result == null")
    public ProductResponse getProduct(UUID productId) {
        log.debug("Cache miss — fetching product: {}", productId);
        return productClient.getProduct(productId);
    }

    @CacheEvict(value = "product-details", key = "#productId")
    public void invalidateProductCache(UUID productId) {
        log.debug("Invalidated product cache: {}", productId);
    }

    // Cache entire search results only for common queries
    @Cacheable(value = "product-search", key = "{#query, #page, #size}",
               unless = "#result.content.isEmpty()")
    public ProductPage searchProducts(String query, int page, int size) {
        return productClient.search(query, page, size);
    }
}
```

**Cache config (Caffeine — local; Redis — distributed):**
```yaml
spring:
  cache:
    type: caffeine
    caffeine:
      spec: |
        expireAfterWrite=30m,maximumSize=500
    cache-names:
      - product-details
      - product-search
```

**Redis for distributed caching (multi-instance):**
```yaml
spring:
  cache:
    type: redis
    redis:
      time-to-live: 30m
      cache-null-values: false
```

### 2h. Webhook Receiver

Receiving webhooks from external services:

```java
@RestController
@RequestMapping("/webhooks")
@RequiredArgsConstructor
@Slf4j
public class StripeWebhookController {
    private final PaymentWebhookService service;
    private final WebhookVerifier verifier;

    @PostMapping("/stripe")
    public ResponseEntity<Void> handleStripeWebhook(
            @RequestBody String payload,
            @RequestHeader("Stripe-Signature") String signature,
            @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey) {

        // 1. Verify signature — reject immediately if invalid
        if (!verifier.verifyStripeSignature(payload, signature)) {
            log.warn("Invalid Stripe webhook signature");
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }

        // 2. Parse event
        var event = verifier.parseEvent(payload);

        // 3. Check idempotency — don't process the same event twice
        if (service.isEventProcessed(event.id())) {
            log.info("Duplicate webhook ignored: eventId={}", event.id());
            return ResponseEntity.ok().build();
        }

        // 4. Process asynchronously — acknowledge quickly
        service.processAsync(event);
        log.info("Webhook accepted: eventId={} type={}", event.id(), event.type());
        return ResponseEntity.accepted().build();
    }
}

@Component
public class WebhookVerifier {
    private final String webhookSecret;

    public WebhookVerifier(@Value("${integration.stripe.webhook-secret}") String secret) {
        this.webhookSecret = secret;
    }

    public boolean verifyStripeSignature(String payload, String signature) {
        // HMAC-SHA256: compute HmacSHA256(payload, webhookSecret) and compare to signature
        try {
            var mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(webhookSecret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            var computed = bytesToHex(mac.doFinal(payload.getBytes(StandardCharsets.UTF_8)));
            return MessageDigest.isEqual(computed.getBytes(), signature.getBytes());
        } catch (Exception e) {
            return false;
        }
    }
}
```

### 2i. External API Config Pattern

```yaml
integration:
  payment:
    base-url: ${PAYMENT_API_URL:https://api.payment.example.com}
    api-key: ${PAYMENT_API_KEY:}
    connect-timeout: 5s
    read-timeout: 30s
  inventory:
    base-url: ${INVENTORY_API_URL:https://inventory.internal}
    read-timeout: 10s
  stripe:
    webhook-secret: ${STRIPE_WEBHOOK_SECRET:}
  shipping:
    base-url: ${SHIPPING_API_URL:https://api.shipping.example.com}
    api-key: ${SHIPPING_API_KEY:}
```

**Rules:**
- Group all external API config under `integration.{name}`
- Always environment-variable override for sensitive values (API keys, secrets, base URLs)
- Sensible defaults for non-sensitive values (timeouts, pool sizes)
- One config record per external service
- Base URLs: production defaults, override for staging/test

## Step 3: Wire Resilience

Every external API call MUST have resilience patterns. Use the resilience patterns from the `resilience` skill:

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class PaymentClient {
    private final RestClient restClient;

    @CircuitBreaker(name = "payment", fallbackMethod = "fallbackCharge")
    @Retry(name = "payment")
    @TimeLimiter(name = "payment")   // reactive; for sync, use HTTP client timeout
    public PaymentResponse charge(ChargeRequest request) { ... }

    private PaymentResponse fallbackCharge(ChargeRequest request, CallNotPermittedException ex) {
        log.warn("Payment circuit breaker open — returning pending response");
        return PaymentResponse.pending(request.orderId(), "Payment processing delayed");
    }
}
```

For comprehensive resilience setup (typed config records, bulkhead, rate limiter), use `/devskillslearning-pipeline:resilience`.

## Step 4: Integration Tests with WireMock

```java
@SpringBootTest(webEnvironment = RANDOM_PORT)
@WireMockTest(httpPort = 9099)
class PaymentClientIntegrationTest {
    @Autowired private PaymentClient client;

    @Test
    void shouldChargeSuccessfully() {
        stubFor(post(urlEqualTo("/v1/charges"))
            .withHeader("X-API-Key", equalTo("test-key"))
            .willReturn(aResponse()
                .withStatus(200)
                .withHeader("Content-Type", "application/json")
                .withBody("""
                    {"chargeId":"ch_123","status":"SUCCEEDED","amount":"29.99"}
                    """)));

        var response = client.charge(new ChargeRequest(...));
        assertThat(response.status()).isEqualTo(ChargeStatus.SUCCEEDED);
    }

    @Test
    void shouldRetryOnServerError() {
        stubFor(post(urlEqualTo("/v1/charges"))
            .inScenario("retry")
            .willReturn(aResponse().withStatus(503))
            .willSetStateTo("first-failed"));
        stubFor(post(urlEqualTo("/v1/charges"))
            .inScenario("retry")
            .whenScenarioStateIs("first-failed")
            .willReturn(aResponse().withStatus(200).withBody("...")));

        var response = client.charge(new ChargeRequest(...));
        assertThat(response.status()).isEqualTo(ChargeStatus.SUCCEEDED);
    }

    @Test
    void shouldThrowOnClientError() {
        stubFor(post(urlEqualTo("/v1/charges"))
            .willReturn(aResponse()
                .withStatus(400)
                .withBody("""
                    {"code":"card_declined","message":"Card was declined"}
                    """)));

        assertThatThrownBy(() -> client.charge(new ChargeRequest(...)))
            .isInstanceOf(CardDeclinedException.class);
    }
}
```

## Step 5: Verify

```sh
# Generate client from OpenAPI spec
mvn openapi-generator:generate

# Verify generated client compiles
mvn compile

# Run integration tests
mvn test -Dtest="*ClientIntegrationTest"

# Test connectivity (manual)
curl -H "X-API-Key: $API_KEY" https://api.payment.example.com/health

# Verify resilience — stop the downstream service (or WireMock) and check fallback
# Verify caching — call cached endpoint twice, check logs for "Cache miss" only once
```

## Checklist

- [ ] OpenAPI spec downloaded/copied to `src/main/resources/openapi/` (if generating client)
- [ ] `openapi-generator-maven-plugin` configured with correct package names
- [ ] RestClient/WebClient/Feign configured with base URL, auth headers, and timeouts
- [ ] Connect timeout and read timeout configured on HTTP client
- [ ] API key / secret sourced from environment variables — never hardcoded
- [ ] Auth interceptor injects credentials and trace ID
- [ ] Error mapping: downstream error codes → domain exceptions (not raw downstream errors)
- [ ] `onStatus` handlers defined for 4xx, 5xx, and 429
- [ ] Circuit breaker + retry on every external call (use `/devskillslearning-pipeline:resilience`)
- [ ] Cache configured for idempotent/lookup calls with appropriate TTL
- [ ] Webhook endpoints verify HMAC signature before processing payload
- [ ] Webhook endpoints handle idempotency (same event sent twice by sender)
- [ ] Integration tests use WireMock — no real external calls in CI
- [ ] WireMock stubs test: success, 4xx, 5xx, timeout, retry
- [ ] External API config under `integration.{name}` in application.yml
- [ ] Base URLs overrideable via environment variables for different environments
- [ ] User-Agent header set for identifying your service to the downstream API

## Next Step
After integrating external APIs, use `/devskillslearning-pipeline:resilience` to harden with circuit breakers, retry, and bulkheads. For APIs you own, use `/devskillslearning-pipeline:design-api` to design the contract first.
