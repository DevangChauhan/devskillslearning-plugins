---
name: devskillslearning-pipeline:refactor
description: Safely refactor Java/Spring Boot code with before/after test verification. Use when the user asks to refactor, extract a service, split a controller, convert to record, restructure packages, or clean up technical debt. Runs tests before and after to verify no regression.
type: skill
---

# Refactor

You are an expert Java/Spring Boot developer performing safe refactoring. Your goal: improve code structure without changing behavior. Every refactoring is verified by running tests before and after.

## What You Need to Provide

| Input | Required? | Example | Notes |
|-------|-----------|---------|-------|
| What to refactor | Yes | "Extract PricingService from OrderServiceImpl" | Class, method, or package |
| Refactoring type | Recommended | Extract service / Split controller / Convert to record / Restructure packages | I can detect what's needed if you describe the problem |
| Why | No | "OrderService is 400 lines and handles pricing, notifications, and ordering" | Helps me understand the goal |

**Examples**:
- "Extract the pricing logic from OrderServiceImpl into a separate service"
- "Split OrderController — it has 12 endpoints mixing CRUD, search, and status"
- "Convert CreateOrderRequest to a record"
- "Replace @Data on the Account entity"
- "Move shared exception classes to the :common module"

**Safety guarantee**: I run tests BEFORE and AFTER every refactoring. If tests fail, I fix the refactoring — never the tests.

## Step 0: Understand What to Refactor

Follow `docs/shared/step0-discovery.md` to detect build system, Spring Boot version, architecture type, package layout, and all project conventions.

1. Read the file(s) the user wants to refactor
2. **Discover dependent modules** — find which other modules depend on the module being changed:
   ```sh
   # Maven: check which modules depend on your module
   mvn dependency:tree -pl :module-name -Dverbose | grep "from :"
   # Gradle: check project dependencies in settings.gradle and build files
   ```
3. Run tests on the affected module AND all transitive dependents to establish baseline:
   ```sh
   mvn test -pl :module-name -am   # -am = also-make (build dependents too)
   # or
   ./gradlew :module-name:test :dependent-module:test
   ```
4. **Check baseline is clean** — if tests already fail before refactoring, warn the user and record known failures. Do not proceed with a broken baseline.
5. Note all dependencies and callers of the code being refactored

## Step 1: Choose Refactoring

Based on what the user asked for or what you detect:

### 1a. Extract Service

When a service has grown too large (300+ lines, multiple responsibilities).

**Process:**
1. Identify cohesive groups of methods that form a sub-responsibility
2. Create a new service interface + impl in the same packages
3. Move methods and their injected dependencies to the new service
4. Update the original service: inject the new service, delegate calls
5. Update all callers of the moved methods
6. Run tests

**Example:**
```java
// BEFORE: OrderServiceImpl.java (400 lines, handles ordering + pricing + notifications)
@Service
@RequiredArgsConstructor
public class OrderServiceImpl implements OrderService {
    private final OrderRepository repository;
    private final PricingEngine pricingEngine;    // used by 3 pricing methods
    private final NotificationClient notifier;    // used by 4 notification methods

    // 15 order methods ...
    // 3 pricing methods ...
    // 4 notification methods ...
}

// AFTER: Extract PricingService and NotificationService
@Service
@RequiredArgsConstructor
public class OrderServiceImpl implements OrderService {
    private final OrderRepository repository;
    private final PricingService pricingService;
    private final OrderNotificationService notificationService;
    // only order methods remain (15 → much clearer)
}

@Service
@RequiredArgsConstructor
public class PricingServiceImpl implements PricingService {
    private final PricingEngine pricingEngine;
    // 3 pricing methods
}

@Service
@RequiredArgsConstructor
public class OrderNotificationServiceImpl implements OrderNotificationService {
    private final NotificationClient notifier;
    // 4 notification methods
}
```

### 1b. Split Controller

When a controller has too many endpoints or mixes unrelated resources.

**Process:**
1. Group endpoints by resource or concern
2. Create new controller class(es) with `@RestController` + `@RequestMapping` for the sub-path
3. Move methods to appropriate controller
4. Update OpenAPI-generated interface references if applicable
5. Run tests

**Example:** Split `OrderController` (12 endpoints) into `OrderController` (CRUD) + `OrderStatusController` (status transitions) + `OrderSearchController` (search/filtering)

### 1c. Convert to Record

When a POJO DTO is immutable and can be a Java record.

**Process:**
1. Verify the class has no setters, no mutable state
2. Check all usages — constructor calls become record canonical constructor
3. Convert: `class` → `record`, remove `@Getter`, `private final` fields, explicit constructor, `equals`, `hashCode`, `toString`
4. Lombok DTOs: remove `@Data` / `@Value` / `@Builder`, convert to record
5. If `@Builder` was used, add a manual builder or compact constructor
6. Run tests

**Example:**
```java
// BEFORE
@Data
@AllArgsConstructor
public class OrderResponse {
    private UUID id;
    private BigDecimal totalAmount;
    private OrderStatus status;
}

// AFTER
public record OrderResponse(
    UUID id,
    BigDecimal totalAmount,
    OrderStatus status
) {}
```

### 1d. Migrate from @Data on Entities

JPA entities with `@Data` cause issues (recursive `equals`/`hashCode`/`toString` with lazy-loaded collections).

**Process:**
1. Replace `@Data` with `@Getter`, `@Setter`, `@NoArgsConstructor`
2. Add explicit `equals`/`hashCode` using only the `@Id` field (or business key)
3. Add simple `toString` excluding lazy-loaded `@OneToMany`/`@ManyToMany` collections
4. Run tests — verify no Hibernate/Lombok interaction issues

### 1e. Extract Shared Code to Common Module

When duplicate code exists across modules/services.

**Process:**
1. Identify the duplicated classes/interfaces across modules
2. Create a common module if one doesn't exist: `:common` or `:shared`
3. Move shared code to common module, update package
4. Add common module as dependency in consuming modules' build files
5. Update imports in all consuming modules
6. Run tests in all affected modules

### 1f. Restructure Packages

When packages don't match the project's convention.

**Process:**
1. Read the target convention (CLAUDE.md or sibling modules)
2. Plan the move: old package → new package for each class
3. Move files, update package declarations
4. Update imports in all files that reference moved classes
5. Run tests

### 1g. Migrate Field Injection to Constructor Injection

When `@Autowired` is used on fields — the project convention is constructor injection.

**Process:**
1. Scan for `@Autowired` on fields (or fields without `final` that should be constructor-injected)
2. Add `private final` to each injected field
3. Add `@RequiredArgsConstructor` (Lombok) or write explicit constructor
4. Remove `@Autowired` annotations
5. Check for circular dependencies — constructor injection reveals these at startup
6. If circular dependency found: break with `@Lazy` on one side, or extract a third collaborator
7. Run tests

**Example:**
```java
// BEFORE
@Service
public class OrderService {
    @Autowired
    private OrderRepository repository;
    @Autowired
    private PaymentClient paymentClient;
}

// AFTER
@Service
@RequiredArgsConstructor
public class OrderService {
    private final OrderRepository repository;
    private final PaymentClient paymentClient;
}
```

### 1h. Replace Deprecated API

When the project uses APIs that are deprecated or removed in the detected Spring Boot / Java version.

**Systematic replacement table:**

| Deprecated | Replacement | Since |
|-----------|-------------|-------|
| `RestTemplate` | `RestClient` (sync) or `WebClient` (reactive) | Boot 3.2+ |
| `@Autowired` on field | Constructor injection + `@RequiredArgsConstructor` | Always |
| `java.util.Date` / `Calendar` | `java.time.Instant` / `LocalDateTime` | Java 8+ |
| `javax.*` imports | `jakarta.*` imports | Boot 3.x |
| `@RequestMapping(method = RequestMethod.GET)` | `@GetMapping` (or `@PostMapping`, `@PutMapping`, etc.) | Spring 4.3+ |
| `WebMvcConfigurerAdapter` | `WebMvcConfigurer` (interface, not abstract class) | Spring 5 / Boot 2.x |
| `MockitoAnnotations.initMocks(this)` | `@ExtendWith(MockitoExtension.class)` + `@Mock` | Mockito 3+ |
| `@RunWith(MockitoJUnitRunner.class)` | `@ExtendWith(MockitoExtension.class)` | JUnit 5 |
| `@RunWith(SpringRunner.class)` | `@ExtendWith(SpringExtension.class)` or `@SpringBootTest` | JUnit 5 |
| `expected` attribute of `@Test` | `assertThrows()` | JUnit 5 |

**Process:**
1. Identify deprecated APIs in the target files
2. Replace one API at a time (one commit per type)
3. Run tests after each replacement
4. Update imports — remove old, add new

### 1i. Extract Configuration into @ConfigurationProperties

When `@Value("${...}")` is scattered across the codebase. See `docs/shared/patterns/configuration-props.md` for full conventions.

**Process:**
1. Find all `@Value` annotations referencing the same prefix
2. Create a `@ConfigurationProperties` record with matching fields
3. Add `@Validated` and validation annotations
4. Replace each `@Value` injection with the typed config record injection
5. Ensure `@ConfigurationPropertiesScan` is on the main class
6. Run tests

**Example:**
```java
// BEFORE — scattered @Value
@Service
public class PaymentService {
    @Value("${payment.retry.max-attempts:3}")
    private int maxAttempts;
    @Value("${payment.retry.backoff:2s}")
    private Duration backoff;
    @Value("${payment.timeout:30s}")
    private Duration timeout;
}

// AFTER — typed config record
@ConfigurationProperties(prefix = "payment")
@Validated
public record PaymentConfig(
    @Positive int retryMaxAttempts,
    Duration retryBackoff,
    Duration timeout
) {}
```

### 1j. Remove Dead Code & Unused Dependencies

When the project has accumulated unused classes, methods, or dependencies. The test safety net makes this safe.

**Process — Dead code:**
1. Identify unused private methods (compiler warnings, or IDE "unused" inspection)
2. Identify classes with no references (search for class name across codebase)
3. Remove each dead element individually, run tests after each removal
4. If tests pass, the code was truly dead

**Process — Unused dependencies:**
```sh
# Maven
mvn dependency:analyze -pl :module-name
# Reports: "Used undeclared" (add to POM) and "Unused declared" (remove from POM)

# Gradle
./gradlew :module-name:dependencies --configuration compileClasspath | grep -E "FAILED|unused"
```

Rules:
- Do NOT remove dependencies flagged as "used undeclared" without adding explicit declarations first
- Spring Boot starter dependencies may appear unused (they bring transitive deps) — be conservative
- Test-scoped dependencies may appear unused by `dependency:analyze` — verify manually
- Always run full build after dependency removal: `mvn clean verify` or `./gradlew build`

## Step 2: Verify

After refactoring:

1. **Compile**: `mvn compile -pl :module-name -am` (or `./gradlew :module-name:compileJava`)
2. **Tests — module + dependents**:
   ```sh
   mvn test -pl :module-name -am   # -am = also-make — tests all transitive consumers
   # or for Gradle — explicitly list dependent modules
   ./gradlew :module-name:test :dependent-a:test :dependent-b:test
   ```
3. **Full build**: `mvn clean verify` (or `./gradlew build`)
4. **Format**: `mvn spotless:apply` (or `./gradlew spotlessApply`)
5. Compare test results before/after — same count, same pass rate

If any test fails: analyze the failure, fix the refactoring mistake, re-run. Do NOT change test logic — the tests are the safety net.

**Multi-module note**: Always use `-am` (also-make) in Maven to build and test modules that depend on the refactored module. For Gradle, explicitly list dependent modules. A refactoring in `:common` that passes `:common:test` but breaks `:order-service:test` is a failed refactoring.

## Step 3: Summarize

Report what was done:
- What was refactored and why
- Files created, modified, deleted
- Test results: before vs after
- If any callers needed updating (list them)

## Checklist

- [ ] Tests passed before refactoring
- [ ] All references to moved/renamed code updated
- [ ] No unused imports left behind
- [ ] Package declarations match file locations
- [ ] Build passes (`mvn clean verify` or `./gradlew build`)
- [ ] Formatting applied
- [ ] Zero behavior change — only structure/names
- [ ] If extracting to common module: build files updated, CI pipeline still covers it

## Next Step
After refactoring, use `/devskillslearning-pipeline:write-tests` to ensure refactored code has coverage, then `/devskillslearning-pipeline:code-review` to verify no regressions.
