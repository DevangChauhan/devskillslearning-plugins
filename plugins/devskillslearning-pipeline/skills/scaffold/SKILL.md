---
name: devskillslearning-pipeline:scaffold
description: Bootstrap a new Java/Spring Boot project or module from scratch. Use when the user asks to create a new project, start a new service, scaffold a module, or initialize a Spring Boot application. Sets up build files, package structure, base classes, config, and a health endpoint following best practices.
type: skill
---

# Scaffold Project

You are an expert Java/Spring Boot developer bootstrapping a new project. Your goal is to create a production-ready foundation that the `write-code` and `code-review` skills can build on.

## Step 1: Gather Requirements

Ask the user (or use defaults marked with *):

| Question | Options | Default |
|----------|---------|---------|
| Build system | Maven / Gradle / Gradle Kotlin DSL | Maven |
| Architecture | Monolith / Monolith with Spring Modulith / REST Microservices / Event-Driven Microservices | REST Microservices |
| Java version | 17 / 21 / 23 | 21* |
| Spring Boot version | 3.3.x / 3.2.x / latest stable | latest stable 3.x |
| Group ID | user provides | — |
| Artifact ID / service name | user provides | — |
| Database | PostgreSQL / MySQL / H2 (dev only) / None | PostgreSQL |
| Migration tool | Flyway / Liquibase / None | Flyway |
| Execution model | Blocking (Tomcat/JPA) / Reactive (Netty/R2DBC) | Blocking |
| Message broker | Kafka / RabbitMQ / None | None (Kafka if event-driven) |
| API protocol | REST / gRPC / GraphQL / REST + gRPC / REST + GraphQL | REST |
| API versioning | URI path / Header / None | URI path (`/api/v1/`) |
| Lombok | Yes / No | Yes |
| MapStruct | Yes / No | Yes |
| Docker | Yes / No | Yes |
| Deployment target | Kubernetes / Docker Compose / None | Kubernetes |
| CI/CD | GitHub Actions / GitLab CI / None | GitHub Actions |
| Multi-tenancy | None / Discriminator / Schema-per-tenant / Database-per-tenant | None |
| Redis | Yes / No | Yes |
| Batch processing | None / Spring Batch / @Scheduled only | None |
| i18n | Yes / No | No |
| Feature flags | Yes / No | No |
| WebSocket / SSE | None / WebSocket / SSE | None |

If the user provides a minimal prompt like "create a new project called order-service", use the defaults and state your assumptions.

## Step 2: Generate Project Structure

### 2a. Root directory layout

```
<artifact-id>/
├── pom.xml (or build.gradle)
├── Dockerfile
├── docker-compose.yml
├── CLAUDE.md
├── .gitignore
└── src/
    ├── main/
    │   ├── java/com/<group>/<artifact>/
    │   │   ├── <Artifact>Application.java
    │   │   ├── config/
    │   │   ├── controller/
    │   │   │   └── HealthController.java
    │   │   ├── service/
    │   │   ├── service/impl/
    │   │   ├── repository/
    │   │   ├── entity/
    │   │   ├── dto/
    │   │   ├── mapper/
    │   │   ├── exception/
    │   │   │   ├── GlobalExceptionHandler.java
    │   │   │   └── ErrorCode.java
    │   │   └── common/
    │   │       ├── ApiResponse.java
    │   │       └── BaseException.java
    │   └── resources/
    │       ├── application.yml
    │       └── db/migration/ (if Flyway)
    └── test/
        └── java/com/<group>/<artifact>/
            └── architecture/
                └── ArchitectureTest.java
```

### 2b. Build file (Maven example — default)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.3.5</version>
    </parent>

    <groupId>com.<company></groupId>
    <artifactId><service-name></artifactId>
    <version>0.0.1-SNAPSHOT</version>

    <properties>
        <java.version>21</java.version>
        <spring-cloud.version>2023.0.3</spring-cloud.version>
        <mapstruct.version>1.5.5.Final</mapstruct.version>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-jpa</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-validation</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-actuator</artifactId>
        </dependency>
        <dependency>
            <groupId>org.flywaydb</groupId>
            <artifactId>flyway-database-postgresql</artifactId>
        </dependency>
        <dependency>
            <groupId>org.postgresql</groupId>
            <artifactId>postgresql</artifactId>
            <scope>runtime</scope>
        </dependency>
        <!-- Observability -->
        <dependency>
            <groupId>io.micrometer</groupId>
            <artifactId>micrometer-tracing-bridge-brave</artifactId>
        </dependency>
        <dependency>
            <groupId>io.micrometer</groupId>
            <artifactId>micrometer-registry-prometheus</artifactId>
            <scope>runtime</scope>
        </dependency>
        <!-- Dev -->
        <dependency>
            <groupId>org.projectlombok</groupId>
            <artifactId>lombok</artifactId>
            <optional>true</optional>
        </dependency>
        <dependency>
            <groupId>org.mapstruct</groupId>
            <artifactId>mapstruct</artifactId>
            <version>${mapstruct.version}</version>
        </dependency>
        <!-- Test -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-testcontainers</artifactId>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>org.testcontainers</groupId>
            <artifactId>postgresql</artifactId>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>com.tngtech.archunit</groupId>
            <artifactId>archunit-junit5</artifactId>
            <version>1.3.0</version>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
                <configuration>
                    <excludes>
                        <exclude>
                            <groupId>org.projectlombok</groupId>
                            <artifactId>lombok</artifactId>
                        </exclude>
                    </excludes>
                </configuration>
            </plugin>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-compiler-plugin</artifactId>
                <configuration>
                    <annotationProcessorPaths>
                        <path><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId></path>
                        <path><groupId>org.mapstruct</groupId><artifactId>mapstruct-processor</artifactId>
                             <version>${mapstruct.version}</version></path>
                    </annotationProcessorPaths>
                </configuration>
            </plugin>
        </plugins>
    </build>
</project>
```

For Gradle, generate the equivalent `build.gradle.kts` with the same dependency set. For multi-module, create a root `pom.xml` with `<modules>` or root `settings.gradle` with `include`.

### 2c. Main application class

```java
package com.<company>.<artifact>;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;
import org.springframework.data.jpa.repository.config.EnableJpaAuditing;

@SpringBootApplication
@EnableJpaAuditing
@ConfigurationPropertiesScan
public class <Artifact>Application {
    public static void main(String[] args) {
        SpringApplication.run(<Artifact>Application.class, args);
    }
}
```

### 2d. Configuration (application.yml)

```yaml
server:
  port: ${SERVER_PORT:8080}

spring:
  application:
    name: <service-name>
  datasource:
    url: ${DATASOURCE_URL:jdbc:postgresql://localhost:5432/<service-name>}
    username: ${DATASOURCE_USERNAME:postgres}
    password: ${DATASOURCE_PASSWORD:postgres}
    hikari:
      maximum-pool-size: 10
      minimum-idle: 2
  jpa:
    hibernate:
      ddl-auto: validate
    open-in-view: false
  flyway:
    enabled: true
    baseline-on-migrate: true

management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus,metrics
  endpoint:
    health:
      show-details: when-authorized
      probes:
        enabled: true

logging:
  level:
    com.<company>: DEBUG
    org.springframework.web: INFO
  pattern:
    level: "%5p [${spring.application.name:},%X{traceId:-},%X{spanId:-}]"
```

### 2e. Base classes

**ErrorCode enum**:
```java
package com.<company>.<artifact>.exception;

import lombok.Getter;
import org.springframework.http.HttpStatus;

@Getter
public enum ErrorCode {
    RESOURCE_NOT_FOUND(HttpStatus.NOT_FOUND, "Requested resource was not found"),
    CONFLICT(HttpStatus.CONFLICT, "Resource already exists or state conflict"),
    BAD_REQUEST(HttpStatus.BAD_REQUEST, "Invalid request"),
    VALIDATION_ERROR(HttpStatus.BAD_REQUEST, "Request validation failed"),
    INTERNAL_ERROR(HttpStatus.INTERNAL_SERVER_ERROR, "An unexpected error occurred"),
    SERVICE_UNAVAILABLE(HttpStatus.SERVICE_UNAVAILABLE, "Service temporarily unavailable");

    private final HttpStatus httpStatus;
    private final String defaultMessage;

    ErrorCode(HttpStatus httpStatus, String defaultMessage) {
        this.httpStatus = httpStatus;
        this.defaultMessage = defaultMessage;
    }
}
```

**BaseException**:
```java
package com.<company>.<artifact>.exception;

import lombok.Getter;

@Getter
public class BaseException extends RuntimeException {
    private final ErrorCode errorCode;

    public BaseException(ErrorCode errorCode, String message) {
        super(message);
        this.errorCode = errorCode;
    }

    public BaseException(ErrorCode errorCode) {
        super(errorCode.getDefaultMessage());
        this.errorCode = errorCode;
    }
}
```

**Concrete exceptions**:
```java
public class ResourceNotFoundException extends BaseException {
    public ResourceNotFoundException(ErrorCode errorCode, String message) { super(errorCode, message); }
}

public class ConflictException extends BaseException {
    public ConflictException(ErrorCode errorCode, String message) { super(errorCode, message); }
}

public class BadRequestException extends BaseException {
    public BadRequestException(ErrorCode errorCode, String message) { super(errorCode, message); }
}
```

**ApiResponse wrapper**:
```java
package com.<company>.<artifact>.common;

import com.fasterxml.jackson.annotation.JsonInclude;
import java.time.Instant;

@JsonInclude(JsonInclude.Include.NON_NULL)
public record ApiResponse<T>(
    boolean success,
    String message,
    T data,
    String errorCode,
    Instant timestamp
) {
    public static <T> ApiResponse<T> success(T data) {
        return new ApiResponse<>(true, null, data, null, Instant.now());
    }

    public static <T> ApiResponse<T> error(String errorCode, String message) {
        return new ApiResponse<>(false, message, null, errorCode, Instant.now());
    }
}
```

**GlobalExceptionHandler**:
```java
package com.<company>.<artifact>.exception;

import com.<company>.<artifact>.common.ApiResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
@Slf4j
public class GlobalExceptionHandler {

    @ExceptionHandler(ResourceNotFoundException.class)
    public ResponseEntity<ApiResponse<Void>> handleNotFound(ResourceNotFoundException ex) {
        log.warn("Resource not found: {}", ex.getMessage());
        return ResponseEntity.status(ex.getErrorCode().getHttpStatus())
            .body(ApiResponse.error(ex.getErrorCode().name(), ex.getMessage()));
    }

    @ExceptionHandler(ConflictException.class)
    public ResponseEntity<ApiResponse<Void>> handleConflict(ConflictException ex) {
        log.warn("Conflict: {}", ex.getMessage());
        return ResponseEntity.status(ex.getErrorCode().getHttpStatus())
            .body(ApiResponse.error(ex.getErrorCode().name(), ex.getMessage()));
    }

    @ExceptionHandler(BadRequestException.class)
    public ResponseEntity<ApiResponse<Void>> handleBadRequest(BadRequestException ex) {
        log.warn("Bad request: {}", ex.getMessage());
        return ResponseEntity.status(ex.getErrorCode().getHttpStatus())
            .body(ApiResponse.error(ex.getErrorCode().name(), ex.getMessage()));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiResponse<Void>> handleUnexpected(Exception ex) {
        log.error("Unexpected error", ex);
        return ResponseEntity.status(500)
            .body(ApiResponse.error("INTERNAL_ERROR", "An unexpected error occurred"));
    }
}
```

**HealthController**:
```java
package com.<company>.<artifact>.controller;

import com.<company>.<artifact>.common.ApiResponse;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HealthController {

    @GetMapping("/api/v1/health")
    public ResponseEntity<ApiResponse<String>> health() {
        return ResponseEntity.ok(ApiResponse.success("healthy"));
    }
}
```

**Example Configuration Properties** (for the service's own config needs):

```java
package com.<company>.<artifact>.config;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Positive;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;
import java.time.Duration;

@Validated
@ConfigurationProperties(prefix = "<artifact>.api")
public record ApiConfig(
    @NotBlank String baseUrl,
    @Positive Duration connectTimeout,
    @Positive Duration readTimeout
) {}
```

For Spring Boot 2.x, add `@ConstructorBinding` on the record.
Place all `@ConfigurationProperties` classes in `config/`.
Add corresponding defaults in `application.yml`:

```yaml
<artifact>:
  api:
    base-url: https://api.example.com
    connect-timeout: 5s
    read-timeout: 30s
```

### 2f. Architecture test (ArchUnit)

```java
package com.<company>.<artifact>.architecture;

import com.tngtech.archunit.junit.AnalyzeClasses;
import com.tngtech.archunit.junit.ArchTest;
import com.tngtech.archunit.lang.ArchRule;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.classes;

@AnalyzeClasses(packages = "com.<company>.<artifact>")
public class ArchitectureTest {

    @ArchTest
    static final ArchRule controllersInControllerPackage = classes()
        .that().areAnnotatedWith(org.springframework.web.bind.annotation.RestController.class)
        .should().resideInAPackage("..controller..");

    @ArchTest
    static final ArchRule servicesInServiceImplPackage = classes()
        .that().areAnnotatedWith(org.springframework.stereotype.Service.class)
        .should().resideInAPackage("..service.impl..");

    @ArchTest
    static final ArchRule repositoriesInRepositoryPackage = classes()
        .that().areAnnotatedWith(org.springframework.stereotype.Repository.class)
        .should().resideInAPackage("..repository..");

    @ArchTest
    static final ArchRule entitiesInEntityPackage = classes()
        .that().areAnnotatedWith(jakarta.persistence.Entity.class)
        .should().resideInAPackage("..entity..");

    @ArchTest
    static final ArchRule controllersDependOnService = classes()
        .that().resideInAPackage("..controller..")
        .should().dependOnClassesThat().resideInAPackage("..service..");
}
```

### 2g. Docker support

**Dockerfile**:
```dockerfile
FROM eclipse-temurin:21-jre-alpine
COPY target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app.jar"]
```

**docker-compose.yml**:
```yaml
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: <service-name>
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data

  <service-name>:
    build: .
    ports:
      - "8080:8080"
    environment:
      DATASOURCE_URL: jdbc:postgresql://postgres:5432/<service-name>
      DATASOURCE_USERNAME: postgres
      DATASOURCE_PASSWORD: postgres
    depends_on:
      - postgres

volumes:
  pgdata:
```

### 2h. CLAUDE.md stub

Generate a minimal `CLAUDE.md` in the project root documenting the decisions made:
```markdown
# CLAUDE.md

## Build
- Maven: `mvn clean verify`
- Format: `mvn spotless:apply` (configure if needed)

## Architecture
- Type: <monolith|microservices|event-driven>
- Java 21, Spring Boot 3.3.x, PostgreSQL
- Flyway for migrations, Lombok + MapStruct

## Conventions
- See `docs/` for detailed conventions
- Package-by-layer: controller → service → repository → entity
```

### 2i. .gitignore

Standard Java/Maven .gitignore including: `target/`, `*.class`, `.idea/`, `*.iml`, `*.log`, `.env`, `build/`, `.gradle/`.

## Step 3: Event-Driven Additions

If the user chose event-driven, also generate:

1. **Kafka dependencies** in build file: `spring-cloud-stream-binder-kafka`, `spring-kafka`
2. **Kafka config** in `application.yml`:
```yaml
spring:
  cloud:
    stream:
      kafka:
        binder:
          brokers: ${KAFKA_BROKERS:localhost:9092}
      bindings:
        <service>-out-0:
          destination: <service>-events
          producer:
            use-native-encoding: true
  kafka:
    consumer:
      group-id: ${spring.application.name}
      auto-offset-reset: earliest
```
3. **Kafka** service in `docker-compose.yml`
4. **Outbox table migration** (first migration):
```sql
CREATE TABLE IF NOT EXISTS outbox_events (
    id UUID NOT NULL PRIMARY KEY,
    aggregate_type VARCHAR(100) NOT NULL,
    aggregate_id UUID NOT NULL,
    event_type VARCHAR(200) NOT NULL,
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    published_at TIMESTAMPTZ,
    PRIMARY KEY (id)
);
CREATE INDEX idx_outbox_published ON outbox_events(published_at) WHERE published_at IS NULL;
```
5. **Outbox entity + repository + scheduler** classes

## Step 4: Verify

After scaffolding:
```sh
# Maven
mvn clean verify
# Gradle
./gradlew build
```

Then tell the user:
- What was created and where
- Which defaults were assumed
- How to customize: edit `application.yml` for DB credentials, ports, etc.
- The health endpoint is at `GET /api/v1/health`
- Run `/devskillslearning-pipeline:write-code` to start adding features
