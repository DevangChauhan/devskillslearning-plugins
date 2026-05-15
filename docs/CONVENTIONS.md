# EasyBank Coding Conventions

Reference for AI code generation. These rules are encoded in every skill.

## Package Structure

```
com.easybank.<service>/
├── controller/       # REST controllers (thin — delegate to service)
├── service/          # Interface
├── service/impl/     # Implementation
├── repository/       # Spring Data JPA
├── entity/           # JPA entities
├── dto/              # Request/response DTOs
├── mapper/           # MapStruct (entity ↔ DTO)
├── config/           # @Configuration
└── exception/        # @RestControllerAdvice
```

## Dependency Injection

- Constructor injection always — no `@Autowired` on fields.
- No setters for required dependencies.

## DTOs & Entities

- **Records over classes** for DTOs unless mutability is required.
- **No Lombok `@Data`** on JPA entities — use `@Getter`/`@Setter`/`@NoArgsConstructor` individually.
- Entity audit fields: `createdAt`, `updatedAt`.

## Controllers

- `@Validated` on controller class, `@Valid` on request bodies.
- Implement the OpenAPI-generated interface (from `openapi-generator-maven-plugin`).
- Return `ApiResponse<T>` from every endpoint.
- No business logic — validate input, call service, return response.

## Error Handling

- Domain exceptions extend `BaseException` (in `easybank-common`).
- Use `ErrorCode` enum values — never ad-hoc strings.
- Each service has a `@RestControllerAdvice` extending `GlobalExceptionHandler`.

## Naming

| What | Convention | Example |
|------|-----------|---------|
| Controller methods | `getX`, `createX`, `updateX`, `deleteX` | `getAccount` |
| DB tables | plural snake_case | `accounts` |
| REST paths | plural nouns | `/api/v1/accounts` |
| Config keys | kebab-case | `my-service.retry.max` |

## Service Layer

- One service interface per aggregate.
- Implementation in `service/impl/`.
- Each service owns its database exclusively — no cross-service DB access.

## Testing

- **Unit**: `@ExtendWith(MockitoExtension.class)`, `@Mock` + `@InjectMocks`
- **Web layer**: `@WebMvcTest`, `@MockBean` service, `MockMvc`
- **Integration**: `@SpringBootTest` (RANDOM_PORT), Testcontainers PostgreSQL, RestAssured
- ArchUnit `ArchitectureTest` enforces package structure at build time.

## Build

- Java 21, Spring Boot 3.2.4, Spring Cloud 2023.0.0
- `mvn clean verify -f pom.xml` must pass before committing.
- Spotless formatting runs at `validate` phase.
- OpenAPI generator runs at `generate-sources` phase.
