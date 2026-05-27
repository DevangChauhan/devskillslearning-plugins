# Configuration Properties

Type-safe configuration using `@ConfigurationProperties` — never scatter `@Value` across the codebase.

## Core Rules

- Use Java **records** for `@ConfigurationProperties`. Spring Boot 3.x auto-detects constructor binding.
- For Spring Boot 2.x, add `@ConstructorBinding` on the record or constructor.
- `@Validated` on the properties class with standard validation annotations on fields.
- Prefix always uses **kebab-case**: `orders.retry`, not `ordersRetry` or `orders_retry`.
- Inject via constructor — never use `@Value` except for one-off values.
- Place in `*.config` package.
- Register with `@ConfigurationPropertiesScan` on `@SpringBootApplication` (or `@EnableConfigurationProperties` on the consuming config).

## Example

```java
@ConfigurationProperties(prefix = "orders.retry")
@Validated
public record OrderRetryConfig(
    @Positive int maxAttempts,
    @DurationMin(seconds = 1) Duration backoff,
    Set<HttpStatus> retryableStatuses
) {}
```

```yaml
orders:
  retry:
    max-attempts: 3
    backoff: 2s
    retryable-statuses:
      - SERVICE_UNAVAILABLE
      - GATEWAY_TIMEOUT
```

## Common Mistakes to Flag

| Issue | Problem |
|-------|---------|
| `long`/`int` for durations | Use `java.time.Duration` — Spring Boot auto-converts `2s`, `500ms` |
| camelCase or snake_case prefix | Must be kebab-case |
| Missing `@Validated` | No validation on required fields |
| Secrets in config properties | Use `spring-config-encrypt`, Vault, or K8s Secrets — never plaintext |
| Scattered `@Value` annotations | Group into one `@ConfigurationProperties` class |
| Missing registration | No `@ConfigurationPropertiesScan` or `@EnableConfigurationProperties` |

## Maps and Lists

```java
@ConfigurationProperties(prefix = "integration")
public record IntegrationConfig(
    Map<String, ServiceConfig> services
) {}

public record ServiceConfig(
    URI baseUrl,
    Duration timeout,
    String apiKey
) {}
```

```yaml
integration:
  services:
    payment:
      base-url: https://payment.internal
      timeout: 5s
      api-key: ${PAYMENT_API_KEY}
```
