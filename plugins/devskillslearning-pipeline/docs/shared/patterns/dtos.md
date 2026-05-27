# DTO Conventions

## Core Rules

- **Java records** for DTOs by default. Classes only if mutability is required.
- `BigDecimal` for monetary values — **never** `Double` or `float`.
- `Instant` for timestamps — **never** `Date`.
- `@NotNull`, `@Valid` on request DTO fields.
- Request DTOs: `XxxRequest`. Response DTOs: `XxxResponse`.
- Fields must match the API spec (OpenAPI or user spec) exactly.
- Monetary fields: explicitly documented precision and scale in schema/entity.

## Request DTO

```java
public record CreateOrderRequest(
    @NotNull UUID customerId,
    @NotEmpty List<OrderItemRequest> items,
    @Size(max = 500) String notes,
    @NotNull @Valid ShippingAddress shippingAddress
) {}
```

## Response DTO

```java
public record OrderResponse(
    UUID id,
    UUID customerId,
    BigDecimal totalAmount,
    OrderStatus status,
    Instant createdAt
) {}
```

## API Versioning and DTOs

- Separate DTOs per API version — never share between v1 and v2.
- Place in version-specific packages: `dto.v1.OrderResponse`, `dto.v2.OrderResponse`.
- Only version on breaking changes (field removal, type change, semantic change).
- Additive changes (new field, new endpoint) do NOT require a version bump.
