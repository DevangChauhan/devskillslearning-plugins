---
name: devskillslearning-pipeline:database
description: Design and optimize database schemas, migrations, queries, and data models for Java/Spring Boot applications. Use when the user asks to design a schema, add migrations, optimize slow queries, review indexing strategy, set up connection pooling, configure read replicas, model data for CQRS/event sourcing, or audit migrations for no-downtime safety.
type: skill
---

# Database

You are a database architect working with Java/Spring Boot applications. Your goal: design and optimize the persistence layer for correctness, performance, and operational safety.

## What You Need to Provide

| Input | Required? | Example | Notes |
|-------|-----------|---------|-------|
| What to work on | Yes | "Design the schema for the Order Service" | Domain and scope |
| Database engine | Recommended | PostgreSQL 16 / MySQL 8.0 / Oracle 19c | I'll detect from datasource config |
| Specific concern | No | "The orders query by status is slow" | Performance/problem context |
| Data volumes | Recommended for perf | "~10M orders/month, 500 concurrent read queries" | Drives indexing and partitioning |
| Data retention | No | "Keep orders for 7 years, archive older" | Drives partitioning strategy |

**Examples**:
- "Design the database schema for the payment service"
- "Add a migration for soft-deleting orders"
- "The GET /orders?status=PENDING query takes 3 seconds with 5M rows — why and fix"
- "Review all migrations for no-downtime safety"
- "Set up read-write split with read replicas"

**I auto-discover**: Database engine and version, connection pool config, migration tool (Flyway/Liquibase), existing schemas and indexes, query patterns from repository code, N+1 risks.

## Step 0: Discover the Database

Follow `docs/shared/step0-discovery.md` to detect build system, Spring Boot version, architecture type, package layout, and all project conventions.

## Step 1: Determine Scope

| Request | What to implement |
|---------|-------------------|
| "Design schema" | New migration scripts + entity classes + indexes |
| "Add/alter migration" | New migration with safety review |
| "Optimize query" | Identify bottleneck, add indexes, rewrite query |
| "Review indexes" | Audit existing indexes, recommend adds/drops |
| "Set up read replicas" | Routing datasource config, read/write split |
| "Connection pool tuning" | HikariCP config optimization |
| "Data archival strategy" | Partitioning + archival job |
| "No-downtime migration review" | Audit migrations for lock duration, backfill safety |

## Step 2: Design and Implement

### 2a. Schema Design

**Naming conventions:**
- Tables: plural, snake_case — `orders`, `order_items`, `payment_transactions`
- Columns: singular, snake_case — `customer_id`, `created_at`, `is_active`
- PK: `id` (UUID) — never composite unless a join table
- FKs: `{referenced_table_singular}_id` — `customer_id` references `customers(id)`
- Indexes: `idx_{table}_{column(s)}` — `idx_orders_status`, `idx_orders_customer_id_status`
- Unique constraints: `uq_{table}_{column(s)}` — `uq_orders_order_number`
- Check constraints: `ck_{table}_{rule}` — `ck_orders_total_positive`
- Enums: CHECK constraint or lookup table — never use PostgreSQL ENUM type in production

**PostgreSQL migration example:**
```sql
-- V3__create_orders.sql
CREATE TABLE IF NOT EXISTS orders (
    id              UUID NOT NULL,
    order_number    VARCHAR(50) NOT NULL,
    customer_id     UUID NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    total_amount    NUMERIC(19,4) NOT NULL DEFAULT 0,
    currency        CHAR(3) NOT NULL DEFAULT 'USD',
    shipping_address JSONB,
    notes           TEXT,
    version         BIGINT NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT uq_orders_order_number UNIQUE (order_number),
    CONSTRAINT ck_orders_total_positive CHECK (total_amount >= 0),
    CONSTRAINT ck_orders_status_valid CHECK (status IN (
        'PENDING','CONFIRMED','PROCESSING','SHIPPED','DELIVERED','CANCELLED','REFUNDED'
    ))
);

CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_created_at ON orders(created_at DESC);
-- Composite index for the most common filtered list query
CREATE INDEX idx_orders_customer_status ON orders(customer_id, status);
-- Partial index for pending orders (small subset of total)
CREATE INDEX idx_orders_pending ON orders(created_at) WHERE status = 'PENDING';
-- GIN index on JSONB for shipping address queries
CREATE INDEX idx_orders_shipping ON orders USING GIN (shipping_address jsonb_path_ops);

CREATE TABLE IF NOT EXISTS order_items (
    id              UUID NOT NULL,
    order_id        UUID NOT NULL,
    product_id      UUID NOT NULL,
    product_name    VARCHAR(255) NOT NULL,
    quantity        INTEGER NOT NULL,
    unit_price      NUMERIC(19,4) NOT NULL,
    line_total      NUMERIC(19,4) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT fk_order_items_order FOREIGN KEY (order_id) REFERENCES orders(id),
    CONSTRAINT ck_order_items_quantity_positive CHECK (quantity > 0),
    CONSTRAINT ck_order_items_unit_price_positive CHECK (unit_price >= 0),
    CONSTRAINT ck_order_items_line_total_positive CHECK (line_total >= 0)
);

CREATE INDEX idx_order_items_order_id ON order_items(order_id);

-- Rollback:
-- DROP TABLE IF EXISTS order_items CASCADE;
-- DROP TABLE IF EXISTS orders CASCADE;
```

**Migration rules:**
- `CREATE TABLE IF NOT EXISTS` for idempotency
- Every table gets `created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP`
- Mutating tables get `updated_at TIMESTAMPTZ` + `version BIGINT NOT NULL DEFAULT 0`
- PKs are UUID (not SERIAL/BIGSERIAL) for distributed-friendliness
- Monetary columns: `NUMERIC(19,4)` — 4 decimal places for currency precision
- `JSONB` for semi-structured data (address, metadata), not `JSON`
- `TEXT` over `VARCHAR` for unbounded strings — add CHECK for length constraints
- Always document rollback in a comment
- Use `TIMESTAMPTZ` not `TIMESTAMP` — always store with timezone

### 2b. Indexing Strategy

**Index every:**
- Foreign key column
- Column used in `WHERE` clauses (especially with high selectivity)
- Column used in `ORDER BY` (with matching sort direction)
- Column used in `JOIN` conditions
- Composite: columns frequently queried together

**Do NOT index:**
- Low-cardinality columns (boolean, status with < 5 values) unless partial index
- Columns that are never queried
- Tables with very high write volume and low read volume
- Every column "just in case" — indexes slow down writes

**Partial indexes** (index only a subset of rows):
```sql
-- Only ~5% of orders are PENDING — index just those
CREATE INDEX idx_orders_pending ON orders(created_at) WHERE status = 'PENDING';

-- Active subscriptions
CREATE INDEX idx_subscriptions_active ON subscriptions(customer_id) WHERE status = 'ACTIVE';
```

**Covering indexes** (include additional columns to avoid heap lookup):
```sql
-- PostgreSQL 11+ — INCLUDE columns are not part of the search but available without heap fetch
CREATE INDEX idx_orders_list ON orders(customer_id, status)
    INCLUDE (order_number, total_amount, created_at);
```

**When to use each index type:**

| Type | When | Example |
|------|------|---------|
| B-tree (default) | Equality, range, sorting | `WHERE status = 'ACTIVE' ORDER BY created_at` |
| Hash | Equality only, no sorting | `WHERE api_key_hash = 'abc'` (but B-tree is fine) |
| GIN | Full-text search, JSONB containment, array containment | `WHERE shipping_address @> '{"city":"NYC"}'` |
| GiST | Geometric, full-text with ranking | `WHERE location <@ bounding_box` |
| BRIN | Very large tables with physical correlation | `WHERE created_at > '2025-01-01'` on append-only table |

### 2c. Query Optimization

**Common anti-patterns and fixes:**

**N+1 Queries:**
```java
// BAD - N+1: each order triggers a lazy load of items
List<Order> orders = repository.findByCustomerId(customerId);
// SELECT * FROM orders WHERE customer_id = ?
// SELECT * FROM order_items WHERE order_id = ?  -- N times

// GOOD - Single query with JOIN FETCH
@Query("""
    SELECT DISTINCT o FROM Order o
    LEFT JOIN FETCH o.items
    WHERE o.customerId = :customerId
    """)
List<Order> findWithItemsByCustomerId(@Param("customerId") UUID customerId);
```

**Missing index on filtered column:**
```sql
-- SLOW: full table scan on 10M rows searching by status
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'PENDING';
-- Seq Scan on orders (cost=0.00..250000.00 rows=5000 width=...)

-- FIX: add index
CREATE INDEX idx_orders_status ON orders(status);
-- Now: Index Scan using idx_orders_status (cost=0.42..500.00 rows=5000)
```

**WHERE clause that defeats index:**
```sql
-- BAD: function on indexed column prevents index use
SELECT * FROM orders WHERE LOWER(order_number) = 'ord-12345';
-- FIX: store normalized or use expression index
CREATE INDEX idx_orders_order_number_lower ON orders(LOWER(order_number));
```

**Pagination with OFFSET on large tables:**
```sql
-- BAD: OFFSET scans all skipped rows (slow at page 500)
SELECT * FROM orders ORDER BY created_at DESC LIMIT 20 OFFSET 10000;

-- GOOD: keyset pagination (seek method)
SELECT * FROM orders
WHERE created_at < :lastSeenCreatedAt
ORDER BY created_at DESC LIMIT 20;
```

**Missing query timeout:**
```java
// application.yml
spring:
  jpa:
    properties:
      jakarta:
        persistence:
          query:
            timeout: 5000  # 5-second timeout — fail fast, don't hang
```

### 2d. No-Downtime Migrations

**Rules for safe migrations on live tables:**

| Operation | Safe? | Risk | Mitigation |
|-----------|-------|------|------------|
| `CREATE TABLE` | Safe | None | — |
| `CREATE INDEX` | Safe (CONCURRENTLY) | Locks writes without CONCURRENTLY | `CREATE INDEX CONCURRENTLY` |
| `ALTER TABLE ... ADD COLUMN` (nullable) | Safe | None for nullable, default | Always add nullable or with default |
| `ALTER TABLE ... ADD COLUMN NOT NULL DEFAULT` | Dangerous | Rewrites whole table, holds ACCESS EXCLUSIVE lock | Add nullable → backfill → set NOT NULL |
| `DROP COLUMN` | Safe (if unused) | Code still referencing column | Deploy code that stops reading column first, then drop |
| `ALTER COLUMN ... TYPE` | Dangerous | Full table rewrite, exclusive lock | Create new column → dual-write → backfill → switch reads → drop old |
| `RENAME COLUMN` | Dangerous | Code references old name | Not worth it — use view or add new + deprecate old |
| `DROP TABLE` | Dangerous | Code still referencing | Remove code references first, then drop in next release |
| `ADD FOREIGN KEY` | Dangerous | `VALIDATE CONSTRAINT` locks both tables | Create NOT VALID → validate in separate transaction |

**Safe column addition pattern:**
```sql
-- Release N: Add nullable column (instant on PostgreSQL 11+)
ALTER TABLE orders ADD COLUMN IF NOT EXISTS tracking_number VARCHAR(50);

-- Release N+1: After backfill, set NOT NULL (safe because all rows have values)
ALTER TABLE orders ALTER COLUMN tracking_number SET NOT NULL;
```

**Safe index creation:**
```sql
-- CONCURRENTLY avoids locking the table for writes
-- Must be run outside a transaction block
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_tracking
    ON orders(tracking_number);
```

**Migration backfill safety:**
```sql
-- BAD: single UPDATE locks all matching rows
UPDATE orders SET status = 'ARCHIVED' WHERE created_at < '2020-01-01';

-- GOOD: batch update in chunks
-- Flyway callback or separate batch job
DO $$
DECLARE
    batch_count INT;
BEGIN
    LOOP
        WITH batch AS (
            SELECT id FROM orders
            WHERE created_at < '2020-01-01' AND status != 'ARCHIVED'
            LIMIT 1000
            FOR UPDATE SKIP LOCKED
        )
        UPDATE orders SET status = 'ARCHIVED'
        FROM batch WHERE orders.id = batch.id;
        GET DIAGNOSTICS batch_count = ROW_COUNT;
        EXIT WHEN batch_count = 0;
        COMMIT;
    END LOOP;
END $$;
```

### 2e. Connection Pool Tuning (HikariCP)

```yaml
spring:
  datasource:
    hikari:
      pool-name: ${spring.application.name}-pool
      # Connections = ((core_count * 2) + effective_spindle_count)
      # Formula: (CPU cores * 2) + (number of disks)
      # For a typical 4-core app server: 10 connections
      maximum-pool-size: 10
      # Minimum idle: keep enough to handle steady-state
      minimum-idle: 5
      # Connection timeout: how long to wait for a connection (fail fast)
      connection-timeout: 30000
      # Idle timeout: close connections idle longer than this
      idle-timeout: 600000
      # Max lifetime: close connections older than this (DB server timeout minus 2 min)
      max-lifetime: 1800000
      # Leak detection: log connections held longer than this (not prod-safe at zero)
      leak-detection-threshold: 60000
      # Read-only connection auto-detection
      read-only: false
```

**Connection pool sizing considerations:**
- PostgreSQL: one backend process per connection — keep pools modest
- MySQL: thread-per-connection model — more efficient, can pool higher
- Each service instance: 10-20 connections typical
- Microservice with N instances: `total_pool = max_db_connections / N`

### 2f. Read-Write Splitting (Read Replicas)

```java
@Configuration
public class DataSourceConfig {

    @Bean
    @Primary
    public DataSource routingDataSource(
            @Qualifier("writeDataSource") DataSource write,
            @Qualifier("readDataSource") DataSource read) {
        var resolver = new ReadWriteRoutingDataSource();
        resolver.setDefaultTargetDataSource(write);
        Map<Object, Object> targets = new HashMap<>();
        targets.put(RoutingType.WRITE, write);
        targets.put(RoutingType.READ, read);
        resolver.setTargetDataSources(targets);
        return resolver;
    }

    // Routing datasource
    public static class ReadWriteRoutingDataSource extends AbstractRoutingDataSource {
        @Override
        protected Object determineCurrentLookupKey() {
            return TransactionSynchronizationManager.isCurrentTransactionReadOnly()
                ? RoutingType.READ
                : RoutingType.WRITE;
        }
    }

    public enum RoutingType { READ, WRITE }
}
```

**Usage:** Mark read-only service methods with `@Transactional(readOnly = true)` — they automatically route to the read replica.

**Replication lag handling:**
```java
// After a write, subsequent read must go to primary to avoid stale data
@Transactional  // NOT readOnly — routes to primary
public OrderResponse createOrder(CreateOrderRequest req) {
    var saved = repository.save(entity);
    return mapper.toResponse(saved);  // reads from primary, no stale data risk
}
```

### 2g. Data Archival and Partitioning

**Table partitioning (PostgreSQL native):**
```sql
-- Partition orders by created_at month for large tables (> 100M rows)
CREATE TABLE orders (
    id UUID NOT NULL,
    -- ... columns ...
    created_at TIMESTAMPTZ NOT NULL
) PARTITION BY RANGE (created_at);

-- Monthly partitions
CREATE TABLE orders_2025_01 PARTITION OF orders
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
CREATE TABLE orders_2025_02 PARTITION OF orders
    FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');
-- Default partition catches future dates
CREATE TABLE orders_default PARTITION OF orders DEFAULT;
```

**Archival policy:**
```yaml
# application.yml
orders:
  archival:
    retention-months: 84     # 7 years
    partition-size: MONTHLY
    archive-strategy: DETACH  # Detach old partitions rather than DELETE
```

### 2h. CQRS Data Model

When the project uses CQRS, the database skill generates both read and write models:

**Write side (normalized, JPA):**
```java
@Entity
@Table(name = "orders")
public class Order {
    @Id private UUID id;
    @Column(nullable = false) private OrderStatus status;
    @OneToMany(mappedBy = "order", cascade = ALL)
    private List<OrderItem> items;
    // Normalized — full domain model
}
```

**Read side (denormalized, JDBC or native SQL):**
```sql
-- Materialized view for fast order listing queries
CREATE MATERIALIZED VIEW mv_order_summaries AS
SELECT
    o.id,
    o.customer_id,
    o.order_number,
    o.status,
    o.total_amount,
    o.currency,
    o.created_at,
    COUNT(oi.id) AS item_count,
    -- Denormalized: customer name embedded to avoid JOIN
    c.name AS customer_name
FROM orders o
JOIN customers c ON c.id = o.customer_id
LEFT JOIN order_items oi ON oi.order_id = o.id
GROUP BY o.id, c.name;

CREATE UNIQUE INDEX ON mv_order_summaries(id);

-- Refresh: concurrently (no read lock) on a schedule
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_order_summaries;
```

### 2i. Event Sourcing Schema

```sql
-- Event store table
CREATE TABLE IF NOT EXISTS event_store (
    id              BIGSERIAL NOT NULL,       -- Sequential ID for ordering
    aggregate_id    UUID NOT NULL,             -- Order ID, Account ID, etc.
    aggregate_type  VARCHAR(100) NOT NULL,     -- 'Order', 'Account'
    event_type      VARCHAR(100) NOT NULL,     -- 'OrderCreated', 'OrderShipped'
    event_version   VARCHAR(10) NOT NULL,      -- '1.0'
    payload         JSONB NOT NULL,            -- Event data
    metadata        JSONB,                     -- traceId, userId, etc.
    occurred_at     TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (id, aggregate_id)             -- Partition by aggregate for snapshot isolation
) PARTITION BY HASH (aggregate_id);

CREATE INDEX idx_event_store_aggregate ON event_store(aggregate_id, id);
CREATE INDEX idx_event_store_type ON event_store(event_type, occurred_at);

-- Snapshot table (for performance — rebuild from last snapshot instead of event #1)
CREATE TABLE IF NOT EXISTS snapshots (
    aggregate_id    UUID NOT NULL,
    aggregate_type  VARCHAR(100) NOT NULL,
    state           JSONB NOT NULL,
    last_event_id   BIGINT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (aggregate_id)
);

-- Rollback:
-- DROP TABLE IF EXISTS snapshots CASCADE;
-- DROP TABLE IF EXISTS event_store CASCADE;
```

## Step 3: Verify

```sh
# Run migrations
mvn flyway:migrate -pl :module-name
# or
mvn liquibase:update -pl :module-name

# Verify migration was applied
# Flyway:
mvn flyway:info -pl :module-name
# Liquibase:
mvn liquibase:status -pl :module-name

# Test rollback (Flyway - manual; Liquibase):
mvn liquibase:rollback -Dliquibase.rollbackCount=1 -pl :module-name

# Check indexes on table (connect to DB)
psql -d orderdb -c "\d orders"

# Explain slow queries
psql -d orderdb -c "EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE status = 'PENDING';"

# Check for missing indexes — queries doing Seq Scan on large tables
psql -d orderdb -c "
  SELECT schemaname, tablename, seq_scan, seq_tup_read,
    idx_scan, seq_tup_read / NULLIF(seq_scan, 0) AS avg_seq_tup
  FROM pg_stat_user_tables
  WHERE seq_scan > 0
  ORDER BY seq_tup_read DESC LIMIT 10;
"

# Run application tests
mvn test -pl :module-name
```

## Checklist

- [ ] Table names: plural, snake_case
- [ ] Column names: singular, snake_case
- [ ] PK: UUID (`id`), not SERIAL
- [ ] `created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP` on every table
- [ ] `updated_at TIMESTAMPTZ` + `version BIGINT` on mutating tables
- [ ] `NUMERIC(19,4)` for monetary columns — never `DOUBLE` or `FLOAT`
- [ ] FK columns indexed (every one)
- [ ] Composite indexes for common multi-column filter queries
- [ ] Partial indexes for queries on small subsets (e.g., PENDING orders)
- [ ] No OFFSET pagination on large tables — keyset pagination instead
- [ ] N+1 queries eliminated (JOIN FETCH or EntityGraph)
- [ ] Migration is idempotent (`IF NOT EXISTS`)
- [ ] Migration is no-downtime safe (CONCURRENTLY, nullable columns first, batched backfills)
- [ ] Rollback documented in migration comment
- [ ] HikariCP pool size tuned: ~10 per instance
- [ ] Query timeout configured globally (5s default)
- [ ] Read replicas configured with routing datasource (if needed)
- [ ] Materialized views for CQRS reads (if CQRS)
- [ ] Event store + snapshot tables (if event sourcing)
- [ ] Archival/partitioning strategy for large tables

## Next Step
After designing the schema and migrations, use `/devskillslearning-pipeline:write-code` to implement entities, repositories, and services on top of this schema.
