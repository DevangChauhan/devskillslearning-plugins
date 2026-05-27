# Security Patterns

## Data Protection

- No credentials or secrets in code or config files. Use Vault, K8s Secrets, or encrypted config.
- Input validation on all request bodies (`@NotNull`, `@Valid`, `@Size`, etc.).
- No raw SQL (use JPQL, Criteria API, or named queries).
- No user input in log messages without sanitization — never log request bodies, tokens, PII.
- `@JsonIgnore` on sensitive entity fields (passwords, tokens, SSN, credit card numbers).

## OAuth2 Resource Server (JWT)

Standard pattern for securing REST APIs:

```java
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        return http
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/actuator/health/**", "/api/v1/health").permitAll()
                .requestMatchers(HttpMethod.GET, "/api/v1/**").hasAuthority("SCOPE_read")
                .requestMatchers(HttpMethod.POST, "/api/v1/**").hasAuthority("SCOPE_write")
                .requestMatchers(HttpMethod.PUT, "/api/v1/**").hasAuthority("SCOPE_write")
                .requestMatchers(HttpMethod.DELETE, "/api/v1/**").hasAuthority("SCOPE_admin")
                .anyRequest().authenticated()
            )
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt.jwtAuthenticationConverter(jwtAuthenticationConverter()))
            )
            .sessionManagement(session -> session.sessionCreationPolicy(STATELESS))
            .csrf(csrf -> csrf.disable())
            .cors(cors -> cors.configurationSource(corsConfigurationSource()))
            .build();
    }
}
```

**Spring Boot 2.x**: Replace `oauth2ResourceServer(oauth2 -> oauth2.jwt(...))` with `oauth2ResourceServer(OAuth2ResourceServerConfigurer::jwt)`. Replace Lambda DSL `csrf(csrf -> csrf.disable())` with `csrf().disable()`.

Rules:
- Stateless (no `HttpSession`) for REST APIs — tokens carry all context.
- Validate `iss`, `aud`, and `exp` via `spring.security.oauth2.resourceserver.jwt.*` properties.
- `permitAll()` only for health endpoints and public endpoints — everything else authenticated by default.
- Never accept tokens without signature verification.
- Use HTTPS everywhere — enforce via redirect or HSTS.

## Method-Level Security

```java
@PreAuthorize("hasAuthority('SCOPE_write')")
@PostMapping
public ResponseEntity<...> createOrder(@Valid @RequestBody CreateOrderRequest request) { ... }

@PreAuthorize("hasAuthority('SCOPE_admin') or @orderSecurity.isOwner(#id, authentication)")
@GetMapping("/{id}")
public ResponseEntity<...> getOrder(@PathVariable UUID id) { ... }

@PostFilter("filterObject.customerId == authentication.principal.claims['sub']")
@GetMapping
public List<OrderResponse> listOrders() { ... }
```

- `@PreAuthorize` on mutating endpoints and endpoints returning sensitive data.
- `@PostFilter` for filtering collection results to only authorized records.
- Complex rules extracted to `@Component` beans (SpEL delegates).
- `@EnableMethodSecurity` on config class.

## CORS

```java
@Bean
public CorsConfigurationSource corsConfigurationSource() {
    var config = new CorsConfiguration();
    config.setAllowedOrigins(List.of("https://app.example.com"));  // explicit, never "*"
    config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE"));
    config.setAllowedHeaders(List.of("Authorization", "Content-Type", "Idempotency-Key"));
    config.setAllowCredentials(true);
    config.setMaxAge(3600L);
    var source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/api/**", config);
    return source;
}
```

Rules:
- Never `allowedOrigins("*")` with `allowCredentials(true)` — browsers reject it.
- List allowed origins explicitly.
- Only expose headers clients actually need.

## CSRF

- Stateless REST APIs: disable CSRF (tokens replace cookies for auth).
- Session-based (MVC + Thymeleaf): keep CSRF enabled.
- Cookies use `SameSite=Strict` or `SameSite=Lax`.

## Rate Limiting

- Rate limit filter or interceptor on public/mutating endpoints.
- Thresholds configurable via `@ConfigurationProperties` (not hardcoded).
- `Retry-After` header on 429 responses.
- Rate limit endpoint excluded from actuator health checks.

## Audit Logging

- Audited: who (user/service), what (action), what-on (resource), when (timestamp), result (success/failure).
- Mutating operations (create, update, delete) and auth events (login, logout, token refresh).
- Log at INFO with `AUDIT:` prefix for filtering.
- Never log tokens, passwords, or full request bodies in audit.
