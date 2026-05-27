---
name: devskillslearning-pipeline:monitor
description: Set up production observability — Micrometer, Prometheus/Grafana, distributed tracing, SLIs/SLOs, alerting rules, health indicators. Use when: add metrics, configure tracing, define SLOs, generate dashboards.
type: skill
---

# Monitor

You are an SRE/observability expert instrumenting a Java/Spring Boot application for production. Your goal: make the application observable — metrics, traces, logs, health checks, and alerts — without over-instrumenting.

## What You Need to Provide

| Input | Required? | Example | Notes |
|-------|-----------|---------|-------|
| What to monitor | Yes | "Add Prometheus metrics to the order service" | The service and observability stack |
| Metrics backend | Recommended | Prometheus / Datadog / New Relic / OTel collector | I'll configure the registry |
| Tracing backend | If adding tracing | Zipkin / Jaeger / Tempo / Datadog APM | I'll configure the exporter |
| Dashboard preference | No | Grafana / Datadog / CloudWatch | I generate dashboard JSON |
| Alert channels | No | Slack / PagerDuty / Opsgenie / email | For alerting rules |
| Critical SLOs | Recommended | "Order checkout: 99.9% availability, p99 < 500ms" | I'll derive SLIs from these |

**Examples**:
- "Add metrics and tracing to the order service with Prometheus and Zipkin"
- "Set up production health checks with SLIs for the payment service"
- "Generate a Grafana dashboard for the inventory service"
- "Add alerting rules: p99 latency > 1s, error rate > 1%"

**I auto-discover**: Existing Micrometer setup, observability dependencies, Spring Boot version, Actuator config, architecture type (servlet/reactive), existing health indicators, message broker instrumentation needs.

## Step 0: Discover Current Observability State

Follow `docs/shared/step0-discovery.md` to detect build system, Spring Boot version, architecture type, package layout, and all project conventions.

## Step 1: Determine Scope

| Request | What to implement |
|---------|-------------------|
| "Add metrics" | Micrometer + Prometheus registry + Actuator endpoint, custom business metrics |
| "Add tracing" | Micrometer Tracing + Brave/OTel bridge + Zipkin/Tempo exporter |
| "Set up health checks" | Custom HealthIndicators for DB, message broker, downstream APIs |
| "Generate dashboard" | Grafana dashboard JSON with key panels |
| "Add alerting" | Prometheus alerting rules or Datadog monitors with thresholds |
| "Full production readiness" | Metrics + tracing + health checks + dashboards + alerting |
| "Add log aggregation" | Structured JSON logging, Loki/Promtail setup, log-based alerting, retention config |

## Step 2: Implement

### 2a. Prometheus Metrics Setup

**Build dependency (Maven):**
```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

**application.yml:**
```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus,metrics
      base-path: /actuator
  endpoint:
    health:
      show-details: when-authorized
      probes:
        enabled: true
      group:
        readiness:
          include: readinessState,db,messageBroker
        liveness:
          include: livenessState
  metrics:
    tags:
      application: ${spring.application.name}
      environment: ${ENVIRONMENT:dev}
    distribution:
      percentiles-histogram:
        http.server.requests: true
        "[orders.create]": true
        "[payments.process]": true
      slo:
        http.server.requests: 10ms,50ms,100ms,250ms,500ms,1s,2s,5s
  tracing:
    sampling:
      probability: ${TRACING_SAMPLE_RATE:1.0}
  observations:
    key-values:
      application: ${spring.application.name}
```

**If Spring Boot 2.x**: Replace `management.tracing.sampling.probability` with `spring.sleuth.sampler.probability`. Replace `management.observations.key-values` — not available, use `spring.sleuth.baggage.*`.

### 2b. Custom Business Metrics

Add counters, gauges, and timers in service classes:

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class OrderService {
    private final MeterRegistry meterRegistry;

    public OrderResponse createOrder(CreateOrderRequest request) {
        // Counter: each order created, tagged by type
        meterRegistry.counter("orders.created.total",
            "type", request.orderType().name()).increment();

        // Gauge: current pending orders
        var pendingCount = repository.countByStatus(OrderStatus.PENDING);
        meterRegistry.gauge("orders.pending", pendingCount);

        // Timer: wrapped around the operation
        var start = System.nanoTime();
        try {
            var result = doCreateOrder(request);
            meterRegistry.timer("orders.create.duration",
                "type", request.orderType().name())
                .record(System.nanoTime() - start, TimeUnit.NANOSECONDS);
            return result;
        } catch (Exception e) {
            meterRegistry.counter("orders.create.errors",
                "type", request.orderType().name(),
                "error", e.getClass().getSimpleName()).increment();
            throw e;
        }
    }
}
```

**Metrics naming convention** (Micrometer): `{domain}.{operation}.{unit}` — e.g., `orders.created.total`, `payments.process.duration`, `inventory.stock.low`.

**Standard metrics every service should emit:**

| Metric | Type | Description |
|--------|------|-------------|
| `{domain}.created.total` | Counter | Entities created, tagged by type |
| `{domain}.updated.total` | Counter | Entities updated |
| `{domain}.deleted.total` | Counter | Entities deleted |
| `{domain}.operation.errors` | Counter | Errors by operation and error type |
| `{domain}.operation.duration` | Timer | Operation latency histogram |
| `{domain}.active` | Gauge | Currently active/processing count |
| `downstream.{name}.health` | Gauge | 1=up, 0=down |

### 2c. Distributed Tracing

**Spring Boot 3.x (Micrometer Tracing + Brave):**
```xml
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-tracing-bridge-brave</artifactId>
</dependency>
<dependency>
    <groupId>io.zipkin.reporter2</groupId>
    <artifactId>zipkin-reporter-brave</artifactId>
</dependency>
```

**application.yml:**
```yaml
management:
  tracing:
    sampling:
      probability: ${TRACING_SAMPLE_RATE:0.1}
    baggage:
      remote-fields: customer-id,order-id
      correlation:
        fields: customer-id,order-id
```

**Inject tracer for manual spans:**
```java
@Service
@RequiredArgsConstructor
public class OrderService {
    private final ObservationRegistry observationRegistry;

    public OrderResponse processOrder(UUID orderId) {
        return Observation.createNotStarted("orders.process", observationRegistry)
            .lowCardinalityKeyValue("order.id", orderId.toString())
            .observe(() -> {
                // Business logic — auto-wrapped in span
                var order = repository.findById(orderId).orElseThrow(...);
                paymentClient.charge(order);   // span propagates via HTTP headers
                notificationClient.notify(order);
                return mapper.toResponse(order);
            });
    }
}
```

**Spring Boot 2.x (Sleuth)** — use `spring-cloud-starter-sleuth` instead. Inject `Tracer` bean. Wrap with `tracer.nextSpan().name("orders.process").start()`.

### 2d. Health Indicators

**Database health:**
```java
@Component
public class DatabaseHealthIndicator implements HealthIndicator {
    private final DataSource dataSource;

    @Override
    public Health health() {
        try (var conn = dataSource.getConnection()) {
            var stmt = conn.createStatement();
            var rs = stmt.executeQuery("SELECT 1");
            rs.next();
            return Health.up()
                .withDetail("database", conn.getMetaData().getDatabaseProductName())
                .withDetail("url", conn.getMetaData().getURL())
                .build();
        } catch (Exception e) {
            return Health.down().withException(e).build();
        }
    }
}
```

**Message broker health:**
```java
@Component
public class KafkaHealthIndicator implements HealthIndicator {
    private final KafkaAdmin kafkaAdmin;

    @Override
    public Health health() {
        try {
            var desc = kafkaAdmin.describeCluster(KafkaAdmin.DEFAULT_TIMEOUT);
            return Health.up()
                .withDetail("clusterId", desc.clusterId())
                .withDetail("nodes", desc.nodes().size())
                .build();
        } catch (Exception e) {
            return Health.down().withException(e).build();
        }
    }
}
```

**Downstream API health:**
```java
@Component
public class PaymentServiceHealthIndicator implements HealthIndicator {
    private final PaymentClient paymentClient;

    @Override
    public Health health() {
        try {
            var start = System.nanoTime();
            paymentClient.ping();
            var latencyMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - start);
            return Health.up().withDetail("latencyMs", latencyMs).build();
        } catch (Exception e) {
            return Health.down().withException(e).build();
        }
    }
}
```

**Readiness vs Liveness**: Readiness probes include all dependency checks (DB, broker, downstream APIs). Liveness probes check only that the JVM is alive — no dependency checks. Use `management.endpoint.health.group.readiness.include` to scope readiness checks.

### 2e. Structured Logging and Correlation

**logback-spring.xml** (JSON format for log aggregation):
```xml
<configuration>
    <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <encoder class="net.logstash.logback.encoder.LogstashEncoder">
            <includeMdcKeyName>traceId</includeMdcKeyName>
            <includeMdcKeyName>spanId</includeMdcKeyName>
            <includeMdcKeyName>customerId</includeMdcKeyName>
            <includeMdcKeyName>orderId</includeMdcKeyName>
        </encoder>
    </appender>
    <root level="INFO">
        <appender-ref ref="CONSOLE" />
    </root>
</configuration>
```

**Logging best practices in code:**
```java
@Slf4j
public class OrderService {
    // Structured: key=value pairs in message
    public OrderResponse createOrder(CreateOrderRequest req) {
        log.info("Creating order: type={} customerId={}", req.orderType(), req.customerId());
        // TraceId and SpanId are auto-injected by Micrometer Tracing into MDC
        // Never log PII, tokens, or passwords — even in structured fields
    }
}
```

**Key dependencies for JSON logging:**
```xml
<dependency>
    <groupId>net.logstash.logback</groupId>
    <artifactId>logstash-logback-encoder</artifactId>
    <version>7.4</version>
</dependency>
```

### 2f. Log Aggregation with Loki + Promtail

For Kubernetes deployments, ship logs to Grafana Loki for centralized search and correlation with metrics:

**Log shipping pipeline**: `App → stdout (JSON) → Promtail (DaemonSet) → Loki → Grafana`

**Promtail DaemonSet config** (K8s):
```yaml
# promtail-config.yaml — ConfigMap mounted to Promtail pods
server:
  http_listen_port: 9080

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: spring-boot-apps
    kubernetes_sd_configs:
      - role: pod
    pipeline_stages:
      - json:
          expressions:
            level: level
            message: message
            traceId: traceId
            spanId: spanId
            logger: logger_name
            application: application
      - labels:
          application:
          level:
          traceId:
      - match:
          selector: '{level="ERROR"}'
          stages:
            - metrics:
                log_errors_total:
                  type: Counter
                  description: "Total error log lines"
                  config:
                    match_all: true
                    action: inc
```

**Loki alerting rules** (log-based):
```yaml
# loki-alerts.yaml
groups:
  - name: spring-boot-log-alerts
    rules:
      - alert: HighErrorLogRate
        expr: |
          rate({level="ERROR"}[5m]) > 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "{{ $labels.application }} logging > 10 ERROR/min"
          runbook: "https://wiki.internal/runbooks/high-error-log-rate"

      - alert: StackTraceDetected
        expr: |
          {level="ERROR"} |= "Exception"
        labels:
          severity: warning
        annotations:
          summary: "Exception detected in {{ $labels.application }}: {{ $labels.message }}"

      - alert: NoLogsFromService
        expr: |
          absent_over_time({application="order-service"}[10m])
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Order service has produced no logs for 10 minutes"
```

**Loki datasource in Grafana** (`grafana-datasources.yaml`):
```yaml
apiVersion: 1
datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    jsonData:
      maxLines: 1000
```

**Correlating metrics and logs in Grafana**: When viewing a metric panel, split a Loki query by `traceId` to see all log lines for a specific request. Loki labels derived from JSON fields (`traceId`, `application`, `level`) enable fast filtering without full-text scan.

### 2g. Log Retention and Sampling

For high-volume services, control log volume:

```yaml
# Loki config — retention and limits
limits_config:
  retention_period: 744h       # 31 days
  max_entries_limit_per_query: 5000
  reject_old_samples: true
  reject_old_samples_max_age: 168h  # reject logs older than 7 days

table_manager:
  retention_deletes_enabled: true
  retention_period: 744h
```

**Application-level sampling for non-critical logs:**
```yaml
# logback-spring.xml — async appender with queue
<appender name="ASYNC" class="ch.qos.logback.classic.AsyncAppender">
    <queueSize>512</queueSize>
    <discardingThreshold>0</discardingThreshold>
    <neverBlock>true</neverBlock>
    <appender-ref ref="CONSOLE" />
</appender>
<root level="INFO">
    <appender-ref ref="ASYNC" />
</root>
```

Rules:
- Log at INFO for business events, WARN for recoverable issues, ERROR for actionable failures
- Never log at DEBUG in production — use `logging.level.com.company` in `application-prod.yml` to override specific packages
- Ship only `level`, `message`, `traceId`, `spanId`, `application`, and key business IDs as Loki labels — everything else stays in the log line
- Too many labels = high cardinality = slow Loki. Keep label count under 10 per stream

### 2h. Log-Based Alerting Rules

Beyond Loki, combine log patterns with Prometheus metrics for composite alerts:

| Scenario | Metric check | Log check | Severity |
|----------|------------|-----------|----------|
| DB connection failure | `hikaricp_connections_active == 0` | `"Cannot acquire connection"` | Critical |
| Auth failure spike | `http_requests_total{status="401"} > 50/5m` | `"Invalid token"` or `"Access denied"` | Warning |
| Downstream timeout | `downstream_calls_seconds_count{status="timeout"} > 10/5m` | `"SocketTimeoutException"` | Warning |
| Schema registry failure | `kafka_producer_errors_total > 0` | `"Schema not found"` or `"Incompatible schema"` | Warning |
| OOM approaching | `jvm_memory_used_bytes / jvm_memory_max_bytes > 0.9` | `"OutOfMemoryError"` or `"GC overhead"` | Critical |

**Composite alert example (Prometheus + Loki in Alertmanager):**
```yaml
- alert: DatabaseConnectionFailure
  expr: |
    rate(hikaricp_connections_timeout_total[5m]) > 0
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "DB connection timeouts detected"
    description: "Check Loki: {application=\"{{ $labels.application }}\"} |= \"connection\""
```

### 2j. SLI / SLO Definition

Define SLIs as a config file: `.sli/order-service.yaml`

```yaml
service: order-service
slo_window: 30d

slis:
  - name: availability
    description: Proportion of successful HTTP requests
    metric: http_server_requests_seconds_count{status!~"5.."}
    target: 99.9
    alert_threshold: 99.5

  - name: latency-p99
    description: 99th percentile latency for checkout endpoint
    metric: histogram_quantile(0.99, rate(http_server_requests_seconds_bucket{uri="/api/v1/orders/checkout"}[5m]))
    target: 500ms
    alert_threshold: 1000ms

  - name: error-budget-burn
    description: Rate of error budget consumption
    target: < 1 budget consumed per 7 days

error_budget:
  availability:
    # 99.9% = 43.2 minutes allowed downtime per month
    total_minutes: 43.2
    burn_rate_fast: 14.4  # alerts within 1 hour
    burn_rate_slow: 3     # alerts within 6 hours
```

### 2k. Grafana Dashboard

Generate a JSON dashboard file at `.dashboards/{service}-dashboard.json` with these panels:

**Row 1: Service Health**
- **Up/Down**: SingleStat — `up{job="${service}"}` — shows 1 or 0
- **Request Rate**: Graph — `rate(http_server_requests_seconds_count[5m])` — per-endpoint lines
- **Error Rate**: Graph — `rate(http_server_requests_seconds_count{status=~"5.."}[5m]) / rate(http_server_requests_seconds_count[5m])`

**Row 2: Latency**
- **p50/p90/p99 Latency**: Heatmap or multi-line graph
- **Slow Endpoints**: Table — top 10 by p99 latency

**Row 3: Throughput & Saturation**
- **Active Requests**: Gauge — `http_server_requests_active`
- **JVM Memory**: Graph — used/committed/max heap
- **GC Pause Time**: Graph — `jvm_gc_pause_seconds_sum`

**Row 4: Dependencies**
- **DB Connection Pool**: Graph — active/idle/pending connections
- **Downstream Latency**: Graph per downstream service
- **Kafka Consumer Lag**: Graph — `kafka_consumer_fetch_manager_records_lag_max`

**Row 5: Business Metrics**
- Custom panels based on the service's business counters and gauges

### 2l. Prometheus Alerting Rules

Generate `.alerts/{service}-alerts.yml`:

```yaml
groups:
  - name: order-service-critical
    rules:
      - alert: ServiceDown
        expr: up{job="order-service"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Order service is down"
          runbook: "https://wiki.internal/runbooks/order-service-down"

      - alert: HighErrorRate
        expr: |
          rate(http_server_requests_seconds_count{job="order-service",status=~"5.."}[5m])
          / rate(http_server_requests_seconds_count{job="order-service"}[5m]) > 0.01
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Error rate > 1% for 5 minutes"

      - alert: HighLatency
        expr: |
          histogram_quantile(0.99,
            rate(http_server_requests_seconds_bucket{job="order-service",uri="/api/v1/orders/checkout"}[5m])
          ) > 1.0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Checkout p99 latency > 1 second"

      - alert: DatabaseConnectionPoolExhaustion
        expr: hikaricp_connections_pending{job="order-service"} > 10
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "DB connection pool has {{ $value }} pending connections"

      - alert: KafkaConsumerLag
        expr: kafka_consumer_fetch_manager_records_lag_max{job="order-service"} > 10000
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Kafka consumer lag > 10k records for 10 minutes"

      - alert: DeadLetterQueueGrowth
        expr: rate(messaging_client_sent_messages_total{result="failed"}[15m]) > 0
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Messages failing to deliver"
```

### 2m. OpenTelemetry (Alternative to Prometheus-only)

For organizations standardizing on OTel:

```xml
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-otlp</artifactId>
</dependency>
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-tracing-bridge-otel</artifactId>
</dependency>
```

```yaml
management:
  metrics:
    export:
      otlp:
        url: ${OTEL_EXPORTER_OTLP_ENDPOINT:http://localhost:4318/v1/metrics}
        step: 30s
  tracing:
    sampling:
      probability: 0.1
  otlp:
    tracing:
      endpoint: ${OTEL_EXPORTER_OTLP_ENDPOINT:http://localhost:4318/v1/traces}
```

### 2n. Database Observability

Instrument database queries when the project has access to connection pool metrics:

```yaml
management:
  metrics:
    enable:
      jdbc: true  # Spring Boot 3.1+
```

For HikariCP (default pool):
```yaml
spring:
  datasource:
    hikari:
      pool-name: ${spring.application.name}-pool
      # Metrics automatically exposed at /actuator/metrics/hikaricp.*
```

Key HikariCP metrics: `hikaricp_connections_active`, `hikaricp_connections_idle`, `hikaricp_connections_pending`, `hikaricp_connections_timeout_total`.

## Step 3: Verify

```sh
# Start the service
mvn spring-boot:run -Dspring-boot.run.profiles=dev

# Check Actuator endpoints
curl http://localhost:8080/actuator/health | jq .
curl http://localhost:8080/actuator/prometheus | head -30

# Verify metrics are being emitted
curl -s http://localhost:8080/actuator/metrics | jq '.names | sort'

# Check liveness/readiness (Kubernetes-style)
curl http://localhost:8080/actuator/health/liveness
curl http://localhost:8080/actuator/health/readiness

# Verify tracing
# Make a request and look for "traceId" in console log output
curl http://localhost:8080/api/v1/orders
# Log should include: traceId=..., spanId=...
```

## Checklist

- [ ] `spring-boot-starter-actuator` dependency present
- [ ] Metrics registry dependency added (Prometheus or OTLP or Datadog)
- [ ] Tracing bridge and exporter configured (if tracing requested)
- [ ] `management.endpoints.web.exposure.include` includes `health,prometheus`
- [ ] Histogram percentiles configured for critical endpoints
- [ ] Custom business counters, gauges, timers added to service classes
- [ ] Health indicators added for DB, message broker, downstream APIs
- [ ] Liveness and readiness probe groups configured
- [ ] Structured JSON logging configured (logstash-logback-encoder)
- [ ] TraceId and SpanId propagated in MDC
- [ ] Log aggregation pipeline set up (Promtail → Loki → Grafana)
- [ ] Log retention and sampling configured
- [ ] Log-based alerting rules defined
- [ ] Loki datasource configured in Grafana
- [ ] Async log appender configured for high-volume services
- [ ] SLI/SLO definitions file created
- [ ] Grafana dashboard JSON generated
- [ ] Alerting rules defined with severity levels and runbook links
- [ ] HikariCP connection pool metrics exposed
- [ ] Actuator endpoints secured (only `health` public, rest behind auth)
- [ ] No sensitive data logged or exposed via metrics
- [ ] `management.server.port` configured (different from app port) for production

## Next Step
After setting up observability, use `/devskillslearning-pipeline:deploy` to containerize and deploy the instrumented service.
