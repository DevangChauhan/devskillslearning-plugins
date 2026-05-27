---
name: devskillslearning-pipeline:design-api
description: Design API contracts before implementation — OpenAPI, AsyncAPI, gRPC, GraphQL. Spec becomes source of truth for write-code. Use when: design API, create OpenAPI spec, define AsyncAPI channels, design gRPC schema.
type: skill
---

# Design API

You are an API architect designing contracts before a single line of implementation code is written. Your goal: produce a complete, reviewable API contract that `write-code` can implement from directly.

## What You Need to Provide

| Input | Required? | Example | Notes |
|-------|-----------|---------|-------|
| What API to design | Yes | "Design the Order Service REST API" | Domain and purpose |
| Resources / operations | Recommended | "CRUD for orders, checkout, cancel, track status" | What the API should do |
| Consumers | Recommended | "Mobile app (customer), admin dashboard, payment service (M2M)" | Drives auth, rate limiting, response shape |
| Domain model sketch | If available | "Order: id, customerId, items[], total, status, tracking" | I'll expand into full schemas |
| Non-functional requirements | No | "p99 < 200ms, 10K req/s, GDPR data residency" | Drives pagination, caching, filtering |

**Examples**:
- "Design a REST API for the Order Service — customers create/read orders, admins manage all"
- "Create an OpenAPI spec for the Payment Service with idempotent charge and refund"
- "Design AsyncAPI channels for order events: created, shipped, delivered, cancelled"
- "Define gRPC service contract for Inventory Service"

**I auto-discover**: Project architecture type, whether existing APIs use versioning, existing error response patterns, API gateway config, whether the project uses OpenAPI codegen already.

## Step 0: Discover the Project

Follow `docs/shared/step0-discovery.md` to detect build system, Spring Boot version, architecture type, package layout, and all project conventions.

## Step 1: Determine Scope

| Request | What to produce |
|---------|-----------------|
| "Design REST API" | OpenAPI 3.1 spec + Spring interface stubs + versioning strategy |
| "Design AsyncAPI" | AsyncAPI 3.0 spec + event schema files + channel definitions |
| "Design gRPC API" | `.proto` files + service definitions + message types |
| "Design GraphQL API" | `.graphqls` schema + resolver interface stubs |
| "Full API contract" | All of the above for the service, depending on its communication patterns |

## Step 2: Design

### 2a. OpenAPI 3.1 REST API

Produce `src/main/resources/openapi/{service}-api.yaml`. See `docs/api-examples.md` for the full annotated example.

**Key structure (skeleton):**
```yaml
openapi: 3.1.0
info:
  title: {Service} API
  version: 1.0.0
  description: |        # Consumers, auth, idempotency, rate limits
servers:
  - url: https://api.example.com/v1
tags:                     # One per resource group
paths:
  /{resource}:            # POST (create), GET (list)
  /{resource}/{id}:       # GET, PUT/PATCH
  /{resource}/{id}/{action}:  # POST for sub-resource actions
components:
  schemas:                # All DTOs, enums, ProblemDetail
  responses:              # Reusable error responses per status code
  securitySchemes:        # BearerAuth, ApiKeyAuth
security:                 # Default auth requirement
```

**OpenAPI design conventions:**

- **Monetary values**: Use `string` with regex pattern `^\d+\.\d{2}$` — never `number` for money
- **Timestamps**: `string` format `date-time` (RFC 3339)
- **IDs**: `string` format `uuid`
- **Enums**: Upper snake_case, explicitly listed values
- **Pagination**: `page` (0-based), `size` (default 20, max 100), `sort` (field,direction)
- **All mutating endpoints**: Accept `Idempotency-Key` header
- **Error responses**: RFC 7807 Problem Details (`application/problem+json`), typed per status code
- **Nullable fields**: Explicit `nullable: true` — never omit
- **Deprecation**: Use `deprecated: true` with `x-sunset` header extension

### 2b. API Versioning Strategy

**URL path versioning** (recommended for REST):
```
/api/v1/orders
/api/v2/orders
```

Version when:
- Removing or renaming a field (breaking change)
- Changing a field type (breaking change)
- Changing enum values (breaking change)
- Changing authentication requirements (breaking change)

Do NOT version when:
- Adding a new optional field
- Adding a new endpoint
- Adding a new optional query parameter
- Relaxing validation (e.g., increasing maxLength)

**Version sunset policy** (document in spec):
```yaml
info:
  x-sunset-policy:
    versions:
      v1:
        sunset-date: 2026-12-31
        notice-period: 90d
```

### 2c. AsyncAPI for Event-Driven Services

Produce `src/main/resources/asyncapi/{service}-events.yaml`. See `docs/api-examples.md` for the full annotated example.

**Key structure (skeleton):**
```yaml
asyncapi: 3.0.0
info:
  title: {Service} Events
  version: 1.0.0
servers:
  production:
    host: kafka-broker:9092
    protocol: kafka
channels:                 # One per event: {domain}.{action}
  orders.created:         # Published events
  payments.charged:       # Consumed events (from other services)
operations:               # send (publish) or receive (consume)
components:
  messages:               # Event payloads with eventId, eventType, eventVersion
  schemas:                # Reusable nested payloads
```

**Event schema conventions:**
- Every event MUST have: `eventId` (UUID for dedup), `eventType` (constant per event type), `eventVersion` (semver), `occurredAt` (when it happened)
- Channel naming: `{domain}.{action}` — `orders.created`, `payments.charged`
- Event types: past-tense nouns — `OrderCreated`, `PaymentCharged`, `ShipmentDelivered`
- Use `const` for `eventType` to match exactly one event type per message definition
- Monetary values as string — same as REST convention

### 2d. gRPC API

Produce `src/main/proto/{service}.proto`. See `docs/api-examples.md` for the full example.

**Key structure (skeleton):**
```protobuf
syntax = "proto3";
package {domain}.v1;
option java_package = "com.acme.{service}.grpc";
option java_multiple_files = true;

service {Service} {
  rpc CreateThing(CreateThingRequest) returns (ThingResponse);
  rpc GetThing(GetThingRequest) returns (ThingResponse);
  rpc ListThings(ListThingsRequest) returns (ListThingsResponse);
}
message ThingResponse { ... }
message CreateThingRequest { string idempotency_key = ...; }
enum ThingStatus { THING_STATUS_UNSPECIFIED = 0; ... }
```

**gRPC conventions:**
- Monetary values in minor units (cents) as `int64` — never `float` or `double`
- Timestamps as `int64` (epoch millis) OR `google.protobuf.Timestamp`
- Enum zero value is always `UNSPECIFIED`
- Package: `{domain}.v{version}`
- Include `idempotency_key` on all mutating RPCs

### 2e. GraphQL API

Produce `src/main/resources/graphql/{service}.graphqls`. See `docs/api-examples.md` for the full example.

**Key structure (skeleton):**
```graphql
type Query {
    thing(id: ID!): Thing
    things(filter: ThingFilter, page: PageInput): ThingPage!
}
type Mutation {
    createThing(input: CreateThingInput!): CreateThingPayload!
}
type Thing { id: ID! ... }
type Money { amount: String! currency: String! }   # Always string, never Float
input CreateThingInput { ... idempotencyKey: ID! }
type CreateThingPayload { thing: Thing errors: [UserError!]! }
type UserError { field: [String!]! message: String! code: String! }
enum ThingStatus { ... }
```

**GraphQL conventions:**
- Schema-first: `.graphqls` files are the contract, never generate schema from code
- Mutations return payloads with `UserError` — never throw for business errors
- Monetary wrapper type (`Money`) — string amounts, never `Float`
- `ID` type for all identifiers (UUID as string)
- Paginated lists return `Page` type with counts — cursors for very large datasets
- `idempotencyKey` on all mutating inputs

### 2f. Generate Spring Interfaces from OpenAPI

Configure `openapi-generator-maven-plugin` to generate only interfaces (no implementation):

```xml
<plugin>
    <groupId>org.openapitools</groupId>
    <artifactId>openapi-generator-maven-plugin</artifactId>
    <version>7.8.0</version>
    <executions>
        <execution>
            <goals><goal>generate</goal></goals>
            <configuration>
                <inputSpec>${project.basedir}/src/main/resources/openapi/order-service-api.yaml</inputSpec>
                <generatorName>spring</generatorName>
                <generateApis>true</generateApis>
                <generateModels>true</generateModels>
                <apiPackage>com.acme.orderservice.controller</apiPackage>
                <modelPackage>com.acme.orderservice.dto</modelPackage>
                <configOptions>
                    <interfaceOnly>true</interfaceOnly>
                    <useSpringBoot3>true</useSpringBoot3>
                    <useResponseEntity>false</useResponseEntity>
                    <skipDefaultInterface>true</skipDefaultInterface>
                    <openApiNullable>false</openApiNullable>
                </configOptions>
            </configuration>
        </execution>
    </executions>
</plugin>
```

For Spring Boot 2.x, set `<useSpringBoot3>false</useSpringBoot3>`.

When generated interfaces exist, controllers implement them:
```java
@RestController
@RequiredArgsConstructor
public class OrderController implements OrdersApi {
    private final OrderService service;
    // implement all generated methods
}
```

### 2g. API Security Design (Contract-Level)

Annotate the spec with security requirements:

```yaml
paths:
  /orders:
    post:
      security:
        - BearerAuth: [write:orders]
        - ApiKeyAuth: []
      x-rate-limit:
        per-minute: 100
        per-user: true

  /orders/{orderId}:
    get:
      security:
        - BearerAuth: [read:orders]
      x-rate-limit:
        per-minute: 200
        per-user: true

  /admin/orders:
    get:
      security:
        - BearerAuth: [admin:orders]
      x-rate-limit:
        per-minute: 1000
        per-user: true
```

**Scope naming convention**: `{action}:{resource}` — `read:orders`, `write:orders`, `admin:orders`

### 2h. API Design Review Checklist

Embed in the spec as `x-design-review`:

```yaml
x-design-review:
  consistency:
    - All monetary values use string pattern (not number)
    - All timestamps use date-time format
    - All IDs use uuid format
    - Pagination fields named page/size/totalElements/totalPages across all endpoints
  completeness:
    - Every endpoint has error responses: 400, 401, 403, 404, 409, 422, 429, 500
    - Every mutating endpoint accepts Idempotency-Key
    - Every response schema includes all required audit fields
    - Every array field has min/max constraints
  security:
    - Every endpoint has security requirements
    - Scopes follow {action}:{resource} convention
    - Rate limits defined per endpoint
  evolution:
    - Version reflected in URL path (/v1/) or content type
    - No backward-incompatible changes within a version
    - Deprecated fields marked with `deprecated: true` and migration notes
  documentation:
    - API description includes consumer list
    - Every path has a summary
    - Every parameter and schema property has a description
    - Non-obvious behavior (idempotency, caching, eventual consistency) documented
```

## Step 3: Verify

```sh
# Validate OpenAPI spec
npx @redocly/cli lint src/main/resources/openapi/order-service-api.yaml

# Generate to verify spec compiles
mvn openapi-generator:generate

# Compile generated sources
mvn compile

# Validate AsyncAPI spec (if generated)
npx @asyncapi/cli validate src/main/resources/asyncapi/order-service-events.yaml

# Validate GraphQL schema (if generated)
npx graphql-inspector validate src/main/resources/graphql/order-service.graphqls
```

## Checklist

- [ ] OpenAPI 3.1 spec written to `src/main/resources/openapi/`
- [ ] All monetary values as string with regex pattern (not `number`)
- [ ] All IDs as `string format: uuid`
- [ ] All enums explicitly listed, upper snake_case
- [ ] Pagination standardized: page (0-based), size (default 20, max 100), sort
- [ ] All mutating endpoints have `Idempotency-Key` header parameter
- [ ] Error responses defined per status code (400/401/403/404/409/422/429/500)
- [ ] RFC 7807 Problem Details schema for errors
- [ ] API versioning strategy documented
- [ ] AsyncAPI spec for event channels (if event-driven)
- [ ] `.proto` files for gRPC (if gRPC)
- [ ] `.graphqls` schema for GraphQL (if GraphQL)
- [ ] `openapi-generator-maven-plugin` configured for interface generation
- [ ] Security scopes follow `{action}:{resource}` convention
- [ ] Rate limits defined per endpoint group
- [ ] Spec passes Redocly lint with zero errors
- [ ] Generated interfaces compile successfully

## Next Step
After designing the API contract, use `/devskillslearning-pipeline:write-code` to implement from the spec. It will auto-detect the generated interfaces and implement controllers against them.
