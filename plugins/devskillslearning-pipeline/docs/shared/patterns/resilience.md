# Resilience Patterns

Layered resilience for external service calls: every downstream call needs all four — retry + circuit breaker + timeout + bulkhead.

## Pattern Ordering

Stack patterns outside-in from outermost to innermost:

```
Retry → CircuitBreaker → TimeLimiter → Bulkhead → actual call
```

```java
@Bulkhead(name = "payment")
@TimeLimiter(name = "payment")
@CircuitBreaker(name = "payment")
@Retry(name = "payment")
public PaymentResponse processPayment(ChargeRequest request) { ... }
```

## Configuration

```yaml
resilience4j:
  retry:
    instances:
      payment:
        max-attempts: 3
        wait-duration: 1s
        exponential-backoff-multiplier: 2
        retry-exceptions:
          - java.net.SocketTimeoutException
          - org.springframework.web.client.ResourceAccessException
  circuitbreaker:
    instances:
      payment:
        sliding-window-size: 50
        failure-rate-threshold: 50
        wait-duration-in-open-state: 30s
        permitted-number-of-calls-in-half-open-state: 5
  timelimiter:
    instances:
      payment:
        timeout-duration: 5s
        cancel-running-future: true
  bulkhead:
    instances:
      payment:
        max-concurrent-calls: 10
        max-wait-duration: 500ms
  ratelimiter:
    instances:
      payment:
        limit-for-period: 100
        limit-refresh-period: 1s
        timeout-duration: 500ms
```

## Fallback Methods

```java
@CircuitBreaker(name = "payment", fallbackMethod = "paymentFallback")
public PaymentResponse processPayment(ChargeRequest request) {
    return paymentClient.charge(request);
}

public PaymentResponse paymentFallback(ChargeRequest request, Exception e) {
    log.error("Payment processing failed after circuit breaker open", e);
    throw new ServiceUnavailableException(ErrorCode.SERVICE_UNAVAILABLE, "Payment service unavailable");
}
```

## Retryable vs Ignored Exceptions

- **Retry on**: `ConnectException`, `SocketTimeoutException`, `ResourceAccessException`, HTTP 503.
- **Never retry on**: `BadRequestException`, `ResourceNotFoundException`, HTTP 400/404/409/422.
- Configure `record-exceptions` and `ignore-exceptions` explicitly per instance.

## Typed Configuration Records

```java
@ConfigurationProperties(prefix = "resilience.payment")
@Validated
public record PaymentResilienceConfig(
    @Positive int retryMaxAttempts,
    Duration retryBackoff,
    int circuitBreakerFailureThreshold,
    Duration circuitBreakerOpenDuration,
    int circuitBreakerHalfOpenCalls,
    Duration timeout,
    int bulkheadMaxConcurrent,
    Duration bulkheadMaxWait
) {}
```

## Graceful Shutdown

```yaml
server:
  shutdown: graceful
spring:
  lifecycle:
    timeout-per-shutdown-phase: 30s
```

## Resilience Audit Priority

- **Critical path**: all 4 mandatory (retry + CB + timeout + bulkhead).
- **Semi-critical**: circuit breaker + timeout minimum.
- **Non-critical**: timeout + bulkhead so they don't block critical paths.
