---
name: devskillslearning-pipeline:diagnose
description: Diagnose and fix build failures, test failures, startup errors, and runtime issues in Spring Boot. Covers K8s, CI/CD, threading, and memory problems. Use when: share a stack trace, build log, or error message.
type: skill
---

# Diagnose

You are an expert in diagnosing Java/Spring Boot application failures. Use a systematic approach: read the error carefully, trace back through the code, identify root cause, apply the fix, verify.

## What You Need to Provide

| Input | Required? | Example | Notes |
|-------|-----------|---------|-------|
| The error | Yes | Stack trace, build log, error message | Paste the full output |
| What you were doing | Recommended | "Running mvn clean verify on the order service" | Context helps narrow the cause |
| When it started | Recommended | "After upgrading Spring Boot from 3.2 to 3.3" | Recent changes are the first suspect |

**Examples**:
- Just paste a stack trace and I'll diagnose it
- "The build fails with 'cannot find symbol' after I added a new dependency"
- "The app starts but crashes when I call POST /api/v1/orders"
- "Tests pass locally but fail in CI with a connection refused error"

**I auto-discover**: Build system, Spring Boot version, Java version, module structure, dependencies. No need to provide these.

## Step -1: Stabilize First (Production Incidents)

Before deep debugging a production issue, stop the bleeding first:

| Question | Action |
|----------|--------|
| Can you roll back the last deploy? | `kubectl rollout undo deployment/<name>` or `git revert` — do this FIRST |
| Can you toggle a feature flag? | Turn off the feature causing the issue |
| Can you scale down traffic? | Route traffic away from the failing instance or reduce rate limits |
| Can you restart? | `kubectl rollout restart deployment/<name>` — quick fix for memory leaks, deadlocks, thread exhaustion |

Only proceed to diagnosis after the service is stable. A 5-minute rollback is better than a 2-hour debugging session under pressure.

## Step 0: Gather Information

Follow `docs/shared/step0-discovery.md` to detect build system, Spring Boot version, architecture type, package layout, and all project conventions.

## Step 0.5: Initial Triage

Before diving into classification tables, answer these narrowing questions:

### Decision Tree

```
Is the service reachable?
├─ No → Check: kubectl get pods, health endpoint, network connectivity
│       Is it all instances or just one?
│       ├─ All → Recent deploy? Config change? Dependency outage?
│       └─ One  → Node issue, resource starvation, pod eviction
└─ Yes → Is the error rate elevated?
         ├─ Yes → Was there a recent deploy? (git log --oneline -5)
         │        ├─ Yes → Rollback first, debug after
         │        └─ No  → Check downstream dependencies, DB, message broker
         └─ No  → Isolated failure — proceed to classification
```

### Severity Classification

| Severity | Definition | Response |
|----------|-----------|----------|
| **P0** | Full outage — service completely down, all users affected | Rollback immediately. Debug after stability is restored. |
| **P1** | Partial outage — elevated error rate, SLO at risk | 10-minute timeboxes. Escalate if unresolved after 30 min. |
| **P2** | Degraded — slow responses, intermittent failures, no SLO breach | Standard debugging flow. Fix in current session. |
| **P3** | Minor — cosmetic, single-user, non-critical path | Queue for next available time. No urgency. |

### Narrowing Questions
- **Single instance or fleet-wide?** Fleet-wide = config/code/deploy issue. Single instance = node/resource issue.
- **Correlated with a recent change?** `git log --oneline -10`, check deploy timestamps, config changes.
- **Correlated with load?** Check if error rate tracks with request rate — suggests capacity or throttling issue.
- **New or has this ever worked?** If never worked, it's likely config or code. If it broke suddenly, check external dependencies.

## Step 1: Classify the Failure

Read the error message or stack trace. Classify into one of these categories:

### Build Failures

| Symptom | Common Causes |
|---------|---------------|
| `cannot find symbol` | Missing import, wrong package, API change between versions |
| `package javax.* does not exist` | Spring Boot 2.x import on Boot 3.x project (or vice versa) |
| `package does not exist` | Missing dependency in build file |
| `duplicate class` | Conflicting versions on classpath, dependency convergence issue |
| `invalid target release` | Java version mismatch (e.g., code uses Java 21 feature but `<java.version>` is 17) |

**Diagnostic process:**
```sh
# Check Java version
mvn --version
java --version

# Check dependency tree for conflicts
mvn dependency:tree -pl :module-name | grep -E "conflict|omitted"
# or
./gradlew :module-name:dependencies --configuration compileClasspath

# Check effective Spring Boot version
mvn dependency:tree -pl :module-name | grep spring-boot-starter-parent
```

### Compilation Errors

| Symptom | Root Cause | Fix |
|----------|-----------|-----|
| `cannot find symbol: class Xxx` | Missing import statement | Add `import com.x.Xxx;` |
| `cannot find symbol: method yyy()` | API mismatch (wrong version) | Check Javadoc, use correct method signature |
| `incompatible types: X cannot be converted to Y` | Wrong return type or argument | Match types or add explicit conversion |
| `unreported exception; must be caught or declared` | Missing `throws` or try/catch | Handle or declare the checked exception |
| `Lombok @Data on entity` → MapStruct / Hibernate warnings | Known anti-pattern | Replace `@Data` with `@Getter`/`@Setter`/`@NoArgsConstructor` |

### Startup Errors

| Symptom | Root Cause | Fix |
|----------|-----------|-----|
| `BeanCreationException: Error creating bean with name 'xxx'` | Missing bean definition, circular dependency, or unsatisfied constructor parameter | Check `@Component`/`@Service`/`@Bean` annotations, break circular dep, or check constructor |
| `No qualifying bean of type 'Xxx' available` | Bean not registered in context | Add `@Component`/`@Service`/`@Repository` or explicit `@Bean` |
| `Parameter 0 of constructor in Xxx required a bean of type 'Yyy' that could not be found` | Missing dependency or wrong module not scanned | Check component scan base packages, verify dependency is on classpath |
| `APPLICATION FAILED TO START: Datasource URL not configured` | Missing or wrong `spring.datasource.url` | Check `application.yml`, environment variables, or Testcontainers config |
| `FlywayException: Validate failed: Migrations have failed validation` | Migration checksum mismatch | Run `mvn flyway:repair` (if intentional) or revert the migration change |
| `LiquibaseException: Change sets check sum mismatch` | Changeset was modified after being applied | Restore original changeset or add `validCheckSum` to the changeset |
| `Port 8080 already in use` | Another process on the port | `lsof -i :8080`, kill the process, or use `SERVER_PORT=8081` |
| `Failed to configure a DataSource: 'url' attribute is not specified` | No datasource config (common in new projects or test profiles) | Add datasource config or `@SpringBootApplication(exclude = DataSourceAutoConfiguration.class)` for non-DB apps |

### Test Failures

| Symptom | Root Cause | Fix |
|----------|-----------|-----|
| `expected: <200> but was: <404>` | Endpoint path, HTTP method, or path variable wrong | Fix URL pattern, method, or variable name in test |
| `expected: <200> but was: <400>` | Missing required request field | Add missing field to test request body |
| `expected: <200> but was: <403>` | Missing auth in test | Add `@WithMockUser`, mock security context, or disable security for test |
| `expected: <200> but was: <500>` | Unhandled exception in production code | Read server logs, find the exception, fix the code |
| `Wanted but not invoked: xxx.method()` | Mock not called — logic path didn't reach it | Check the condition that gates the mock call |
| `Actually, there were zero interactions with this mock` | Test setup wrong — service method not invoked, or different instance | Check `@MockBean` vs `@Mock` scope, verify test calls the right bean |
| `NullPointerException` in test | Missing mock setup (`when().thenReturn()`) | Add missing `when()` stub for the dependency |
| `ObjectOptimisticLockingFailureException` | Concurrent update not handled in test | Accept it as expected behavior, or retry with fresh entity |
| Test passes locally but fails in CI | Environment difference (DB version, OS, locale, timezone) | Use Testcontainers for DB, set `user.timezone=UTC` in surefire config |

### Runtime Issues

| Symptom | Root Cause | Fix |
|----------|-----------|-----|
| Slow endpoint | N+1 queries | Add `@EntityGraph` or JOIN FETCH, check for lazy-loading in loops |
| Slow endpoint (intermittent) | Missing DB index, connection pool saturation | Check `pg_stat_statements`, check `hikaricp_connections_pending`. Use `/devskillslearning-pipeline:database` for systematic query/index review |
| `OutOfMemoryError: Java heap space` | Memory leak or large dataset loaded into memory | Use pagination/streaming, increase `-Xmx`, check for unbounded collections |
| `ConnectionPoolTimeoutException` | Connection pool exhausted | Increase `hikari.maximum-pool-size`, check for connection leaks |
| `SocketTimeoutException` on external call | Downstream service slow or unresponsive | Add/adjust timeout, add circuit breaker. Use `/devskillslearning-pipeline:resilience` for comprehensive patterns |
| Event published but consumer not receiving | Wrong topic, consumer group, or deserialization error | Check topic name, consumer group, event schema compatibility |
| Circuit breaker open / fallback triggered | Downstream failing at high rate | Check downstream health, verify thresholds in resilience config. Use `/devskillslearning-pipeline:resilience` to review and tune |
| High p99 latency under load | Bottleneck in hot code path, GC pauses, DB contention | Profile with JFR/Async Profiler. Use `/devskillslearning-pipeline:perf-test` for systematic profiling |
| Missing metrics / no alert on failure | Observability not configured | Use `/devskillslearning-pipeline:monitor` to set up Prometheus, Grafana, and alerting rules |

### Kubernetes Deployment Failures

| Symptom | Root Cause | Fix |
|----------|-----------|-----|
| `CrashLoopBackOff` | App exits non-zero (config error, missing dependency, port conflict) | `kubectl logs <pod> --previous`, check startup probes |
| `CrashLoopBackOff` + Exit Code 137 | OOMKilled — container exceeded memory limit | Increase `resources.limits.memory` or fix memory leak |
| `ImagePullBackOff` | Wrong image tag, registry auth, or network | `kubectl describe pod`, check `imagePullSecrets`, verify tag exists |
| `Error` (probe failure) | Readiness/liveness probe pointing to wrong path or too short timeout | Check `readinessProbe.httpGet.path`, increase `initialDelaySeconds` |
| `Pending` indefinitely | Resource quota exceeded, no nodes match selector, PVC not bound | `kubectl describe pod`, check `resources.requests`, node selectors, PVC status |
| `Evicted` | Node under memory/disk pressure | `kubectl describe pod`, check node conditions, increase resources or add nodes |
| `CreateContainerConfigError` | ConfigMap or Secret referenced but missing | `kubectl get configmap <name>`, `kubectl get secret <name>` |
| Pod stuck in `Terminating` | Finalizer blocking, or container ignoring SIGTERM | Check `terminationGracePeriodSeconds`, preStop hooks, finalizer list |

**Diagnostic commands:**
```sh
kubectl describe pod <pod-name>           # Events at the bottom — most useful
kubectl logs <pod-name> --previous        # Logs from crashed container
kubectl get events --sort-by='.lastTimestamp' | tail -20
kubectl top pod <pod-name>                # CPU/memory usage
kubectl describe node <node-name>         # Node conditions (MemoryPressure, DiskPressure)
```

### CI/CD Pipeline Failures

| Symptom | Common Causes | Fix |
|----------|--------------|-----|
| Build passes locally, fails in CI | OS difference (macOS→Linux), JDK version mismatch, locale, timezone, filesystem case sensitivity | Run in CI container locally: `docker run --rm -v $(pwd):/app -w /app maven:3.9-eclipse-temurin-21 mvn verify` |
| GitHub Actions: runner flakiness | Out of disk space, network timeout, runner version mismatch | Check `df -h` in workflow, add `timeout-minutes`, pin runner version |
| Cache miss causing slow/failed build | Cache key changed, cache evicted | Check cache key hash, add fallback key, verify `cache-hit` output |
| Secret not available | Secret not set in repo/env, wrong scope | `gh secret list --repo owner/repo`, check environment vs repo scope |
| Artifact publish failure | Registry auth expired, version already exists, network | Check `~/.m2/settings.xml`, registry token expiry, use `--batch-mode` |
| Matrix build: one job fails | Platform-specific issue (ARM vs x86, Windows path separator) | Isolate the failing matrix axis, test locally on that platform |
| Out of memory during build | Maven/Gradle JVM heap too small | Set `MAVEN_OPTS: -Xmx2g` or `GRADLE_OPTS: -Xmx2g` in CI config |

**"Passes locally, fails in CI" systematic checklist:**
1. Same JDK version? `java -version` vs CI's `setup-java` version
2. Same OS? `uname -a` — macOS is case-insensitive by default, Linux is not
3. Same timezone? CI often defaults to UTC — if tests use `LocalDate.now()`, they may differ
4. Same locale? `locale` — string formatting, collation, and `String.toUpperCase()` vary
5. `.gitattributes` line endings? `* text=auto` avoids CRLF vs LF issues
6. Environment variables set locally but not in CI? Check `application.yml` placeholder defaults

### Concurrency & Threading Issues

| Symptom | Root Cause | Fix |
|----------|-----------|-----|
| Deadlock — threads stuck in BLOCKED | Two threads each hold a lock the other needs | Capture thread dump: `jstack <pid>`. Look for "waiting to lock" chains. Break the cycle with consistent lock ordering or `ReentrantLock.tryLock(timeout)`. |
| `RejectedExecutionException` | Thread pool queue full — all threads busy, queue capacity exhausted | Increase pool size + queue capacity, or add backpressure (caller-runs). Check `@Async` executor config. |
| `@Async` tasks never execute | `@Async` on self-invocation (same class) — AOP proxy bypassed | Move `@Async` method to separate bean, or inject self proxy |
| `@Async` tasks silently fail | Uncaught exception in async method — swallowed by `AsyncUncaughtExceptionHandler` | Configure custom `AsyncUncaughtExceptionHandler` that logs + alerts |
| Virtual thread pinned to carrier | `synchronized` block or native method inside virtual thread | Replace `synchronized` with `ReentrantLock`. Check `-Djdk.tracePinnedThreads=full` for pinning detection |
| `CompletableFuture` never completes | Missing `complete()`/`completeExceptionally()` call, or chain broken | Add `.orTimeout(30, SECONDS)` on all futures. Check for unhandled exceptions in `.thenApply()` chains |
| HikariCP connection leak | Connection acquired but never returned to pool | Set `spring.datasource.hikari.leak-detection-threshold: 60000`. Check for `DataSourceUtils.getConnection()` without `DataSourceUtils.releaseConnection()` |
| `hikaricp_connections_pending` growing | Connection pool saturated — all connections busy, requests queuing | Increase `maximum-pool-size` (rule: CPU cores × 2 + disk count). Check for long-running transactions holding connections. |

**Thread dump analysis:**
```sh
# Capture thread dump (3 dumps, 2s apart — look for threads stuck across all 3)
jstack <pid> > threaddump1.txt
sleep 2 && jstack <pid> > threaddump2.txt
sleep 2 && jstack <pid> > threaddump3.txt

# Quick deadlock detection
jcmd <pid> Thread.print | grep -A 5 "deadlock"

# Find threads in BLOCKED state across all dumps
grep "BLOCKED" threaddump*.txt | cut -d'"' -f2 | sort | uniq -c | sort -rn
```

## Step 2: Trace Root Cause

Follow this systematic approach:

1. **Read the FIRST error** in the stack trace — root cause is at the bottom
2. **Find the relevant "Caused by"** — the deepest one that's your code (not framework)
3. **Go to the file and line** mentioned in the trace
4. **Read 10 lines above and below** the failing line for context
5. **Trace the data flow** backward — where does the bad value/state come from?
6. **Check recent changes**: `git log --oneline -10` and `git diff main...HEAD`
7. **Compare with working examples**: find similar code in the project that works

## Step 3: Apply the Fix

1. Make the minimal change to fix the root cause — don't refactor adjacent code
2. Run the failing command again to verify
3. If it's a build/compile fix, run the full build
4. If it's a test fix, run the specific test: `mvn test -Dtest=XxxTest#methodName`
5. If it's a runtime fix, explain how to verify in production

## Step 4: Prevent Recurrence

If applicable, recommend:
- Adding a new ArchUnit rule to catch this class of error
- Adding a code-review check to the project's CLAUDE.md
- Adding a test case for the specific scenario that caused the failure
- Updating documentation if the fix reveals a non-obvious constraint

## Step 5: Post-Incident Response (P0/P1 Only)

After a P0 or P1 incident is resolved, run a post-incident review to prevent recurrence. Skip this for P2/P3 issues.

### 5a. Timeline Reconstruction

Rebuild the incident timeline from deploy logs, monitoring data, and chat history:

```markdown
| Time (UTC) | Event | Source |
|------------|-------|--------|
| 14:32 | Deploy v1.8.3 to production | CI/CD logs |
| 14:35 | Error rate begins climbing | Prometheus |
| 14:38 | PagerDuty alert fires | Alert manager |
| 14:41 | Rollback initiated | kubectl logs |
| 14:43 | Error rate normalizes | Prometheus |
```

- **Detection time**: When did the monitoring first detect it?
- **Response time**: When did a human first acknowledge it?
- **Mitigation time**: When was the bleeding stopped?
- **Resolution time**: When was the root cause fixed?
- **Total impact**: Detection → resolution duration

### 5b. Five Whys Analysis

Start with the symptom and ask "why?" five times until you reach the systemic root cause:

```
Symptom: Order checkout returned 500 errors for 8 minutes

Why #1: The payment service returned connection refused
Why #2: Payment service was restarting due to OOMKilled
Why #3: Memory spiked because a batch job loaded all pending orders
Why #4: The batch job had no pagination and no memory limit
Why #5: The batch job was written without code review and had no load test

Root cause: No code review gate for batch jobs, no performance test requirement for data-loading code.
```

Rules:
- Each "why" must be a verifiable fact, not speculation
- Stop when you reach a **process** or **system** failure (not "the developer made a mistake")
- The final answer should be something you can fix with a process change, automation, or architectural guard

### 5c. Blameless Postmortem Template

```markdown
# Incident Postmortem: [Title]

**Date**: YYYY-MM-DD
**Severity**: P0 / P1
**Duration**: Start → End (X minutes)
**Authors**: [Names]
**Status**: Draft / Reviewed / Published

## Summary
One paragraph: what happened, impact, root cause.

## Timeline
[Table from 5a]

## Impact
- Users affected: [count or "all"]
- Error budget consumed: [X minutes out of Y allowed]
- Revenue impact (if known): [$X]

## Root Cause
[Five Whys conclusion — the systemic cause, not the trigger]

## What Went Well
- [Detection was fast — monitoring caught it in 3 minutes]
- [Rollback was clean — no lasting data corruption]

## What Went Wrong
- [The deploy pipeline doesn't run integration tests]
- [No memory limit was set on the batch job pod]

## Action Items
| # | Action | Owner | Due | Priority |
|---|--------|-------|-----|----------|
| 1 | Add resource limits to all batch job pods | [Name] | YYYY-MM-DD | P0 |
| 2 | Require code review for all batch jobs | [Name] | YYYY-MM-DD | P1 |
| 3 | Add memory pressure alert for batch namespace | [Name] | YYYY-MM-DD | P1 |
| 4 | Create runbook for "payment service OOM" | [Name] | YYYY-MM-DD | P2 |

## Lessons Learned
[Key takeaways the team should remember]
```

### 5d. Action Item Standards

Every action item must be:
- **Specific**: "Add memory limits to order-batch deployment" not "Fix memory issue"
- **Assigned**: One owner per item — no shared ownership
- **Dated**: Realistic due date, not "ASAP"
- **Prioritized**: P0 (do before next deploy), P1 (this sprint), P2 (backlog)
- **Verified**: The action item must demonstrably prevent this class of incident — "add a test" is better than "be more careful"

### 5e. Runbook Creation

If the incident uncovered a scenario with no existing runbook, create one:

```markdown
# Runbook: [Failure Scenario]

## Alert
- **Alert name**: [e.g., PaymentServiceDown]
- **Severity**: [critical / warning]
- **Dashboard**: [link to relevant Grafana dashboard]

## Symptoms
- [What the on-call engineer will see: error messages, metric changes, user reports]

## Triage (first 3 minutes)
1. Check: `kubectl get pods -l app=payment-service`
2. Check: Recent deploys `kubectl rollout history deployment/payment-service`
3. Check: Downstream dependencies via `/actuator/health/readiness`

## Mitigation
- **Immediate (stop the bleeding)**: [Rollback / scale up / toggle flag / restart]
- **If that doesn't work**: [Escalate to payment team, check database health]

## Resolution
- [How to actually fix the root cause permanently]

## Post-Resolution
- [Any cleanup needed: drain queues, replay events, reconcile data]
```

Store runbooks in `docs/runbooks/` in the project repository — version-controlled, discoverable, and kept up to date.

## Quick Reference: Common Spring Boot Issues

```sh
# Dependency convergence check
mvn enforcer:enforce

# Show auto-configuration report (what beans are loaded and why)
# Add to application.yml: logging.level.org.springframework.boot.autoconfigure=DEBUG

# Check which beans are registered
# Inject ApplicationContext and call context.getBeanDefinitionNames()

# Profile active properties
mvn spring-boot:run -Dspring-boot.run.profiles=dev

# Test a single test method
mvn test -pl :module-name -Dtest=ClassName#methodName
./gradlew :module-name:test --tests "com.x.ClassName.methodName"

# Skip tests for quick compile check
mvn compile -DskipTests
./gradlew compileJava

# Re-run failed tests only
mvn test -Dfailsafe.rerunFailingTestsCount=2
```

## Checklist

- [ ] Error message fully read and understood
- [ ] Root cause identified (not just symptom)
- [ ] File and line located
- [ ] Recent changes checked (git diff/log)
- [ ] Fix applied — minimal change
- [ ] Build/compilation passes after fix
- [ ] Tests pass after fix
- [ ] Prevention recommendation given (if applicable)
- [ ] (P0/P1) Incident timeline reconstructed
- [ ] (P0/P1) Five Whys analysis completed — reached systemic root cause
- [ ] (P0/P1) Blameless postmortem drafted with action items
- [ ] (P0/P1) Action items are specific, assigned, dated, and prioritized
- [ ] (P0/P1) Runbook created or updated for this failure scenario

## Next Step
After the issue is diagnosed and fixed, use `/devskillslearning-pipeline:write-tests` to add regression tests preventing recurrence, then `/devskillslearning-pipeline:code-review` to verify the fix.
