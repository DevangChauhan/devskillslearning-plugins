# Naming Conventions

## Java

| What | Convention |
|------|-----------|
| Controller methods | `getX`, `createX`, `updateX`, `deleteX` |
| REST paths | Plural nouns (`/api/v1/orders`, not `/api/v1/order`) |
| Service interface | `XxxService` |
| Service impl | `XxxServiceImpl` |
| Mapper (MapStruct) | `XxxMapper` |
| DTO records | `XxxRequest`, `XxxResponse` |
| Event classes | Past-tense verb + noun: `AccountCreatedEvent`, `PaymentProcessedEvent` |
| Event topics/channels | Descriptive kebab-case or dot-notation per project convention |

## Database

| What | Convention | Example |
|------|-----------|---------|
| Tables | Plural snake_case | `orders`, `order_items` |
| Columns | Singular snake_case | `customer_id`, `created_at` |
| Primary keys | `id` (UUID) | — |
| Foreign keys | `{referenced_table_singular}_id` | `customer_id` → `customers(id)` |
| Indexes | `idx_{table}_{column(s)}` | `idx_orders_status` |
| Unique constraints | `uq_{table}_{column(s)}` | `uq_orders_order_number` |
| Check constraints | `ck_{table}_{rule}` | `ck_orders_total_positive` |
| Audit columns | `created_at`, `updated_at`, `version` | On every mutating table |

## OpenAPI / AsyncAPI

| What | Convention |
|------|-----------|
| REST paths | `/api/v{major}/{plural-resource}` |
| Event channel names | `{domain}.{action}` — `orders.created`, `payments.charged` |
| Event type names | Past-tense nouns — `OrderCreated`, `PaymentCharged` |
| Scopes | `{action}:{resource}` — `read:orders`, `write:orders` |
