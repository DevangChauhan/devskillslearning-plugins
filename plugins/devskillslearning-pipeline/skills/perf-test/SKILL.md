---
name: devskillslearning-pipeline:perf-test
description: Performance and load test Java/Spring Boot applications. Use when the user asks to run performance tests, create load test plans, profile application bottlenecks, generate JMeter/Gatling/k6 test scripts, analyze JFR recordings, or identify slow endpoints and queries. Covers throughput, latency, and capacity testing.
type: skill
---

# Performance Test

You are a performance engineer testing a Java/Spring Boot application. Your goal: measure throughput, latency, and resource utilization under load, identify bottlenecks, and produce actionable recommendations.

## What You Need to Provide

| Input | Required? | Example | Notes |
|-------|-----------|---------|-------|
| What to test | Yes | "Load test the order checkout endpoint" | Target service and endpoints |
| Load testing tool | Recommended | k6 / Gatling / JMeter | I'll recommend k6 by default |
| Target throughput | Recommended | "500 RPS sustained, p99 < 200ms" | Success criteria |
| User journey / flow | Recommended | "Search product → add to cart → checkout" | For scenario-based tests |
| Peak load | No | "2x normal during Black Friday" | For capacity planning |
| API spec location | No | `src/main/resources/openapi/order-service-api.yaml` | I'll discover from project |

**Examples**:
- "Load test the order service — 500 RPS, p99 under 200ms"
- "Profile the payment service — it's slow under load"
- "Generate a k6 test script for the checkout flow from the OpenAPI spec"
- "Analyze JFR recording from the production incident"
- "Capacity test: how many concurrent users can the inventory service handle?"

**I auto-discover**: Existing test tool config, OpenAPI specs, actuator endpoints, JVM config (heap, GC), connection pool settings, service dependencies.

## Step 0: Discover Performance Context

1. Read `CLAUDE.md` for project conventions
2. Check for existing test plans: `src/test/*/jmeter/`, `src/test/*/gatling/`, `k6/`, `*.js`
3. Read OpenAPI specs for endpoint definitions (to auto-generate test scripts)
4. Check `application.yml` for server config (thread pool, connection timeout, keep-alive)
5. Check JVM config: `-Xmx`, `-Xms`, GC settings in build scripts or Dockerfile
6. Check connection pool config: `spring.datasource.hikari.*`, HTTP client pool
7. Note the build system and test framework for integration

## Step 1: Determine Scope

| Request | What to implement |
|---------|-------------------|
| "Load test" | k6/Gatling test script + run config + report analysis |
| "Profile" | JFR/Async Profiler instructions, flame graph analysis, bottleneck identification |
| "Capacity test" | Ramp test to find breaking point, capacity recommendations |
| "Benchmark" | JMH microbenchmark for critical code paths |
| "Full performance audit" | Load test + profile + DB query analysis + recommendations |
| "Analyze JFR recording" | Read JFR, identify hot methods, lock contention, allocation pressure |

## Step 2: Implement

### 2a. k6 Load Test Script (Recommended Default)

k6 is the recommended tool — scriptable in JavaScript, built-in metrics, CI-friendly, and lightweight compared to JMeter.

Generate `src/test/k6/{service}-load-test.js`:

```javascript
import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';
import { randomString, randomIntBetween, uuidv4 } from 'https://jslib.k6.io/k6-utils/1.4.0/index.js';

// Custom metrics
const errorRate = new Rate('errors');
const checkoutDuration = new Trend('checkout_duration');
const ordersCreated = new Counter('orders_created');

// Configurable via environment variables
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const RAMP_UP = __ENV.RAMP_UP || '30s';
const STEADY = __ENV.STEADY || '2m';
const RAMP_DOWN = __ENV.RAMP_DOWN || '30s';
const TARGET_VUS = parseInt(__ENV.TARGET_VUS) || 50;

export const options = {
  scenarios: {
    checkout_flow: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: RAMP_UP, target: TARGET_VUS },
        { duration: STEADY, target: TARGET_VUS },
        { duration: RAMP_DOWN, target: 0 },
      ],
    },
  },
  thresholds: {
    // Fail the test if these SLOs are breached
    'http_req_duration': ['p(95)<500', 'p(99)<1000'],
    'http_req_failed': ['rate<0.01'],
    'checkout_duration': ['p(95)<200', 'p(99)<500'],
    'errors': ['rate<0.01'],
  },
  noConnectionReuse: false,
  // Enable for distributed testing:
  // cloud: { projectID: 12345 },
};

export default function () {
  // Each VU gets a unique session — simulate real users
  const authToken = loginAndGetToken();

  group('Checkout flow', () => {
    // Step 1: Search products
    const searchResult = http.get(`${BASE_URL}/api/v1/products?q=test&page=0&size=10`, {
      headers: { Authorization: `Bearer ${authToken}` },
      tags: { name: 'search_products' },
    });
    check(searchResult, { 'search returned 200': (r) => r.status === 200 });

    // Step 2: View product details
    const productId = searchResult.json('content[0].id') || uuidv4();
    const productResult = http.get(`${BASE_URL}/api/v1/products/${productId}`, {
      headers: { Authorization: `Bearer ${authToken}` },
      tags: { name: 'get_product' },
    });
    check(productResult, { 'product returned 200': (r) => r.status === 200 });

    // Step 3: Add to cart
    const cartPayload = JSON.stringify({
      productId: productId,
      quantity: randomIntBetween(1, 5),
    });
    const cartResult = http.post(`${BASE_URL}/api/v1/cart/items`, cartPayload, {
      headers: {
        Authorization: `Bearer ${authToken}`,
        'Content-Type': 'application/json',
        'Idempotency-Key': uuidv4(),
      },
      tags: { name: 'add_to_cart' },
    });
    check(cartResult, { 'cart add returned 201': (r) => r.status === 201 });

    // Step 4: Checkout (the critical path)
    const checkoutPayload = JSON.stringify({
      shippingAddress: {
        line1: '123 Test St',
        city: 'Testville',
        state: 'TS',
        postalCode: '12345',
        country: 'US',
      },
      paymentMethodId: 'pm_test_card',
    });

    const checkoutResult = http.post(`${BASE_URL}/api/v1/orders/checkout`, checkoutPayload, {
      headers: {
        Authorization: `Bearer ${authToken}`,
        'Content-Type': 'application/json',
        'Idempotency-Key': uuidv4(),
      },
      tags: { name: 'checkout' },
    });

    checkoutDuration.add(checkoutResult.timings.duration);

    const success = check(checkoutResult, {
      'checkout returned 201': (r) => r.status === 201,
      'response has orderId': (r) => r.json('orderId') !== undefined,
    });

    if (success) {
      ordersCreated.add(1);
    } else {
      errorRate.add(1);
      console.error(`Checkout failed: ${checkoutResult.status} — ${checkoutResult.body}`);
    }
  });

  // Simulate realistic user think time
  sleep(randomIntBetween(1, 5));
}

function loginAndGetToken() {
  // Use a pre-generated test token or call the auth endpoint
  // For load tests, use a pool of pre-created test tokens to avoid auth overhead
  const token = __ENV.TEST_AUTH_TOKEN || 'test-jwt-token';
  return token;
}

// Teardown: Clean up any created data
export function teardown() {
  console.log(`Orders created during test: ${ordersCreated.value}`);
}
```

### 2b. k6 Test Runner Config

`src/test/k6/run.sh`:

```sh
#!/usr/bin/env bash
set -euo pipefail

# Prerequisites: https://k6.io/docs/get-started/installation/
# brew install k6    # macOS
# sudo apt-get install k6  # Linux

# Smoke test — 1 VU, 1 minute
smoke() {
  k6 run \
    --env BASE_URL="${BASE_URL:-http://localhost:8080}" \
    --env TEST_AUTH_TOKEN="${TEST_AUTH_TOKEN:-test-token}" \
    --env TARGET_VUS=1 \
    --env STEADY=30s \
    src/test/k6/order-service-load-test.js
}

# Load test — 50 VUs, 2 minute steady state
load() {
  k6 run \
    --env BASE_URL="${BASE_URL:-http://localhost:8080}" \
    --env TEST_AUTH_TOKEN="${TEST_AUTH_TOKEN:-test-token}" \
    --env TARGET_VUS=50 \
    --env STEADY=2m \
    --out json=results/load-test-$(date +%Y%m%d-%H%M%S).json \
    src/test/k6/order-service-load-test.js
}

# Stress test — ramp to 200 VUs
stress() {
  k6 run \
    --env BASE_URL="${BASE_URL:-http://localhost:8080}" \
    --env TEST_AUTH_TOKEN="${TEST_AUTH_TOKEN:-test-token}" \
    --env TARGET_VUS=200 \
    --env STEADY=2m \
    --out json=results/stress-test-$(date +%Y%m%d-%H%M%S).json \
    src/test/k6/order-service-load-test.js
}

# Soak test — moderate load over a long period
soak() {
  k6 run \
    --env BASE_URL="${BASE_URL:-http://localhost:8080}" \
    --env TEST_AUTH_TOKEN="${TEST_AUTH_TOKEN:-test-token}" \
    --env TARGET_VUS=30 \
    --env STEADY=30m \
    --out json=results/soak-test-$(date +%Y%m%d-%H%M%S).json \
    src/test/k6/order-service-load-test.js
}

"$@"
```

### 2c. Gatling Test (Java DSL — Alternative)

When the team prefers Java-native tools, generate Gatling simulations:

```java
// src/test/gatling/CheckoutSimulation.java
package com.acme.orderservice.gatling;

import io.gatling.javaapi.core.*;
import io.gatling.javaapi.http.*;
import static io.gatling.javaapi.core.CoreDsl.*;
import static io.gatling.javaapi.http.HttpDsl.*;

public class CheckoutSimulation extends Simulation {

    private final HttpProtocolBuilder httpProtocol = http
        .baseUrl("http://localhost:8080")
        .acceptHeader("application/json")
        .contentTypeHeader("application/json")
        .userAgentHeader("k6-load-test/1.0");

    private final ScenarioBuilder checkoutFlow = scenario("Checkout")
        .exec(http("Search Products")
            .get("/api/v1/products?q=test&page=0&size=10")
            .check(status().is(200))
            .check(jsonPath("$.content[0].id").saveAs("productId")))
        .exec(http("Get Product")
            .get("/api/v1/products/#{productId}")
            .check(status().is(200)))
        .exec(http("Add to Cart")
            .post("/api/v1/cart/items")
            .body(StringBody("""
                {"productId":"#{productId}","quantity":2}
                """))
            .check(status().is(201)))
        .exec(http("Checkout")
            .post("/api/v1/orders/checkout")
            .body(ElFileBody("bodies/checkout-request.json"))
            .check(status().is(201)));

    {
        setUp(
            checkoutFlow.injectOpen(
                rampUsers(50).during(30),   // Ramp up
                constantUsersPerSec(50).during(120), // Steady state
                rampUsers(0).during(30)     // Ramp down
            )
        ).protocols(httpProtocol)
        .assertions(
            global().responseTime().percentile(95.0).lt(500),
            global().responseTime().percentile(99.0).lt(1000),
            global().failedRequests().percent().lt(1.0)
        );
    }
}
```

### 2d. Auto-Generate Test From OpenAPI Spec

When an OpenAPI spec exists, extract endpoints and generate test coverage:

```sh
#!/usr/bin/env bash
# Generate k6 test stubs from OpenAPI spec
# Uses openapi-generator or manual extraction

SPEC="src/main/resources/openapi/order-service-api.yaml"
OUTPUT="src/test/k6/order-service-generated.js"

# Extract POST/PUT/PATCH endpoints (mutating — primary perf targets)
# and GET endpoints (read-heavy — secondary perf targets)

yq eval '.paths | to_entries | .[] |
  "// " + .key + ": " + (.value | keys | join(", "))' "$SPEC"
```

The generated test should:
1. Create, read, update, and list the primary resource in sequence
2. Use different `Idempotency-Key` per request (k6 `uuidv4()`)
3. Tag each request with the operation name for per-endpoint metrics
4. Include thresholds from the spec's `x-slo` annotations if present

### 2e. JVM Profiling with JFR

**Enable JFR at startup (production-safe, < 2% overhead):**
```sh
java \
  -XX:StartFlightRecording=filename=recording.jfr,dumponexit=true,maxsize=500M \
  -XX:FlightRecorderOptions=stackdepth=128 \
  -jar target/order-service.jar
```

**Or attach at runtime:**
```sh
# Find the PID
jps -l | grep order-service

# Start a 60-second recording
jcmd <PID> JFR.start name=profile duration=60s filename=profile.jfr

# Or continuous recording with a rolling buffer (like a black box)
jcmd <PID> JFR.start name=continuous maxsize=250M \
  settings=profile dumponexit=true filename=continuous.jfr
```

**What to look for in JFR analysis:**

| Finding | What it means | Fix |
|---------|--------------|-----|
| `SocketRead` / `SocketWrite` dominating | Threads waiting on I/O | Increase connection timeout, async I/O |
| `Object.wait()` high % | Lock contention | Reduce synchronized blocks, use concurrent collections |
| `Full GC` frequent | Memory pressure | Increase heap, tune GC, reduce allocation rate |
| `HashMap.resize()` hot | Excessive rehashing | Pre-size HashMaps/HashSets |
| `Class.getMethod` / reflection hot | Reflection in hot path | Cache Method handles, avoid reflection |
| `String.concat` / `StringBuilder.append` hot | String allocation pressure | Pool common strings, use StringBuilder correctly |
| DB query methods taking > 100ms | Slow queries | Add indexes, optimize queries (see database skill) |

### 2f. Async Profiler (Linux — Lower Overhead than JFR)

```sh
# Download: https://github.com/async-profiler/async-profiler

# CPU profile (30 seconds)
./profiler.sh -d 30 -f cpu-profile.html <PID>

# Allocation profile (what's creating the most garbage?)
./profiler.sh -e alloc -d 30 -f alloc-profile.html <PID>

# Lock contention
./profiler.sh -e lock -d 30 -f lock-profile.html <PID>

# Wall-clock profile (where threads spend time, including blocked)
./profiler.sh -e wall -d 30 -f wall-profile.html <PID>
```

**Flame graph interpretation:**
- Wide bars at the top = hot methods (optimize these first)
- Tall narrow stacks = deep call chains (check for unnecessary wrapping)
- Green (Java) vs yellow (JVM/C++) vs red (kernel) — red = syscalls, check I/O

### 2g. JMH Microbenchmarks

For critical code paths where nanosecond precision matters:

```java
// src/test/jmh/OrderServiceBenchmark.java
@State(Scope.Benchmark)
@BenchmarkMode(Mode.Throughput)
@OutputTimeUnit(TimeUnit.SECONDS)
@Warmup(iterations = 3, time = 1)
@Measurement(iterations = 5, time = 2)
@Fork(1)
public class OrderServiceBenchmark {

    private OrderService service;
    private CreateOrderRequest request;

    @Setup
    public void setup() {
        // Initialize with Spring context or manual wiring
        var ctx = new AnnotationConfigApplicationContext(BenchmarkConfig.class);
        service = ctx.getBean(OrderService.class);
        request = new CreateOrderRequest(
            List.of(new CreateOrderItemRequest(UUID.randomUUID(), 2)),
            new Address("123 St", null, "NYC", "NY", "10001", "US"),
            null
        );
    }

    @Benchmark
    public OrderResponse createOrder() {
        return service.createOrder(request);
    }

    @Benchmark
    public OrderResponse getOrder() {
        return service.getOrder(TEST_ORDER_ID);
    }
}
```

Add to `pom.xml`:
```xml
<dependency>
    <groupId>org.openjdk.jmh</groupId>
    <artifactId>jmh-core</artifactId>
    <version>1.37</version>
    <scope>test</scope>
</dependency>
<dependency>
    <groupId>org.openjdk.jmh</groupId>
    <artifactId>jmh-generator-annprocess</artifactId>
    <version>1.37</version>
    <scope>test</scope>
</dependency>
```

### 2h. Database Query Profiling

Identify slow queries under load:

```sql
-- PostgreSQL: find slow queries
SELECT queryid, query,
  calls, mean_exec_time_ms, max_exec_time_ms,
  rows, shared_blks_hit, shared_blks_read
FROM pg_stat_statements
ORDER BY mean_exec_time_ms DESC
LIMIT 20;

-- Find queries with high shared_blks_read (disk I/O → missing indexes)
SELECT queryid, query,
  shared_blks_read / NULLIF(calls, 0) AS avg_disk_reads,
  mean_exec_time_ms
FROM pg_stat_statements
WHERE shared_blks_read > 0
ORDER BY shared_blks_read DESC
LIMIT 20;

-- Enable if not already:
-- CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

### 2i. Connection Pool Saturation Check

Monitor during load test:

```sh
# Watch HikariCP metrics during test
watch -n 1 'curl -s http://localhost:8080/actuator/metrics/hikaricp_connections_active | jq .measurements'

# Or if Prometheus:
# hikaricp_connections_active{pool="order-service-pool"}
# hikaricp_connections_pending{pool="order-service-pool"}  # > 0 means pool is saturated
```

**Saturation signs:**
- `hikaricp_connections_pending > 0` → increase `maximum-pool-size`
- `hikaricp_connections_timeout_total` increasing → connections not released, check for leaks
- `hikaricp_connections_active` at max → pool fully utilized

### 2j. Load Test Run and Results Analysis

**Run the test:**
```sh
# Start the service with JFR
java -XX:StartFlightRecording=filename=profile.jfr,dumponexit=true \
  -jar target/order-service.jar &

# Run k6 load test
k6 run --out json=results.json src/test/k6/order-service-load-test.js

# While test runs, capture system metrics
vmstat 1 > results/vmstat.log &
iostat -x 1 > results/iostat.log &

# After test completes, analyze
k6 run --summary-export=results/summary.json src/test/k6/order-service-load-test.js
```

**Analysis report template** (produce this after the test):

```markdown
## Load Test Results — Order Service

**Test Config**: 50 VUs, 30s ramp, 2m steady, 30s ramp-down
**Target**: p95 < 500ms, p99 < 1s, error rate < 1%

### Throughput
| Metric | Value |
|--------|-------|
| Total requests | 12,847 |
| Request rate | 107 req/s |
| Checkout rate | 21 orders/s |
| Data transferred | 45 MB received, 2 MB sent |

### Latency
| Percentile | Value | vs Target |
|-----------|-------|-----------|
| p50 | 45ms | ✓ |
| p95 | 312ms | ✓ (under 500ms) |
| p99 | 897ms | ✓ (under 1s) |
| Max | 2,340ms | — |

### Errors
| Metric | Value |
|--------|-------|
| Error rate | 0.3% (38 / 12,847) |

### Resource Utilization
| Resource | Value | Status |
|----------|-------|--------|
| CPU avg | 62% | OK |
| CPU p99 | 94% | HIGH — consider more instances |
| Heap used avg | 1.2 GB of 2 GB | OK |
| GC pause p99 | 45ms | ACCEPTABLE |
| DB connections active | 8 of 10 | OK |
| DB connections pending | 0 | OK |

### Bottleneck: Checkout Endpoint
- p99 = 897ms, primarily in `PaymentService.charge()` (average 650ms external call)
- RECOMMEND: Add caching for payment method validation (saves ~200ms)
- RECOMMEND: Consider async checkout — return 202 Accepted, process in background

### Recommendations
1. [HIGH] Add Redis cache for payment method validation
2. [MEDIUM] Scale to 3 instances for 300+ RPS headroom
3. [MEDIUM] Tune GC: `-XX:+UseZGC` to reduce p99 pause
4. [LOW] Enable HTTP compression (gzip) for response bodies > 1KB
```

### 2k. Capacity Test — Find the Breaking Point

```sh
# Ramp test: increase VUs until error rate > 1% or p99 > 2s
for vus in 10 25 50 100 150 200 300; do
  echo "=== Testing with $vus VUs ==="
  k6 run \
    --env TARGET_VUS=$vus \
    --env STEADY=1m \
    --summary-export="results/capacity-${vus}vu.json" \
    src/test/k6/order-service-load-test.js
  sleep 30  # Cool down between runs
done

# Plot results: VUs vs p99 latency and error rate
# Breaking point = where latency spikes or error rate crosses threshold
```

**Capacity recommendation formula:**
```
safe_capacity_rps = breaking_point_rps * 0.6
instances_needed = target_rps / safe_capacity_rps
```

## Step 3: Performance Checklist Before Production

- [ ] Load test passes with target throughput + 50% headroom
- [ ] p99 latency under SLO at steady state
- [ ] Error rate < 1% under load
- [ ] DB connection pool not saturated at peak load
- [ ] No `hikaricp_connections_pending` observed
- [ ] GC pause times acceptable (< 100ms for HTTP, < 50ms for gRPC)
- [ ] No memory leak (heap stabilizes after warmup, no upward trend during soak)
- [ ] Thread pool not exhausted (no `RejectedExecutionException`)
- [ ] Downstream circuit breakers not opening under normal load (false positives)
- [ ] CPU utilization under 80% at peak load (room for spikes)
- [ ] HTTP connection pool not exhausted (no `ConnectionPoolTimeoutException`)
- [ ] JVM warmup accounted for (ramp-up period in load test)
- [ ] Cold start time measured and acceptable

## Step 4: Verify

```sh
# 1. Start the service
mvn spring-boot:run -Dspring-boot.run.profiles=dev

# 2. Quick smoke test (ensure test script works)
k6 run --env TARGET_VUS=1 --env STEADY=30s src/test/k6/order-service-load-test.js

# 3. Full load test
bash src/test/k6/run.sh load

# 4. Check metrics during test (separate terminal)
watch -n 1 'curl -s http://localhost:8080/actuator/metrics/http.server.requests | jq'

# 5. After test, check for errors in application logs
grep -c "ERROR" logs/application.log

# 6. Check slow query log
psql -d orderdb -c "
  SELECT query, mean_exec_time_ms, calls
  FROM pg_stat_statements
  ORDER BY mean_exec_time_ms DESC LIMIT 10;
"
```

## Checklist

- [ ] k6 (or Gatling/JMeter) installed and test script generated
- [ ] Test script covers critical user journeys (not just individual endpoints)
- [ ] Test uses realistic payloads (not empty bodies or hardcoded UUIDs)
- [ ] `Idempotency-Key` unique per request in test
- [ ] Thresholds defined: p95, p99, error rate
- [ ] Ramp-up period allows JVM warmup
- [ ] Steady-state duration long enough to observe stable behavior
- [ ] Custom metrics instrumented per business operation
- [ ] JFR or Async Profiler recording enabled during test
- [ ] DB pool metrics monitored during test (`hikaricp_*`)
- [ ] GC metrics monitored (jvm_gc_pause_seconds)
- [ ] CPU and memory utilization captured
- [ ] Slow queries identified from `pg_stat_statements` or slow query log
- [ ] Bottleneck analysis with actionable recommendations
- [ ] Capacity recommendation: safe RPS per instance
- [ ] Raw results saved for trend comparison (JSON output)
- [ ] Load test runner script committed for CI reproducibility
- [ ] Service recovers after test (no residual effects — memory, connections, threads)

## Next Step
After performance testing, fix any identified bottlenecks (use `/devskillslearning-pipeline:refactor` for safe restructuring or `/devskillslearning-pipeline:resilience` if you need circuit breakers for slow downstreams), then `/devskillslearning-pipeline:deploy` to ship.
