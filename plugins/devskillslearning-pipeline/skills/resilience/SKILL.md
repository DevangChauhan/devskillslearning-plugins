---
name: devskillslearning-pipeline:resilience
description: Harden Java/Spring Boot services with Resilience4j patterns. Use when the user asks to add circuit breaker, retry, timeout, bulkhead, or rate limiter to service calls. Covers fallback strategies, resilience configuration records, metrics integration, and resilience audit of existing downstream calls.
type: skill
---

# Resilience

You are a resilience engineer hardening a Java/Spring Boot application against distributed system failures. Your goal: add resilience patterns to every downstream call so the system degrades gracefully, not catastrophically.

## What You Need to Provide

| Input | Required? | Example | Notes |
|-------|-----------|---------|-------|
| What to harden | Yes | "Add circuit breaker to all downstream calls in the order service" | Scope and target service |
| Downstream dependencies | Recommended | "Payment service, inventory service, notification service" | I'll discover from code if not specified |
| Resilience requirements | No | "Payment: 3 retries with 2s backoff, circuit breaker at 50% failure" | Specific thresholds |
| Rate limit targets | No | "100 req/s to payment service per instance" | For rate limiter config |

**Examples**:
- "Add resilience patterns to the order service — it calls payment, inventory, and notification"
- "Add circuit breaker to the PaymentClient — it's been timing out in prod"
- "Audit all downstream HTTP calls and add retry with exponential backoff"
- "Add bulkhead to isolate the slow shipping calculation from the rest of the pool"
- "Add rate limiter: max 50 requests per second to the external tax API"

**I auto-discover**: Existing Resilience4j config, `WebClient`/`RestClient`/`RestTemplate` usage, Feign clients, message broker config, Spring Boot version, existing `application.yml` resilience config, Micrometer metrics setup.

## Step 0: Discover Current Resilience State

1. Read `CLAUDE.md` for project conventions
2. Check build file for `resilience4j-*` dependencies
3. Check `application.yml` for `resilience4j.*` config sections
4. Scan for downstream calls:
   - `WebClient`, `RestClient`, `RestTemplate` in service classes
   - `@FeignClient` interfaces
   - `StreamBridge` or `KafkaTemplate` for message publishing
   - `JdbcTemplate`, `Jooq`, or raw `DataSource` calls
5. Check for existing `@CircuitBreaker`, `@Retry`, `@Bulkhead`, `@RateLimiter` annotations
6. Check if Micrometer is already configured (for resilience metrics)

## Step 1: Determine Scope

| Request | What to implement |
|---------|-------------------|
| "Add circuit breaker" | Circuit breaker on downstream HTTP/gRPC/messaging calls, fallback methods |
| "Add retry" | Retry with exponential backoff, jitter, retryable exceptions |
| "Add timeout" | Timeout on all external calls — shorter than circuit breaker |
| "Add bulkhead" | Thread pool or semaphore isolation for heavy/slow operations |
| "Add rate limiter" | Rate limit on outbound calls to external APIs with quotas |
| "Full resilience hardening" | All five patterns on every downstream call, resilience config records |
| "Resilience audit" | Audit existing calls, identify missing patterns, add where needed |

## Step 2: Implement

### 2a. Dependencies

**Maven:**
```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-aop</artifactId>
</dependency>
<dependency>
    <groupId>io.github.resilience4j</groupId>
    <artifactId>resilience4j-spring-boot3</artifactId>
</dependency>
<!-- For WebClient/Reactive -->
<dependency>
    <groupId>io.github.resilience4j</groupId>
    <artifactId>resilience4j-reactor</artifactId>
</dependency>
<!-- For Micrometer metrics on resilience events -->
<dependency>
    <groupId>io.github.resilience4j</groupId>
    <artifactId>resilience4j-micrometer</artifactId>
</dependency>
```

**Spring Boot 2.x**: Replace `resilience4j-spring-boot3` with `resilience4j-spring-boot2`.

### 2b. Resilience Configuration (Record)

Use a typed `@ConfigurationProperties` record for each downstream service's resilience config:

```java
@Validated
@ConfigurationProperties(prefix = "resilience.payment")
public record PaymentResilienceConfig(
    @Positive int retryMaxAttempts,
    Duration retryBackoff,
    @Positive int circuitBreakerFailureThreshold,
    Duration circuitBreakerOpenDuration,
    @Positive int circuitBreakerHalfOpenCalls,
    @Positive Duration timeout,
    @Positive int bulkheadMaxConcurrent,
    @Positive Duration bulkheadMaxWait
) {}
```

**Corresponding `application.yml`:**
```yaml
resilience:
  payment:
    retry-max-attempts: 3
    retry-backoff: 500ms
    circuit-breaker-failure-threshold: 50
    circuit-breaker-open-duration: 30s
    circuit-breaker-half-open-calls: 5
    timeout: 5s
    bulkhead-max-concurrent: 10
    bulkhead-max-wait: 100ms
  inventory:
    retry-max-attempts: 2
    retry-backoff: 200ms
    circuit-breaker-failure-threshold: 50
    circuit-breaker-open-duration: 30s
    circuit-breaker-half-open-calls: 3
    timeout: 3s
    bulkhead-max-concurrent: 20
    bulkhead-max-wait: 50ms
  notification:
    retry-max-attempts: 5
    retry-backoff: 1s
    circuit-breaker-failure-threshold: 30
    circuit-breaker-open-duration: 60s
    circuit-breaker-half-open-calls: 2
    timeout: 10s
    bulkhead-max-concurrent: 5
    bulkhead-max-wait: 500ms
```

### 2c. Global `application.yml` Resilience4j Config

```yaml
resilience4j:
  circuitbreaker:
    configs:
      default:
        sliding-window-type: COUNT_BASED
        sliding-window-size: 100
        failure-rate-threshold: 50
        wait-duration-in-open-state: 30s
        permitted-number-of-calls-in-half-open-state: 10
        automatic-transition-from-open-to-half-open-enabled: true
        record-exceptions:
          - java.net.ConnectException
          - java.net.SocketTimeoutException
          - java.net.http.HttpTimeoutException
          - org.springframework.web.client.ResourceAccessException
          - io.github.resilience4j.circuitbreaker.CallNotPermittedException
        ignore-exceptions:
          - com.acme.exception.BadRequestException
          - com.acme.exception.ResourceNotFoundException
    instances:
      payment:
        base-config: default
      inventory:
        base-config: default
      notification:
        base-config: default
        sliding-window-size: 50

  retry:
    configs:
      default:
        max-attempts: 3
        wait-duration: 500ms
        enable-exponential-backoff: true
        exponential-backoff-multiplier: 2
        max-wait-duration: 10s
        retry-exceptions:
          - java.net.ConnectException
          - java.net.SocketTimeoutException
          - org.springframework.web.client.ResourceAccessException
        ignore-exceptions:
          - com.acme.exception.BadRequestException
          - com.acme.exception.ResourceNotFoundException

  timelimiter:
    configs:
      default:
        timeout-duration: 5s
        cancel-running-future: true

  bulkhead:
    configs:
      default:
        max-concurrent-calls: 25
        max-wait-duration: 0ms
      instances:
        payment:
          max-concurrent-calls: 10
        notification:
          max-concurrent-calls: 5
          max-wait-duration: 500ms

  ratelimiter:
    configs:
      default:
        limit-for-period: 100
        limit-refresh-period: 1s
        timeout-duration: 500ms
```

### 2d. Circuit Breaker Pattern

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class PaymentService {
    private final PaymentClient paymentClient;
    private final PaymentResilienceConfig config;

    @CircuitBreaker(name = "payment", fallbackMethod = "fallbackCharge")
    public PaymentResponse charge(ChargeRequest request) {
        log.debug("Charging payment: orderId={} amount={}", request.orderId(), request.amount());
        return paymentClient.charge(request);
    }

    // Fallback: MUST have same signature as the guarded method + Exception param
    private PaymentResponse fallbackCharge(ChargeRequest request, CallNotPermittedException ex) {
        log.warn("Payment circuit breaker open — returning degraded response for orderId={}", request.orderId());
        // Store for later retry or return a pending response
        return PaymentResponse.pending(request.orderId(), "Payment processing delayed");
    }

    private PaymentResponse fallbackCharge(ChargeRequest request, Exception ex) {
        log.error("Payment failed for orderId={}: {}", request.orderId(), ex.getMessage());
        throw new PaymentFailedException("Payment unavailable", ex);
    }
}
```

**Circuit breaker rules:**
- Fallback method must have the same return type, same parameters + `Exception` as last param
- Record exceptions that indicate downstream failure (timeout, connection refused, 5xx)
- Ignore exceptions that are client errors (400/404) — don't trip breaker on bad input
- `CallNotPermittedException` fallback = breaker is open, return degraded/cached response
- Other exception fallback = actual failure, rethrow or return error
- Default config: 50% failure rate over 100-call sliding window, 30s open state

### 2e. Retry Pattern

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class InventoryService {
    private final InventoryClient inventoryClient;

    @Retry(name = "inventory", fallbackMethod = "fallbackReserve")
    public InventoryResponse reserve(ReserveRequest request) {
        log.debug("Reserving inventory: productId={} quantity={}", request.productId(), request.quantity());
        return inventoryClient.reserve(request);
    }

    private InventoryResponse fallbackReserve(ReserveRequest request, Exception ex) {
        log.error("Inventory reserve failed after all retries: productId={}", request.productId(), ex);
        throw new InventoryUnavailableException("Cannot reserve inventory after retries", ex);
    }
}
```

**Retry rules:**
- Only retry on transient failures: timeouts, connection refused, 503 Service Unavailable
- Never retry on: 400 Bad Request, 404 Not Found, 409 Conflict, 422 Unprocessable
- Exponential backoff with jitter to avoid thundering herd: 500ms → 1s → 2s → 4s (capped at 10s)
- Max 3 retry attempts for most calls; 5 for async/background operations
- Retry + circuit breaker together: retries happen inside the circuit breaker window

### 2f. Timeout Pattern

Always pair timeouts with retries and circuit breakers. Timeout should be shorter than the circuit breaker's open duration.

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class PaymentService {
    private final PaymentClient paymentClient;

    @TimeLimiter(name = "payment")   // Reactive variant
    @CircuitBreaker(name = "payment")
    public Mono<PaymentResponse> chargeAsync(ChargeRequest request) {
        return paymentClient.chargeAsync(request);
    }

    // For synchronous calls, configure timeout on the HTTP client itself:
    // WebClient / RestClient timeout
}
```

**HTTP client-level timeout (always configure this first):**
```java
@Bean
public RestClient restClient(RestClient.Builder builder) {
    return builder
        .requestFactory(new HttpComponentsClientHttpRequestFactory())
        .build();
}

// Or WebClient:
@Bean
public WebClient webClient(WebClient.Builder builder) {
    var httpClient = HttpClient.create()
        .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 5000)
        .responseTimeout(Duration.ofSeconds(10))
        .doOnConnected(conn ->
            conn.addHandlerLast(new ReadTimeoutHandler(10, TimeUnit.SECONDS))
                .addHandlerLast(new WriteTimeoutHandler(5, TimeUnit.SECONDS)));
    return builder
        .clientConnector(new ReactorClientHttpConnector(httpClient))
        .build();
}
```

**Timeout hierarchy:**
1. HTTP client connect timeout: 3-5s
2. HTTP client response timeout: 5-10s
3. Resilience4j `@TimeLimiter`: slightly higher than HTTP timeout
4. Circuit breaker `wait-duration-in-open-state`: longer than TimeLimiter timeout
5. Overall request timeout (API gateway / load balancer): highest

### 2g. Bulkhead Pattern

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class ShippingService {
    private final ShippingCalculator calculator;

    @Bulkhead(name = "shipping", fallbackMethod = "fallbackCalculate")
    public ShippingRate calculate(ShippingRequest request) {
        log.debug("Calculating shipping: orderId={}", request.orderId());
        return calculator.calculate(request);  // CPU-intensive or slow external call
    }

    private ShippingRate fallbackCalculate(ShippingRequest request, BulkheadFullException ex) {
        log.warn("Shipping bulkhead full — returning default rate for orderId={}", request.orderId());
        return ShippingRate.defaultRate();
    }
}
```

**Bulkhead rules:**
- Use **semaphore** bulkhead for synchronous calls (thread-per-request model)
- Use **thread pool** bulkhead for reactive or async calls
- Limit concurrent calls: 10 for critical downstream, 5 for non-critical, 25 for internal
- `max-wait-duration: 0` means fail-fast — better than queuing (queues hide upstream latency)
- Give non-critical operations their own bulkhead so they don't starve critical ones

### 2h. Rate Limiter (Outbound)

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class TaxService {
    private final TaxApiClient taxClient;

    @RateLimiter(name = "taxApi", fallbackMethod = "fallbackCalculateTax")
    public TaxResponse calculateTax(Order order) {
        log.debug("Calculating tax: orderId={}", order.getId());
        return taxClient.calculateTax(order);
    }

    private TaxResponse fallbackCalculateTax(Order order, RequestNotPermitted ex) {
        log.warn("Tax API rate limit hit — deferring for orderId={}", order.getId());
        // Queue for async processing or return a reasonable estimate
        return TaxResponse.deferred(order.getId());
    }
}
```

**Rate limiter config:**
```yaml
resilience4j:
  ratelimiter:
    instances:
      taxApi:
        limit-for-period: 50         # 50 calls
        limit-refresh-period: 1s     # per second
        timeout-duration: 500ms      # wait up to 500ms for permission
```

### 2i. Chaining Multiple Patterns

For critical downstream calls, stack patterns in this order:

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class OrderProcessor {
    private final PaymentService paymentService;

    // Patterns apply from outside-in:
    // Retry → CircuitBreaker → TimeLimiter → Bulkhead → actual call
    @Bulkhead(name = "payment")
    @TimeLimiter(name = "payment")
    @CircuitBreaker(name = "payment")
    @Retry(name = "payment")
    public PaymentResponse processPayment(ChargeRequest request) {
        log.info("Processing payment: orderId={}", request.orderId());
        return paymentService.charge(request);
    }
}
```

### 2j. Feign Client Resilience

When the project uses `@FeignClient`, configure resilience at the Feign level:

```java
@FeignClient(
    name = "payment-service",
    url = "${payment.service.url}",
    configuration = PaymentFeignConfig.class
)
public interface PaymentClient {
    @PostMapping("/api/v1/payments/charge")
    PaymentResponse charge(@RequestBody ChargeRequest request);
}
```

```yaml
resilience4j:
  circuitbreaker:
    instances:
      payment-service:
        sliding-window-size: 50
        failure-rate-threshold: 50
        wait-duration-in-open-state: 30s
  retry:
    instances:
      payment-service:
        max-attempts: 3
        wait-duration: 500ms
  timelimiter:
    instances:
      payment-service:
        timeout-duration: 5s
```

Feign client names are used as Resilience4j instance names automatically.

### 2k. Resilience Metrics

All patterns auto-emit Micrometer metrics when `resilience4j-micrometer` is on the classpath:

```
# Circuit breaker state
resilience4j_circuitbreaker_state{name="payment",state="open"} 1.0

# Circuit breaker calls
resilience4j_circuitbreaker_calls_total{name="payment",kind="success"} 98
resilience4j_circuitbreaker_calls_total{name="payment",kind="failed"} 2
resilience4j_circuitbreaker_calls_total{name="payment",kind="not_permitted"} 0

# Retry
resilience4j_retry_calls_total{name="payment",kind="success_with_retry"} 5

# Bulkhead
resilience4j_bulkhead_available_concurrent_calls{name="payment"} 8

# Rate limiter
resilience4j_ratelimiter_available_permissions{name="taxApi"} 45
```

**Add to Grafana dashboard / alerting rules:** Alert when `resilience4j_circuitbreaker_state{state="open"}` is 1 for more than 60 seconds.

### 2l. Feign Fallback Factory

```java
@Component
public class PaymentClientFallbackFactory implements FallbackFactory<PaymentClient> {

    @Override
    public PaymentClient create(Throwable cause) {
        return new PaymentClient() {
            @Override
            public PaymentResponse charge(ChargeRequest request) {
                if (cause instanceof CallNotPermittedException) {
                    log.warn("Payment circuit breaker open");
                    return PaymentResponse.pending(request.orderId(), "Delayed");
                }
                log.error("Payment call failed fatally", cause);
                throw new PaymentUnavailableException("Payment service unavailable", cause);
            }
        };
    }
}
```

## Step 3: Resilience Audit

When asked to audit, systematically check every downstream call:

| Downstream | Call Type | Has Circuit Breaker? | Has Retry? | Has Timeout? | Has Bulkhead? | Action |
|-----------|-----------|---------------------|------------|-------------|---------------|--------|
| Payment Service | HTTP POST | No | No | No | No | ADD all — critical path |
| Inventory Service | HTTP POST | No | Yes (Feign default) | No | No | ADD circuit breaker + timeout + bulkhead |
| Notification | Kafka produce | No | N/A (async) | No | No | ADD timeout on produce |
| Tax API (external) | HTTP GET | No | No | No | No | ADD all + rate limiter for external quota |
| Redis cache | Redis GET | N/A | N/A | Yes (Lettuce default) | N/A | OK |
| DB read | JDBC | N/A | N/A | N/A | HikariCP pool | OK |

**Priority:**
1. **Critical path** (payment, order creation) — all 4 patterns mandatory
2. **Semi-critical** (inventory check, shipping calc) — circuit breaker + timeout minimum
3. **Non-critical** (notification, analytics) — timeout + bulkhead so they don't block critical

## Step 4: Verify

```sh
# Ensure app starts with resilience config
mvn spring-boot:run -Dspring-boot.run.profiles=dev

# Check health — resilience4j adds its own health indicators
curl http://localhost:8080/actuator/health | jq .
# Should show: "circuitBreakers": {"status": "UP", "details": {"payment": {"state": "CLOSED"}}}

# Check metrics
curl http://localhost:8080/actuator/metrics | grep resilience4j

# Trigger circuit breaker by stopping the downstream service and hitting the endpoint
# Verify fallback response is returned instead of 500
# Verify circuit breaker state transitions to OPEN
curl http://localhost:8080/actuator/health | jq '.components.circuitBreakers'

# Run tests
mvn test -pl :module-name
```

## Checklist

- [ ] `resilience4j-spring-boot3` (or `boot2`) dependency added
- [ ] `spring-boot-starter-aop` dependency present
- [ ] `resilience4j-micrometer` for metrics on resilience events
- [ ] Global default config in `application.yml` for all 4 patterns
- [ ] Per-downstream config records (`@ConfigurationProperties`) for thresholds
- [ ] Circuit breaker on every downstream HTTP/gRPC call
- [ ] `record-exceptions` includes transient failures, `ignore-exceptions` excludes client errors
- [ ] Retry on every downstream call with exponential backoff + jitter
- [ ] Retryable exceptions: timeouts, connection failures, 503 — not 400/404/409
- [ ] HTTP client timeouts configured (connect + response)
- [ ] Bulkhead on CPU-intensive or slow calls to isolate thread pools
- [ ] Rate limiter on external APIs with hard quotas
- [ ] Fallback methods return degraded/pending responses, not exceptions
- [ ] Feign clients use Resilience4j via instance names matching service IDs
- [ ] Fallback prevents `CallNotPermittedException` from propagating to callers
- [ ] Resilience metrics visible at `/actuator/metrics`
- [ ] Circuit breaker health indicators visible at `/actuator/health`
- [ ] Alerting configured: open circuit breaker > 60s → page on-call
- [ ] Pattern order correct: Retry → CB → TimeLimiter → Bulkhead (outermost to innermost)
- [ ] No ad-hoc `try-catch Thread.sleep()` retry loops — use Resilience4j annotations everywhere

## Next Step
After hardening with resilience patterns, use `/devskillslearning-pipeline:perf-test` to load test and verify the system degrades gracefully under stress, then `/devskillslearning-pipeline:deploy` to ship.
