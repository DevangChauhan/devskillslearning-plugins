# API Contract Examples

Full reference examples for the `design-api` skill. These are the canonical contract formats — the skill references these, keeping its instruction lean.

---

## OpenAPI 3.1 — REST API (Order Service)

```yaml
openapi: 3.1.0
info:
  title: Order Service API
  version: 1.0.0
  description: |
    REST API for order lifecycle management.
    Consumers: Mobile app (customer self-service), Admin dashboard (full access), Payment service (M2M charge/refund).

    ## Authentication
    All endpoints require JWT Bearer token. Customers access their own orders. Admins have full access. Payment service uses API key.

    ## Idempotency
    All mutating endpoints (POST/PUT/PATCH/DELETE) accept `Idempotency-Key` header. Duplicate keys with same body return the original response.

    ## Rate Limits
    - Customers: 100 req/min per user
    - Admins: 1000 req/min per user
    - M2M: 5000 req/min per API key

servers:
  - url: https://api.example.com/v1
    description: Production
  - url: https://api-staging.example.com/v1
    description: Staging

tags:
  - name: Orders
    description: Order lifecycle — create, read, update, cancel, track
  - name: Admin Orders
    description: Admin-only order management — search, bulk update, reports

paths:
  /orders:
    post:
      tags: [Orders]
      summary: Create a new order
      operationId: createOrder
      parameters:
        - name: Idempotency-Key
          in: header
          required: true
          schema:
            type: string
            format: uuid
          description: Client-generated unique key for safe retry
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CreateOrderRequest'
      responses:
        '201':
          description: Order created
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/OrderResponse'
          headers:
            Idempotency-Replayed:
              schema:
                type: boolean
              description: True if this is a replayed response
        '400':
          $ref: '#/components/responses/BadRequest'
        '401':
          $ref: '#/components/responses/Unauthorized'
        '409':
          $ref: '#/components/responses/Conflict'
        '422':
          $ref: '#/components/responses/UnprocessableEntity'
        '429':
          $ref: '#/components/responses/TooManyRequests'

    get:
      tags: [Orders]
      summary: List customer's orders
      operationId: listOrders
      parameters:
        - name: status
          in: query
          schema:
            $ref: '#/components/schemas/OrderStatus'
        - name: page
          in: query
          schema:
            type: integer
            default: 0
            minimum: 0
        - name: size
          in: query
          schema:
            type: integer
            default: 20
            minimum: 1
            maximum: 100
        - name: sort
          in: query
          schema:
            type: string
            default: createdAt,desc
            pattern: '^(createdAt|updatedAt|totalAmount),(asc|desc)$'
      responses:
        '200':
          description: Paginated list of orders
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/OrderPage'

  /orders/{orderId}:
    parameters:
      - name: orderId
        in: path
        required: true
        schema:
          type: string
          format: uuid
    get:
      tags: [Orders]
      summary: Get order by ID
      operationId: getOrder
      responses:
        '200':
          description: Order found
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/OrderResponse'
        '404':
          $ref: '#/components/responses/NotFound'

  /orders/{orderId}/cancel:
    post:
      tags: [Orders]
      summary: Cancel an order
      operationId: cancelOrder
      parameters:
        - name: Idempotency-Key
          in: header
          required: true
          schema:
            type: string
            format: uuid
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CancelOrderRequest'
      responses:
        '200':
          description: Order cancelled
        '409':
          description: Order cannot be cancelled in its current state

components:
  schemas:
    OrderStatus:
      type: string
      enum: [PENDING, CONFIRMED, PROCESSING, SHIPPED, DELIVERED, CANCELLED, REFUNDED]

    OrderResponse:
      type: object
      required: [id, customerId, status, items, totalAmount, currency, createdAt]
      properties:
        id:
          type: string
          format: uuid
        customerId:
          type: string
          format: uuid
        status:
          $ref: '#/components/schemas/OrderStatus'
        items:
          type: array
          items:
            $ref: '#/components/schemas/OrderItemResponse'
        totalAmount:
          type: string
          pattern: '^\d+\.\d{2}$'
          description: Monetary amount in the order currency, as string to avoid floating point issues
        currency:
          type: string
          minLength: 3
          maxLength: 3
          example: USD
        trackingNumber:
          type: string
          nullable: true
        estimatedDelivery:
          type: string
          format: date-time
          nullable: true
        createdAt:
          type: string
          format: date-time
        updatedAt:
          type: string
          format: date-time

    OrderItemResponse:
      type: object
      required: [productId, productName, quantity, unitPrice, lineTotal]
      properties:
        productId:
          type: string
          format: uuid
        productName:
          type: string
        quantity:
          type: integer
          minimum: 1
        unitPrice:
          type: string
          pattern: '^\d+\.\d{2}$'
        lineTotal:
          type: string
          pattern: '^\d+\.\d{2}$'

    CreateOrderRequest:
      type: object
      required: [items, shippingAddress]
      properties:
        items:
          type: array
          minItems: 1
          maxItems: 50
          items:
            $ref: '#/components/schemas/CreateOrderItemRequest'
        shippingAddress:
          $ref: '#/components/schemas/Address'
        notes:
          type: string
          maxLength: 500

    CreateOrderItemRequest:
      type: object
      required: [productId, quantity]
      properties:
        productId:
          type: string
          format: uuid
        quantity:
          type: integer
          minimum: 1
          maximum: 999

    Address:
      type: object
      required: [line1, city, state, postalCode, country]
      properties:
        line1:
          type: string
          maxLength: 200
        line2:
          type: string
          maxLength: 200
        city:
          type: string
          maxLength: 100
        state:
          type: string
          maxLength: 100
        postalCode:
          type: string
          maxLength: 20
        country:
          type: string
          minLength: 2
          maxLength: 2
          description: ISO 3166-1 alpha-2

    CancelOrderRequest:
      type: object
      required: [reason]
      properties:
        reason:
          type: string
          enum: [CUSTOMER_REQUEST, PAYMENT_FAILED, FRAUD_SUSPECTED, OUT_OF_STOCK]
        notes:
          type: string
          maxLength: 500

    OrderPage:
      type: object
      required: [content, page, size, totalElements, totalPages]
      properties:
        content:
          type: array
          items:
            $ref: '#/components/schemas/OrderResponse'
        page:
          type: integer
        size:
          type: integer
        totalElements:
          type: integer
          format: int64
        totalPages:
          type: integer

    ProblemDetail:
      type: object
      required: [type, title, status, detail]
      properties:
        type:
          type: string
          format: uri
        title:
          type: string
        status:
          type: integer
        detail:
          type: string
        instance:
          type: string
          format: uri
        errorCode:
          type: string
        timestamp:
          type: string
          format: date-time

  responses:
    BadRequest:
      description: Validation error
      content:
        application/problem+json:
          schema:
            $ref: '#/components/schemas/ProblemDetail'
    Unauthorized:
      description: Missing or invalid credentials
      content:
        application/problem+json:
          schema:
            $ref: '#/components/schemas/ProblemDetail'
    NotFound:
      description: Resource not found
      content:
        application/problem+json:
          schema:
            $ref: '#/components/schemas/ProblemDetail'
    Conflict:
      description: Business rule conflict
      content:
        application/problem+json:
          schema:
            $ref: '#/components/schemas/ProblemDetail'
    UnprocessableEntity:
      description: Idempotency key conflict with different body
      content:
        application/problem+json:
          schema:
            $ref: '#/components/schemas/ProblemDetail'
    TooManyRequests:
      description: Rate limit exceeded
      content:
        application/problem+json:
          schema:
            $ref: '#/components/schemas/ProblemDetail'
      headers:
        Retry-After:
          schema:
            type: integer

  securitySchemes:
    BearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
    ApiKeyAuth:
      type: apiKey
      in: header
      name: X-API-Key

security:
  - BearerAuth: []
```

---

## AsyncAPI 3.0 — Event-Driven (Order Service)

```yaml
asyncapi: 3.0.0
info:
  title: Order Service Events
  version: 1.0.0
  description: Domain events published and consumed by the Order Service

servers:
  production:
    host: kafka-broker:9092
    protocol: kafka
    description: Production Kafka cluster

channels:
  orders.created:
    address: orders.created
    messages:
      OrderCreatedEvent:
        $ref: '#/components/messages/OrderCreatedEvent'
    description: Emitted when a new order is successfully created

  orders.shipped:
    address: orders.shipped
    messages:
      OrderShippedEvent:
        $ref: '#/components/messages/OrderShippedEvent'

  orders.delivered:
    address: orders.delivered
    messages:
      OrderDeliveredEvent:
        $ref: '#/components/messages/OrderDeliveredEvent'

  orders.cancelled:
    address: orders.cancelled
    messages:
      OrderCancelledEvent:
        $ref: '#/components/messages/OrderCancelledEvent'

  payments.charged:
    address: payments.charged
    messages:
      PaymentChargedEvent:
        $ref: '#/components/messages/PaymentChargedEvent'
    description: Consumed from Payment Service to confirm payment

operations:
  onOrderCreated:
    action: send
    channel:
      $ref: '#/channels/orders.created'
  onPaymentCharged:
    action: receive
    channel:
      $ref: '#/channels/payments.charged'

components:
  messages:
    OrderCreatedEvent:
      summary: Emitted when an order is created
      payload:
        type: object
        required: [eventId, eventType, eventVersion, occurredAt, orderId, customerId, totalAmount, items]
        properties:
          eventId:
            type: string
            format: uuid
          eventType:
            type: string
            const: OrderCreated
          eventVersion:
            type: string
            const: "1.0"
          occurredAt:
            type: string
            format: date-time
          orderId:
            type: string
            format: uuid
          customerId:
            type: string
            format: uuid
          totalAmount:
            type: string
            pattern: '^\d+\.\d{2}$'
          currency:
            type: string
            minLength: 3
            maxLength: 3
          items:
            type: array
            items:
              $ref: '#/components/schemas/OrderItemPayload'

    PaymentChargedEvent:
      summary: Consumed when payment is successfully charged
      payload:
        type: object
        required: [eventId, eventType, orderId, transactionId, amount]
        properties:
          eventId:
            type: string
            format: uuid
          eventType:
            type: string
            const: PaymentCharged
          orderId:
            type: string
            format: uuid
          transactionId:
            type: string
          amount:
            type: string
            pattern: '^\d+\.\d{2}$'

  schemas:
    OrderItemPayload:
      type: object
      required: [productId, productName, quantity, unitPrice]
      properties:
        productId:
          type: string
          format: uuid
        productName:
          type: string
        quantity:
          type: integer
        unitPrice:
          type: string
          pattern: '^\d+\.\d{2}$'
```

---

## gRPC — Order Service

```protobuf
syntax = "proto3";

package order.v1;

option java_package = "com.acme.orderservice.grpc";
option java_multiple_files = true;

service OrderService {
  rpc CreateOrder(CreateOrderRequest) returns (OrderResponse);
  rpc GetOrder(GetOrderRequest) returns (OrderResponse);
  rpc ListOrders(ListOrdersRequest) returns (ListOrdersResponse);
  rpc CancelOrder(CancelOrderRequest) returns (OrderResponse);
}

message CreateOrderRequest {
  repeated OrderItem items = 1;
  Address shipping_address = 2;
  string notes = 3;
  string idempotency_key = 4;  // client-generated UUID for safe retry
}

message OrderResponse {
  string id = 1;
  string customer_id = 2;
  OrderStatus status = 3;
  repeated OrderItem items = 4;
  int64 total_amount_cents = 5;  // monetary values in minor units (cents)
  string currency = 6;
  int64 created_at = 7;   // epoch millis
  int64 updated_at = 8;   // epoch millis
}

message OrderItem {
  string product_id = 1;
  string product_name = 2;
  int32 quantity = 3;
  int64 unit_price_cents = 4;
  int64 line_total_cents = 5;
}

message Address {
  string line1 = 1;
  string line2 = 2;
  string city = 3;
  string state = 4;
  string postal_code = 5;
  string country = 6;
}

message GetOrderRequest {
  string id = 1;
}

message ListOrdersRequest {
  OrderStatus status_filter = 1;
  int32 page = 2;
  int32 size = 3;
  string sort = 4;
}

message ListOrdersResponse {
  repeated OrderResponse content = 1;
  int32 page = 2;
  int32 size = 3;
  int64 total_elements = 4;
  int32 total_pages = 5;
}

message CancelOrderRequest {
  string id = 1;
  string reason = 2;
  string notes = 3;
  string idempotency_key = 4;
}

enum OrderStatus {
  ORDER_STATUS_UNSPECIFIED = 0;
  ORDER_STATUS_PENDING = 1;
  ORDER_STATUS_CONFIRMED = 2;
  ORDER_STATUS_SHIPPED = 3;
  ORDER_STATUS_DELIVERED = 4;
  ORDER_STATUS_CANCELLED = 5;
}
```

---

## GraphQL — Order Service

```graphql
type Query {
    order(id: ID!): Order
    orders(filter: OrderFilter, page: PageInput): OrderPage!
}

type Mutation {
    createOrder(input: CreateOrderInput!): CreateOrderPayload!
    cancelOrder(input: CancelOrderInput!): CancelOrderPayload!
}

type Order {
    id: ID!
    customerId: ID!
    status: OrderStatus!
    items: [OrderItem!]!
    totalAmount: Money!
    trackingNumber: String
    estimatedDelivery: DateTime
    createdAt: DateTime!
    updatedAt: DateTime!
}

type Money {
    amount: String!    # e.g. "29.99" — string to avoid floating point
    currency: String!   # ISO 4217, e.g. "USD"
}

type OrderItem {
    productId: ID!
    productName: String!
    quantity: Int!
    unitPrice: Money!
    lineTotal: Money!
}

enum OrderStatus {
    PENDING
    CONFIRMED
    PROCESSING
    SHIPPED
    DELIVERED
    CANCELLED
    REFUNDED
}

input CreateOrderInput {
    items: [CreateOrderItemInput!]!
    shippingAddress: AddressInput!
    notes: String
    idempotencyKey: ID!
}

input CreateOrderItemInput {
    productId: ID!
    quantity: Int!
}

input AddressInput {
    line1: String!
    line2: String
    city: String!
    state: String!
    postalCode: String!
    country: String!
}

type CreateOrderPayload {
    order: Order
    errors: [UserError!]!
}

type UserError {
    field: [String!]!
    message: String!
    code: String!
}

input CancelOrderInput {
    orderId: ID!
    reason: CancelReason!
    notes: String
    idempotencyKey: ID!
}

enum CancelReason {
    CUSTOMER_REQUEST
    PAYMENT_FAILED
    FRAUD_SUSPECTED
    OUT_OF_STOCK
}

type CancelOrderPayload {
    order: Order
    errors: [UserError!]!
}

input OrderFilter {
    status: OrderStatus
    createdAfter: DateTime
    createdBefore: DateTime
}

type OrderPage {
    content: [Order!]!
    page: Int!
    size: Int!
    totalElements: Int!
    totalPages: Int!
}

input PageInput {
    page: Int = 0
    size: Int = 20
    sort: String = "createdAt,desc"
}
```
