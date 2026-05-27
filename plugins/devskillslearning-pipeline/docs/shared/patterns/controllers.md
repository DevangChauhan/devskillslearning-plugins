# Controller Conventions

## Core Rules

- `@Validated` on controller class, `@Valid` on request bodies.
- Zero business logic — validate input, delegate to service, return response.
- Constructor injection only.
- Implements OpenAPI-generated interface when `openapi-generator` is used.
- Response wrapped in project's standard wrapper or `ResponseEntity<T>`.
- API versioning strategy consistent across all controllers.

## Canonical Controller

```java
@RestController
@RequestMapping("/api/v1/orders")
@RequiredArgsConstructor
@Validated
@Slf4j
public class OrderController implements OrdersApi {  // OpenAPI-generated

    private final OrderService service;

    @PostMapping
    @Timed(value = "orders.create.http", histogram = true)
    public ResponseEntity<ApiResponse<OrderResponse>> createOrder(
            @Valid @RequestBody CreateOrderRequest request,
            @RequestHeader(value = "Idempotency-Key") String idempotencyKey) {
        log.info("Creating order for customer: {}", request.customerId());
        var result = service.createOrder(request, idempotencyKey);
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiResponse.success(result));
    }

    @GetMapping("/{id}")
    public ResponseEntity<ApiResponse<OrderResponse>> getOrder(@PathVariable UUID id) {
        var result = service.getOrder(id);
        return ResponseEntity.ok(ApiResponse.success(result));
    }
}
```

## Idempotency Key Pattern

For mutating endpoints (POST, PUT, PATCH), support safe retries:

```
Client: POST /api/v1/orders  with  Idempotency-Key: abc-123
Server: Processes request, stores (key → response) mapping
Client: Same request again (network timeout retry)
Server: Returns cached response, does NOT process twice
```

Rules:
- Accept `Idempotency-Key: <UUID>` header on mutating endpoints.
- Store mapping: `idempotency_key → (status, response_body_hash)` with TTL (24h).
- First request: process, store response, return `201`/`200`.
- Duplicate with same body hash: return stored response, no side effects.
- Duplicate with different body: return `422 Unprocessable Entity`.
- Concurrent requests with same key: one wins, others get `409 Conflict`.
- Add `Idempotency-Replayed: true` response header when returning a cached response.
- Clean up expired keys via scheduled job or TTL index.

## API Versioning

Default to **URI path versioning** (`/api/v1/...`):

| Strategy | Example | When to use |
|----------|---------|------------|
| URI path (recommended) | `/api/v1/orders`, `/api/v2/orders` | REST APIs — simple, visible, easy to route |
| Header | `Accept: application/vnd.company.v2+json` | Content negotiation, clean URIs |
| Query param | `/api/orders?version=2` | Quick prototyping only |

Rules:
- Only version on **breaking changes** (field removal, type change, semantic change). Additive changes don't need a version bump.
- Support N-1 version for a deprecation window (e.g., 6 months).
- Announce deprecation via `Sunset` HTTP header and `Deprecation: true` header.
- Separate controller per version: `OrderControllerV1`, `OrderControllerV2` in `controller/v1/`, `controller/v2/`.
- Each version gets its own DTOs — never share between versions.
- Separate OpenAPI spec per version.
