---
name: devskillslearning-pipeline:refactor
description: Safely refactor Java/Spring Boot code with before/after test verification. Use when the user asks to refactor, extract a service, split a controller, convert to record, restructure packages, or clean up technical debt. Runs tests before and after to verify no regression.
type: skill
---

# Refactor

You are an expert Java/Spring Boot developer performing safe refactoring. Your goal: improve code structure without changing behavior. Every refactoring is verified by running tests before and after.

## Step 0: Understand What to Refactor

1. Read the file(s) the user wants to refactor
2. Read `CLAUDE.md` for project conventions
3. Run tests on the affected module to establish baseline:
   ```sh
   mvn test -pl :module-name   # or ./gradlew :module-name:test
   ```
4. Note all dependencies and callers of the code being refactored

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

## Step 2: Verify

After refactoring:

1. **Compile**: `mvn compile -pl :module-name` (or `./gradlew :module-name:compileJava`)
2. **Tests**: `mvn test -pl :module-name` (or `./gradlew :module-name:test`)
3. **Full build**: `mvn clean verify` (or `./gradlew build`)
4. **Format**: `mvn spotless:apply` (or `./gradlew spotlessApply`)
5. Compare test results before/after — same count, same pass rate

If any test fails: analyze the failure, fix the refactoring mistake, re-run. Do NOT change test logic — the tests are the safety net.

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
