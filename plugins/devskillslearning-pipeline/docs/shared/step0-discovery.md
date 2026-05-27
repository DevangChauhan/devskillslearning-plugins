# Step 0: Project Discovery

Every skill begins by discovering the target project. Run this checklist before taking any action.

## 1. Read Project Conventions

Read `CLAUDE.md` at the project root — the primary source of conventions, architecture decisions, and tool preferences.

## 2. Detect Build System

| Aspect | Maven | Gradle |
|--------|-------|--------|
| Build command | `mvn clean verify` | `./gradlew build` |
| Single module | `mvn clean verify` | `./gradlew build` |
| Multi-module (specific) | `mvn clean verify -pl :module-name` | `./gradlew :module-name:build` |
| Formatting | `mvn spotless:apply` | `./gradlew spotlessApply` |
| Test (single module) | `mvn test -pl :module-name` | `./gradlew :module-name:test` |
| Test (single test) | `mvn test -pl :module-name -Dtest=ClassName#methodName` | `./gradlew :module-name:test --tests "com.x.ClassName.methodName"` |

## 3. Detect Spring Boot Version

Read `<version>` from `spring-boot-starter-parent` in `pom.xml`, or `springBootVersion` in `build.gradle`.

| Aspect | Spring Boot 2.x | Spring Boot 3.x |
|--------|----------------|-----------------|
| Package prefix | `javax.*` | `jakarta.*` |
| Spring Security | Builder chain (`.cors().and().csrf().disable()`) | Lambda DSL (`.cors(c -> {}).csrf(c -> c.disable())`) |
| Java baseline | Java 8-17 | Java 17+ |
| `@ConstructorBinding` | Required on config records | Auto-detected |
| Observability | Sleuth + Brave | Micrometer Tracing (built-in) |

## 4. Detect Architecture Type

Check dependencies and package structure:

| Architecture | Signal |
|-------------|--------|
| Monolith | Single module, no service discovery |
| Monolith + Modulith | `spring-modulith-starter-core` dependency, module-level packages |
| REST Microservices | Multiple modules, `spring-cloud-starter-netflix-eureka-client` or similar |
| Event-Driven Microservices | `spring-cloud-stream`, `spring-kafka` dependencies |
| Reactive | `spring-boot-starter-webflux` (not `web`) |

## 5. Detect Package Layout

Find the root package from `@SpringBootApplication` class location. Detect sub-packages:
`controller`, `service`, `service.impl`, `repository`, `entity`, `dto`, `mapper`, `config`, `exception`.

If package-by-feature is used, follow that convention.

## 6. Detect Libraries and Tools

| What | How to detect |
|------|---------------|
| Lombok | `@RequiredArgsConstructor`, `@Slf4j` present in existing code |
| MapStruct | `@Mapper(componentModel = "spring")` in existing code |
| Migration tool | `flyway-core` or `liquibase-core` dependency |
| Testcontainers | `testcontainers` in test dependencies |
| Database | `spring.datasource.url` in `application.yml` |
| Java version | `java.version` in `pom.xml` or `sourceCompatibility` in `build.gradle` |

## 7. Detect Error Handling Patterns

- Base exception class: scan for classes extending `RuntimeException`
- Error code enum: scan for enums with fields like `code`, `message`, `httpStatus`
- Response wrapper: scan controller return types for generic wrappers (`ApiResponse<T>`, `ResponseEntity<T>`)
- Global handler: find `@RestControllerAdvice` class

## 8. Greenfield Fallback

When the target project is empty or has no discoverable conventions:

1. Default to Spring Boot 3.x (latest stable) with Jakarta, Java 21
2. Default to Maven, Flyway, Lombok, MapStruct, Java records for DTOs, UUID PKs
3. Create base classes first: `ErrorCode` enum, base exception, `ApiResponse<T>` wrapper, `@RestControllerAdvice`
4. Document decisions in the project's `CLAUDE.md`
