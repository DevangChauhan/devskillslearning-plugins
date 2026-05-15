---
name: devskillslearning-pipeline:write-code
description: Write Java/Spring Boot implementation code following EasyBank conventions. Use when the user asks to implement an endpoint, feature, or service. Reads OpenAPI specs and generates controller, service, repository, entity, DTO, mapper, and tests.
type: skill
---

# Write Code

You are an expert Java/Spring Boot developer implementing features for the EasyBank microservices project. Follow every convention below — deviation means the build fails.

## Step 0: Load Context

Before writing any code, read these files to understand the target:

1. **OpenAPI spec** — `services/<service>/src/main/resources/openapi/openapi.yaml`
2. **Existing code in the service** — controller, service, repository, entity, mapper
3. **`CLAUDE.md`** — project-wide conventions
4. **`docs/CONVENTIONS.md`** — if this skill was installed from devskillslearning-plugins

## Step 1: Identify What to Build

Determine the scope:
- Single endpoint? → implement that endpoint's full stack
- New entity? → entity + repository + service + controller + mapper + DTOs
- New feature? → all layers for all affected endpoints

The OpenAPI spec is the **source of truth**. Controllers MUST implement the generated interface from `openapi-generator-maven-plugin`. The generated interfaces are at:
`services/<service>/target/generated-sources/openapi/src/main/java/com/easybank/<service>/controller/`

## Step 2: Implement Bottom-Up

Build in dependency order — each layer depends on the one before:

### 2a. Entity (`entity/`)

```java
@Entity
@Table(name = "accounts")
@Getter
@Setter
@NoArgsConstructor
public class Account {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(nullable = false, unique = true)
    private String accountNumber;

    @Enumerated(EnumType.STRING)
    private AccountType accountType;

    // audit fields
    @CreatedDate
    private Instant createdAt;
    @LastModifiedDate
    private Instant updatedAt;
}
```

Rules:
- `@Getter` + `@Setter` + `@NoArgsConstructor` individually — NEVER `@Data`
- Table name: plural snake_case (`@Table(name = "accounts")`)
- Audit fields on every entity: `createdAt`, `updatedAt`
- Use `@Enumerated(EnumType.STRING)` for enums
- UUID primary keys with `GenerationType.UUID`

### 2b. Repository (`repository/`)

```java
@Repository
public interface AccountRepository extends JpaRepository<Account, UUID> {
    Optional<Account> findByAccountNumber(String accountNumber);
    Page<Account> findByCustomerId(UUID customerId, Pageable pageable);
    boolean existsByCustomerId(UUID customerId);
}
```

Rules:
- Extends `JpaRepository<Entity, UUID>`
- Annotated `@Repository`
- Uses `Pageable` for list queries
- Derived query methods for lookups

### 2c. DTO (`dto/`)

Use Java **records** for DTOs:

```java
public record AccountResponse(
    UUID id,
    String accountNumber,
    AccountType accountType,
    String branchAddress,
    BigDecimal balance,
    UUID customerId,
    AccountStatus status,
    Instant createdAt,
    Instant updatedAt
) {}

public record CreateAccountRequest(
    @NotNull AccountType accountType,
    String branchAddress,
    @NotNull UUID customerId
) {}
```

Rules:
- Records for DTOs (immutable by default)
- `@NotNull`, `@Valid` on request DTOs
- Match the OpenAPI schema fields exactly
- Use `BigDecimal` for monetary values — NEVER `Double` or `float`

### 2d. Mapper (`mapper/`)

```java
@Mapper(componentModel = "spring")
public interface AccountMapper {
    AccountResponse toResponse(Account entity);
    Account toEntity(CreateAccountRequest request);
    void updateEntity(@MappingTarget Account entity, UpdateAccountRequest request);
}
```

Rules:
- `@Mapper(componentModel = "spring")` — injectable via constructor
- `toResponse` for entity → DTO
- `toEntity` for create request → entity
- `updateEntity` with `@MappingTarget` for updates

### 2e. Service Interface (`service/`)

```java
public interface AccountService {
    AccountResponse createAccount(CreateAccountRequest request);
    AccountResponse getAccount(UUID id);
    AccountPage listAccounts(int page, int size, String sort);
    AccountResponse updateAccount(UUID id, UpdateAccountRequest request);
    void closeAccount(UUID id);
}
```

### 2f. Service Implementation (`service/impl/`)

```java
@Service
@RequiredArgsConstructor
@Transactional
public class AccountServiceImpl implements AccountService {
    private final AccountRepository repository;
    private final AccountMapper mapper;

    @Override
    public AccountResponse createAccount(CreateAccountRequest request) {
        if (repository.existsByAccountNumber(/* ... */)) {
            throw new ConflictException("Account already exists");
        }
        var entity = mapper.toEntity(request);
        entity.setAccountNumber(generateAccountNumber());
        entity.setBalance(BigDecimal.ZERO);
        entity.setStatus(AccountStatus.ACTIVE);
        return mapper.toResponse(repository.save(entity));
    }
}
```

Rules:
- Constructor injection via `@RequiredArgsConstructor` (Lombok) or explicit constructor
- `@Transactional` on the class
- Business logic ONLY in service layer — never in controller
- Throw domain exceptions (`ConflictException`, `ResourceNotFoundException`) using `ErrorCode` values
- Validate business rules here (balance checks, status transitions, etc.)

### 2g. Controller (`controller/`)

The controller **implements** the OpenAPI-generated interface:

```java
@RestController
@RequiredArgsConstructor
@Validated
public class AccountController implements AccountsApi {
    private final AccountService service;

    @Override
    public AccountResponse createAccount(CreateAccountRequest request) {
        return service.createAccount(request);
    }

    @Override
    public AccountResponse getAccount(UUID id) {
        return service.getAccount(id);
    }

    @Override
    public AccountPage listAccounts(Integer page, Integer size, String sort) {
        return service.listAccounts(page != null ? page : 0, size != null ? size : 20, sort != null ? sort : "createdAt,desc");
    }
}
```

Rules:
- Implements the generated `XxxApi` interface — this guarantees the contract is met
- `@Validated` on the class
- Constructor injection only
- ZERO business logic — validate input, delegate, return
- Wrap responses in `ApiResponse<T>` if the generated interface doesn't already

### 2h. Exception Handler (`exception/`)

```java
@RestControllerAdvice
public class AccountExceptionHandler extends GlobalExceptionHandler {
    // Override or add service-specific handlers
}
```

## Step 3: Write Tests

After implementation, write tests following `docs/TESTING.md`:

1. **Unit test** for service (`@ExtendWith(MockitoExtension.class)`)
2. **Web layer test** for controller (`@WebMvcTest`)
3. **Integration test** (`@SpringBootTest` + Testcontainers)

## Step 4: Verify

Run these before declaring done:
```sh
mvn spotless:apply -pl services/<service>
mvn test -pl services/<service>
mvn clean verify -f pom.xml
```

## Checklist

Before finishing, verify:
- [ ] Controller implements generated OpenAPI interface
- [ ] Constructor injection on all classes
- [ ] ErrorCode enum used (never ad-hoc strings)
- [ ] ApiResponse<T> envelope on all responses
- [ ] BigDecimal for money, not Double
- [ ] Audit fields on entities (createdAt, updatedAt)
- [ ] Records for DTOs
- [ ] No @Data on entities
- [ ] No business logic in controllers
- [ ] ArchUnit test passes
- [ ] `mvn clean verify -f pom.xml` passes
