# JPA Entity Conventions

## Core Rules

- `@Getter` + `@Setter` + `@NoArgsConstructor` individually — **never** `@Data` on JPA entities.
- Audit fields on every entity: `createdAt`, `updatedAt` (use `@CreatedDate` / `@LastModifiedDate` with `@EnableJpaAuditing`).
- UUID primary keys with `GenerationType.UUID` (preferred) or `GenerationType.IDENTITY` for MySQL.
- `@Enumerated(EnumType.STRING)` for all enum fields.
- No business logic in entities: no `@Transactional`, no service/repository calls, no injected dependencies.
- Monetary fields: explicit `precision` and `scale` on `@Column`.
- `@Version` for optimistic locking on entities that experience concurrent updates.
- Table name is plural snake_case.

## Canonical Entity

```java
@Entity
@Table(name = "orders")
@Getter
@Setter
@NoArgsConstructor
public class Order {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "customer_id", nullable = false)
    private UUID customerId;

    @Column(nullable = false, precision = 19, scale = 4)
    private BigDecimal totalAmount;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private OrderStatus status;

    @Version
    private Long version;

    @CreatedDate
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @LastModifiedDate
    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;
}
```

## Enum Fields

Always `EnumType.STRING` — ordinal breaks when enum order changes:

```java
@Enumerated(EnumType.STRING)
@Column(name = "status", nullable = false, length = 20)
private OrderStatus status;
```

## Lombok Anti-Pattern: @Data on Entities

`@Data` generates `equals`/`hashCode`/`toString` using all fields, which causes:
- Recursive `toString` with lazy-loaded `@OneToMany` collections
- `equals`/`hashCode` instability when `@Id` is null (before persist)

**Fix**: Replace `@Data` with `@Getter`, `@Setter`, `@NoArgsConstructor`. Write explicit `equals`/`hashCode` using only the `@Id` field.

## @Version for Optimistic Locking

```java
@Version
private Long version;
```

When present, Hibernate increments on each update. `ObjectOptimisticLockingFailureException` is thrown on concurrent modification — handle in the service layer with a retry or by reporting the conflict to the caller.
