# Observability Patterns

## Structured Logging

- Use `log.info("{}", value)` — never string concatenation or `log.info(object.toString())`.
- Include correlation ID / trace ID in every log message (auto-injected by Micrometer Tracing).
- Log at boundaries: incoming requests, outgoing calls, error paths.
- Do NOT log request bodies or headers without sanitization (PII leak).
- Use `@Slf4j` (Lombok) or `LoggerFactory.getLogger(Xxx.class)` consistently.
- `log.error()` includes the exception as second argument, not just `ex.getMessage()`.
- JSON logging for log aggregation: `logstash-logback-encoder`.

## Metrics (Micrometer)

- `@Timed` on every controller endpoint and service method calling external systems.
- Custom counters for business events:

```java
meterRegistry.counter("orders.created", "status", status.name()).increment();
```

- Gauges for queue depth, connection pool size.
- Percentile histograms: `@Timed(histogram = true, percentiles = {0.5, 0.95, 0.99})`.
- Configure `management.metrics.distribution.percentiles-histogram` for HTTP and business timers.
- Standard metrics every service must emit:
  - `{domain}.created.total`
  - `{domain}.operation.errors`
  - `{domain}.operation.duration`
  - `downstream.{name}.health`

## Health Checks

- Custom `HealthIndicator` for DB, message broker, and downstream APIs.
- Liveness: `/actuator/health/liveness` (JVM alive only).
- Readiness: `/actuator/health/readiness` (all dependencies checked — DB, broker, critical downstreams).

## Tracing

- Propagation headers: `X-B3-TraceId`, `X-B3-SpanId` (Zipkin) or `traceparent` (W3C).
- Include tracing in `RestClient`/`WebClient`, Kafka producer/consumer, JDBC driver.
- Inject `Observation` API for custom spans around significant operations.
- Spring Boot 3.x: `micrometer-tracing-bridge-brave`; Spring Boot 2.x: `spring-cloud-starter-sleuth`.

## SLI / SLO Definitions

- Per-endpoint SLIs: availability (% successful requests), latency (p95, p99), error budget.
- Error budget: 99.9% availability = 43.2 min downtime/month.
- Burn rate alerts: fast burn (14.4x = 1h alert) for critical, slow burn (3x = 6h alert) for warning.

## Standard Grafana Dashboard Rows

1. **Service Health**: up/down, request rate, error rate
2. **Latency**: p50/p90/p99, slow endpoints table
3. **Throughput & Saturation**: active requests, JVM memory, GC pauses
4. **Dependencies**: DB pool, downstream latency, Kafka lag
5. **Business Metrics**: domain counters and gauges

## Alerting Rules

| Condition | Severity |
|-----------|----------|
| Service down > 1min | Critical |
| Error rate > 1% for 5min | Critical |
| p99 latency > SLO for 5min | Warning |
| DB connection pool pending > 10 for 2min | Warning |
| Kafka consumer lag > 10k for 10min | Warning |
| Circuit breaker open > 60s | Critical |

Every alert must have a runbook link in annotations.
