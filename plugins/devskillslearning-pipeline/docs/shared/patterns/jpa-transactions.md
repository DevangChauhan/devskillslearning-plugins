# JPA Transaction Rules

These issues compile fine but cause data corruption at runtime.

## Core Checks

| Check | What to look for |
|-------|-----------------|
| Self-invocation | `@Transactional` method called from same class via `this.method()` — Spring AOP doesn't intercept. Fix: inject `self` proxy or move to separate service. |
| Read-only writes | Write operations inside `@Transactional(readOnly = true)`. Fix: remove `readOnly` or move write to separate method. |
| Missing transaction | Database writes without `@Transactional`. Fix: add `@Transactional`. |
| Overly broad transaction | `@Transactional` on controller or method doing non-DB work (HTTP calls, file I/O). Fix: move `@Transactional` to service layer only. |
| Rollback semantics | Checked exceptions do NOT trigger rollback — only unchecked. Flag if `catch` swallows without rethrow. |
| Propagation mismatch | `@Transactional(propagation = REQUIRES_NEW)` used incorrectly, creating unintended independent transactions. |
| `@Version` missing | Entity with concurrent update risk but no `@Version` field. |

## Canonical Service Pattern

```java
@Service
@RequiredArgsConstructor
@Transactional
public class OrderServiceImpl implements OrderService {
    private final OrderRepository repository;

    @Override
    @Transactional(readOnly = true)
    public OrderResponse getOrder(UUID id) {
        return repository.findById(id)
            .map(this::toResponse)
            .orElseThrow(() -> new ResourceNotFoundException(ErrorCode.RESOURCE_NOT_FOUND, "Order not found: " + id));
    }

    @Override
    public OrderResponse createOrder(CreateOrderRequest request) {
        var entity = toEntity(request);
        return toResponse(repository.save(entity));
    }
}
```

## Self-Invocation Fix

```java
// WRONG — self-invocation bypasses proxy
public void processBatch(List<Order> orders) {
    orders.forEach(this::processOne);  // @Transactional on processOne ignored
}

// RIGHT — inject self reference
@Service
@RequiredArgsConstructor
public class OrderServiceImpl {
    private final OrderServiceImpl self;  // Spring injects the proxy

    public void processBatch(List<Order> orders) {
        orders.forEach(self::processOne);  // goes through proxy
    }
}
```

## Read Replica Routing

When read replicas are configured, `@Transactional(readOnly = true)` auto-routes to read replica. Write transactions go to primary.
