# JPA Query Patterns & N+1 Detection

The most common performance bug in JPA applications.

## N+1 Query Patterns

| Pattern | Detection | Fix |
|---------|-----------|-----|
| Loop fetch | `for`/`forEach` loop calling `repository.find*()` or accessing lazy-loaded collection | `@EntityGraph`, JOIN FETCH, or batch fetch |
| Eager loading | `@OneToMany(fetch = EAGER)` or `@ManyToOne(fetch = EAGER)` causing cartesian products | Use `LAZY` + explicit `@EntityGraph` where needed |
| Missing batch size | `@OneToMany` without `@BatchSize(size = 20)` causing per-entity lazy-load queries | Add `@BatchSize` or configure `hibernate.default_batch_fetch_size` |
| DTO projection loop | Fetching entities then mapping in a loop instead of using DTO projection in query | Use `@Query("SELECT new com.x.dto.XxxDto(...) FROM ...")` |

**Flag any loop containing a repository call as HIGH severity.**

## Fix: @EntityGraph

```java
@Repository
public interface OrderRepository extends JpaRepository<Order, UUID> {

    @EntityGraph(attributePaths = {"items", "items.product"})
    Optional<Order> findWithItemsById(UUID id);

    @EntityGraph(attributePaths = {"items"})
    List<Order> findAllWithItemsByCustomerId(UUID customerId);
}
```

## Fix: JOIN FETCH Query

```java
@Query("""
    SELECT DISTINCT o FROM Order o
    JOIN FETCH o.items i
    JOIN FETCH i.product
    WHERE o.customerId = :customerId
    """)
List<Order> findAllWithItemsAndProducts(@Param("customerId") UUID customerId);
```

## Fix: DTO Projection

```java
// Instead of: fetch entities → loop → map to DTOs
@Query("""
    SELECT new com.acme.orders.dto.OrderSummaryDto(
        o.id, o.customerId, o.status, COUNT(i), o.totalAmount
    )
    FROM Order o LEFT JOIN o.items i
    WHERE o.customerId = :customerId
    GROUP BY o.id, o.customerId, o.status, o.totalAmount
    """)
List<OrderSummaryDto> findSummariesByCustomerId(@Param("customerId") UUID customerId);
```

## @BatchSize

```java
@Entity
public class Order {
    @OneToMany(mappedBy = "order")
    @BatchSize(size = 20)
    private List<OrderItem> items;
}
```

Also configurable globally: `spring.jpa.properties.hibernate.default_batch_fetch_size=20`

## Caching Correctness

| Check | What to look for |
|-------|-----------------|
| Missing cache | Expensive computation or external call without `@Cacheable` |
| Stale cache | `@CachePut` without corresponding `@CacheEvict` on write path |
| Missing eviction | Entity updated/deleted but related caches not evicted |
| Wrong key | Non-unique key (e.g., `"accounts"` instead of `"accounts_" + #id`) |
| Self-invocation | `@Cacheable` on same-class method — AOP bypasses proxy |

## Query Anti-Patterns

- **OFFSET pagination** on large tables: use keyset/seek pagination instead
- **Function on indexed column**: `WHERE LOWER(col) = ?` defeats index; use expression index
- **Missing query timeout**: set `jakarta.persistence.query.timeout: 5000`
