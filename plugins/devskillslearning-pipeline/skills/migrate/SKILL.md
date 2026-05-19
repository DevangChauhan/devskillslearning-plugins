---
name: devskillslearning-pipeline:migrate
description: Automate Java/Spring Boot version upgrades. Use when the user asks to upgrade Spring Boot (2.x→3.x), migrate javax to jakarta, upgrade Java versions, or replace deprecated APIs. Runs tests before and after to verify no regression.
type: skill
---

# Migrate

You automate Java/Spring Boot version upgrades with safety. Every migration is verified by running tests before and after. Never leave a project in a broken state.

## What You Need to Provide

| Input | Required? | Example | Notes |
|-------|-----------|---------|-------|
| Migration target | Yes | "Upgrade from Spring Boot 2.7 to 3.3" or "Migrate Java 11 to 21" | What version you're moving to |
| What to migrate | Recommended | "The order service module" | Specific module or entire project |
| Known issues | Recommended | "We use custom Hibernate types that might break" | Heads-up about tricky areas |

**Examples**:
- "Upgrade the payment service from Spring Boot 2.7.18 to 3.3.5"
- "Migrate all services from Java 17 to Java 21"
- "Upgrade the entire monolith from Spring Boot 3.2 to 3.3"
- "Replace all javax imports with jakarta in the :common module"

**Safety guarantee**: I run the full build BEFORE and AFTER. If anything breaks, I fix the migration issues — never leave a broken build.

## Step 0: Assess Current State

1. Read `CLAUDE.md` for project conventions
2. Detect current versions:
   - `pom.xml` or `build.gradle`: Spring Boot version, Java version, dependency versions
   - Check `spring-boot-starter-parent` or plugin version
3. Identify target version (user specifies, or suggest latest stable)
4. Run tests on the current codebase to establish baseline:
   ```sh
   mvn clean verify   # or ./gradlew build
   ```

## Step 1: Choose Migration Path

| Migration | Trigger | Effort |
|-----------|---------|--------|
| Spring Boot 3.2.x → 3.3.x | Minor upgrade | Low |
| Spring Boot 3.1.x → 3.2.x | Minor upgrade | Low |
| Spring Boot 3.x → 3.x (latest) | Patch | Low |
| **Spring Boot 2.7.x → 3.x** | **Major — javax→jakarta** | **High** |
| Java 17 → 21 | Language upgrade | Medium |
| Java 11 → 17 | Language + API upgrade | Medium |
| Spring Cloud 2022.x → 2023.x | Cloud upgrade | Medium |

## Step 2: Spring Boot 2.x → 3.x Migration (Major)

### 2a. Pre-migration Checklist
```sh
# Verify all tests pass on current version
mvn clean verify

# Check for deprecated APIs (will be removed in Boot 3.x)
mvn dependency:tree | grep -E "javax|swagger|hibernate-validator"
```

### 2b. Update Build File

**pom.xml:**
```xml
<parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.3.5</version>  <!-- was 2.7.x -->
</parent>

<properties>
    <java.version>17</java.version>  <!-- was 8 or 11 -->
</properties>
```

**build.gradle:**
```groovy
plugins {
    id 'org.springframework.boot' version '3.3.5'  // was 2.7.x
}
java.sourceCompatibility = JavaVersion.VERSION_17  // was 8 or 11
```

### 2c. javax → jakarta Migration (CRITICAL)

Replace ALL `javax.*` imports with `jakarta.*`:

| javax | jakarta |
|-------|---------|
| `javax.persistence.*` | `jakarta.persistence.*` |
| `javax.validation.*` | `jakarta.validation.*` |
| `javax.servlet.*` | `jakarta.servlet.*` |
| `javax.transaction.*` | `jakarta.transaction.*` |
| `javax.annotation.*` | `jakarta.annotation.*` |

Systematic approach:
```sh
# Find all javax imports
grep -r "import javax\." --include="*.java" src/

# Replace each category
find src/ -name "*.java" -exec sed -i \
  -e 's/javax\.persistence/jakarta.persistence/g' \
  -e 's/javax\.validation/jakarta.validation/g' \
  -e 's/javax\.servlet/jakarta.servlet/g' \
  -e 's/javax\.transaction/jakarta.transaction/g' \
  -e 's/javax\.annotation/jakarta.annotation/g' {} +
```

Also update:
- `@javax.annotation.PostConstruct` → `@jakarta.annotation.PostConstruct`
- Entity annotations: `@Entity`, `@Table`, `@Column` (same name, different package)
- Validation annotations: `@NotNull`, `@Valid` (same name, different package)

### 2d. Spring Security 5.x → 6.x Migration

| 5.x (Builder DSL) | 6.x (Lambda DSL) |
|-------------------|------------------|
| `.authorizeRequests().antMatchers(...).permitAll()` | `.authorizeHttpRequests(auth -> auth.requestMatchers(...).permitAll())` |
| `.csrf().disable()` | `.csrf(csrf -> csrf.disable())` |
| `.cors().and()` | `.cors(cors -> cors.configurationSource(...))` |
| `.oauth2ResourceServer(OAuth2ResourceServerConfigurer::jwt)` | `.oauth2ResourceServer(oauth2 -> oauth2.jwt(...))` |
| `.sessionManagement().sessionCreationPolicy(STATELESS)` | `.sessionManagement(session -> session.sessionCreationPolicy(STATELESS))` |
| `Reactive: .authorizeExchange().pathMatchers(...)` | `.authorizeExchange(auth -> auth.pathMatchers(...))` |

**Before (Boot 2.x):**
```java
http.authorizeRequests()
    .antMatchers("/actuator/health/**").permitAll()
    .anyRequest().authenticated()
    .and()
    .oauth2ResourceServer(OAuth2ResourceServerConfigurer::jwt)
    .sessionManagement().sessionCreationPolicy(SessionCreationPolicy.STATELESS)
    .csrf().disable();
```

**After (Boot 3.x):**
```java
http.authorizeHttpRequests(auth -> auth
    .requestMatchers("/actuator/health/**").permitAll()
    .anyRequest().authenticated())
    .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()))
    .sessionManagement(session -> session.sessionCreationPolicy(STATELESS))
    .csrf(csrf -> csrf.disable());
```

### 2e. Deprecated API Replacements

| Removed/Deprecated | Replacement |
|--------------------|-------------|
| `@EnableGlobalMethodSecurity` | `@EnableMethodSecurity` |
| `WebSecurityConfigurerAdapter` | `SecurityFilterChain` bean |
| `spring.factories` auto-config | `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports` |
| `MockedStatic` (old Mockito) | `MockedStatic` (Mockito 5.x, same API) |
| `JUnit 4` (`@RunWith`) | JUnit 5 (`@ExtendWith`) |
| `@SpringBootTest(webEnvironment = RANDOM_PORT)` | Same (still valid) |
| `spring.h2.console.enabled` | `spring.h2.console.enabled=true` (still valid, but prefer Testcontainers) |
| `@ConfigurationProperties` without `@ConfigurationPropertiesScan` | Add `@ConfigurationPropertiesScan` on main class |
| `spring.data.jpa.repositories.bootstrap-mode` | Removed — Spring Boot 3.x infers from classpath |
| `spring.flyway.baseline-version` | `spring.flyway.baseline-on-migrate=true` |

### 2f. Actuator Changes

| 2.x | 3.x |
|-----|-----|
| `management.endpoints.web.exposure.include` | Same |
| `management.endpoint.health.show-details` | `management.endpoint.health.show-components` + `show-details` |
| `management.metrics.export.*` | `management.<system>.metrics.export.*` |

### 2g. Hibernate 5.x → 6.x

- Query APIs changed: `session.createQuery("FROM X", X.class)` requires `SelectionQuery<X>`
- Sequence naming changed: `hibernate_sequence` → `entity_name_SEQ` by default
- `@TypeDef` and `@Type` removed for user types — use `@JdbcTypeCode` or `@JavaType`
- `hibernate.id.new_generator_mappings` removed — always uses pooled optimizers

## Step 3: Java Version Upgrades

### Java 11 → 17
- Enable preview features: `--enable-preview` for pattern matching, records, sealed classes
- Use records for DTOs: `record AccountResponse(...) {}` replaces `@Data class ...`
- Use pattern matching: `if (obj instanceof String s && !s.isEmpty())`
- Use `List.of()`, `Set.of()`, `Map.of()` for immutable collections
- `var` for local variables where type is obvious
- Switch expressions: `return switch(status) { case PENDING -> "Pending"; ... };`

### Java 17 → 21
- Virtual threads: `Executors.newVirtualThreadPerTaskExecutor()` (preview in 21, stable in 21+)
- Record patterns (preview): `if (point instanceof Point(int x, int y))`
- Pattern matching for switch: `switch(obj) { case String s -> ...; case Integer i -> ...; }`
- Sequenced collections: `list.getFirst()`, `list.getLast()`, `list.reversed()`
- String templates (preview): `STR."Hello \{name}"`
- Enable ZGC for containerized apps: `-XX:+UseZGC`

## Step 4: Dependency Updates

Update common dependencies alongside Spring Boot:

| Dependency | Boot 2.7.x | Boot 3.3.x |
|------------|-----------|-----------|
| Hibernate | 5.6.x | 6.4.x |
| Hibernate Validator | 6.2.x → javax | 8.0.x → jakarta |
| Tomcat | 9.x | 10.x |
| Jackson | 2.13.x | 2.15.x |
| Micrometer | 1.9.x | 1.12.x |
| Mockito | 4.x | 5.x |
| AssertJ | 3.22.x | 3.24.x |
| Testcontainers | 1.17.x | 1.19.x |
| Liquibase | 4.x | 4.x (compatible) |
| Flyway | 8.x | 9.x (newer migrations format) |

Check for compatibility:
```sh
mvn versions:display-dependency-updates
# or
./gradlew dependencyUpdates
```

## Step 5: Verify Migration

```sh
# 1. Compile
mvn clean compile
# Fix any compilation errors before proceeding

# 2. Run tests
mvn test

# 3. Full build
mvn clean verify

# 4. Format
mvn spotless:apply  # may flag changed imports
```

Common compilation errors and fixes:
| Error | Fix |
|-------|-----|
| `package javax.persistence does not exist` | Replace with `jakarta.persistence` |
| `cannot find symbol: class WebSecurityConfigurerAdapter` | Replace with `SecurityFilterChain` bean |
| `cannot find symbol: method antMatchers` | Replace with `requestMatchers` |
| `cannot find symbol: method authorizeRequests` | Replace with `authorizeHttpRequests` |
| `@ConstructorBinding` not required | Can remove on records in Boot 3.x |
| `AutoConfiguration.imports` not found | Move `spring.factories` entries |

## Step 6: Post-Migration Cleanup

- [ ] Remove any unused dependencies that were only needed for the old version
- [ ] Update `CLAUDE.md` with new version numbers and conventions
- [ ] Update CI pipeline Java version
- [ ] Update Dockerfile base image (e.g., `eclipse-temurin:17-jre` → `eclipse-temurin:21-jre`)
- [ ] Run full CI pipeline: `mvn clean verify`
- [ ] Test in staging before production deploy

## Automated Tools (Optional)

For large codebases, suggest these automation tools:

```sh
# OpenRewrite — automated Spring Boot 2→3 migration
mvn org.openrewrite.maven:rewrite-maven-plugin:run \
  -Drewrite.recipeArtifactCoordinates=org.openrewrite.recipe:rewrite-spring:LATEST \
  -Drewrite.activeRecipes=org.openrewrite.java.spring.boot3.UpgradeSpringBoot_3_2

# Find deprecated API usage
mvn org.owasp:dependency-check-maven:check

# Run the Spring Boot migration analysis
# https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-3.0-Migration-Guide
```

## Checklist

- [ ] Pre-migration tests passed (baseline established)
- [ ] Spring Boot parent/plugin version updated in build file
- [ ] Java version updated in build file (if applicable)
- [ ] All `javax.*` imports replaced with `jakarta.*`
- [ ] Spring Security config migrated to Lambda DSL
- [ ] `WebSecurityConfigurerAdapter` replaced with `SecurityFilterChain` bean
- [ ] `@EnableGlobalMethodSecurity` replaced with `@EnableMethodSecurity`
- [ ] `spring.factories` moved to `AutoConfiguration.imports` (if applicable)
- [ ] Deprecated API calls replaced
- [ ] Hibernate queries updated for 6.x
- [ ] Actuator config updated
- [ ] Dependencies updated to compatible versions
- [ ] Compilation passes: `mvn clean compile`
- [ ] Tests pass: `mvn test`
- [ ] Full build passes: `mvn clean verify`
- [ ] `CLAUDE.md` updated with new versions
- [ ] CI pipeline and Dockerfile updated

## Next Step
After migration, use `/devskillslearning-pipeline:write-tests` to verify all tests pass with the upgraded versions, then `/devskillslearning-pipeline:code-review` to check for migration-specific issues.
