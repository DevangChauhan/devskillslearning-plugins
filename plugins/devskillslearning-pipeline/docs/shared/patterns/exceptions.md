# Exception Handling & Error Responses

## Core Rules

- Domain exceptions extend a project base exception (or `RuntimeException` if none exists).
- Use an error code enum for consistent error categorization — never ad-hoc strings.
- `@RestControllerAdvice` handles all domain exceptions centrally.
- Never `catch (Exception e)` that swallows silently — always log or rethrow.
- Catch-all for unexpected exceptions (500) with no details leaked to client.

## Problem Details (RFC 7807) — Spring Boot 3.x

Spring Boot 3.x has built-in `ProblemDetail` support. Prefer this over custom error response classes.

```java
@RestControllerAdvice
@Slf4j
public class GlobalExceptionHandler {

    @ExceptionHandler(ResourceNotFoundException.class)
    public ProblemDetail handleNotFound(ResourceNotFoundException ex) {
        var problem = ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, ex.getMessage());
        problem.setTitle("Resource Not Found");
        problem.setProperty("errorCode", ex.getErrorCode().name());
        problem.setProperty("timestamp", Instant.now());
        return problem;
    }

    @ExceptionHandler(ConflictException.class)
    public ProblemDetail handleConflict(ConflictException ex) {
        var problem = ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT, ex.getMessage());
        problem.setTitle("Conflict");
        problem.setProperty("errorCode", ex.getErrorCode().name());
        problem.setProperty("timestamp", Instant.now());
        return problem;
    }

    @ExceptionHandler(Exception.class)
    public ProblemDetail handleUnexpected(Exception ex) {
        log.error("Unexpected error", ex);
        var problem = ProblemDetail.forStatusAndDetail(
            HttpStatus.INTERNAL_SERVER_ERROR, "An unexpected error occurred");
        problem.setTitle("Internal Server Error");
        problem.setProperty("timestamp", Instant.now());
        return problem;
    }
}
```

Produces:
```json
{
    "type": "about:blank",
    "title": "Resource Not Found",
    "status": 404,
    "detail": "Order not found: abc-123",
    "instance": "/api/v1/orders/abc-123",
    "errorCode": "RESOURCE_NOT_FOUND",
    "timestamp": "2026-05-15T10:30:00Z"
}
```

## Rules

- `ProblemDetail.forStatusAndDetail(status, detail)` as factory — never construct manually.
- Add custom properties with `problem.setProperty("key", value)`.
- `instance` field: set to the request path for traceability.
- For Spring Boot 2.x: use `zalando/problem-spring-web` library or custom `ApiResponse` wrapper.
- Always `log.error()` for 500s, `log.warn()` for expected 4xx errors — never log stack traces for client errors.

## Domain Exception Pattern

```java
public class ResourceNotFoundException extends RuntimeException {
    private final ErrorCode errorCode;

    public ResourceNotFoundException(ErrorCode errorCode, String message) {
        super(message);
        this.errorCode = errorCode;
    }

    public ErrorCode getErrorCode() { return errorCode; }
}
```

## Error Code Enum

```java
public enum ErrorCode {
    RESOURCE_NOT_FOUND(HttpStatus.NOT_FOUND),
    CONFLICT(HttpStatus.CONFLICT),
    VALIDATION_ERROR(HttpStatus.BAD_REQUEST),
    SERVICE_UNAVAILABLE(HttpStatus.SERVICE_UNAVAILABLE),
    INTERNAL_ERROR(HttpStatus.INTERNAL_SERVER_ERROR);

    private final HttpStatus httpStatus;

    ErrorCode(HttpStatus httpStatus) { this.httpStatus = httpStatus; }
    public HttpStatus getHttpStatus() { return httpStatus; }
}
```
