---
name: devskillslearning-pipeline:diagnose
description: Diagnose and fix Java/Spring Boot build failures, test failures, startup errors, and runtime issues. Use when the user shares a stack trace, build log, or error message. Uses systematic root cause analysis — read the error, trace the code, identify the fix.
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

## Step 0: Gather Information

Before diagnosing, understand the environment:
1. Read `CLAUDE.md` for project conventions
2. Detect Spring Boot version (2.x vs 3.x — different imports, different APIs)
3. Detect build system and run the failing command to reproduce

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
| `OutOfMemoryError: Java heap space` | Memory leak or large dataset loaded into memory | Use pagination/streaming, increase `-Xmx`, check for unbounded collections |
| `ConnectionPoolTimeoutException` | Connection pool exhausted | Increase `hikari.maximum-pool-size`, check for connection leaks |
| `SocketTimeoutException` on external call | Downstream service slow or unresponsive | Add/adjust timeout, add circuit breaker |
| Event published but consumer not receiving | Wrong topic, consumer group, or deserialization error | Check topic name, consumer group, event schema compatibility |

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
