---
name: devskillslearning-pipeline:secure
description: Harden Java/Spring Boot application security. Use when the user asks to add authentication, set up OAuth2/JWT, configure Keycloak, add method-level security, harden CORS, set up API keys, add rate limiting, or implement audit logging. Detects existing security config and fills gaps.
type: skill
---

# Secure

You are a Spring Security expert hardening a Java/Spring Boot application. Your goal: add defense-in-depth without breaking existing functionality.

## Step 0: Discover Current Security State

1. Read `CLAUDE.md` for project conventions
2. Check for existing `SecurityFilterChain` / `SecurityWebFilterChain` bean
3. Check for `spring-security` dependency in build file
4. Check `application.yml` for `spring.security.oauth2.resourceserver.*` config
5. Read existing security config class(es)
6. Determine auth type: None / Basic / JWT OAuth2 / Opaque Token / API Key / Session (form-login)

## Step 1: Determine Scope

Based on what the user asked for:

| Request | What to implement |
|---------|-------------------|
| "Add OAuth2 JWT auth" | Resource server config, JWT decoder, scope mapping, SecurityFilterChain, application.yml |
| "Set up Keycloak" | Issuer URI + JWK Set URI config, Keycloak-specific converter, realm setup instructions |
| "Add method security" | `@EnableMethodSecurity`, `@PreAuthorize`/`@PostAuthorize`/`@PostFilter` on endpoints |
| "Harden CORS" | Explicit `CorsConfigurationSource` bean, locked-down origins/methods/headers |
| "Add API key auth" | `X-API-Key` filter, hashed key storage, key rotation strategy |
| "Add rate limiting" | Bucket4j filter or Resilience4j RateLimiter with `application.yml` config |
| "Add audit logging" | `@Auditable` annotation + `AuditAspect` for mutating operations |
| "Full security hardening" | All of the above — defense-in-depth |

## Step 2: Implement

### 2a. OAuth2 Resource Server (JWT)

**Build dependency (Maven):**
```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-oauth2-resource-server</artifactId>
</dependency>
```

**application.yml:**
```yaml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: ${JWT_ISSUER_URI:https://auth.example.com/realms/enterprise}
          jwk-set-uri: ${JWT_ISSUER_URI:https://auth.example.com/realms/enterprise}/protocol/openid-connect/certs
          audiences: api://default
```

**SecurityConfig (Spring Boot 3.x):**
```java
@Configuration
@EnableWebSecurity
@EnableMethodSecurity
@RequiredArgsConstructor
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        return http
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/actuator/health/**", "/actuator/info").permitAll()
                .requestMatchers("/api/v1/health").permitAll()
                .requestMatchers("/api/v1/**").authenticated()
            )
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt.jwtAuthenticationConverter(jwtAuthenticationConverter()))
            )
            .sessionManagement(session -> session.sessionCreationPolicy(STATELESS))
            .csrf(csrf -> csrf.disable())
            .cors(cors -> cors.configurationSource(corsConfigurationSource()))
            .exceptionHandling(ex -> ex
                .authenticationEntryPoint((request, response, authException) -> {
                    response.setStatus(401);
                    response.setContentType("application/json");
                    response.getWriter().write("{\"success\":false,\"message\":\"Unauthorized\"}");
                })
                .accessDeniedHandler((request, response, accessDeniedException) -> {
                    response.setStatus(403);
                    response.setContentType("application/json");
                    response.getWriter().write("{\"success\":false,\"message\":\"Forbidden\"}");
                })
            )
            .build();
    }

    @Bean
    public JwtAuthenticationConverter jwtAuthenticationConverter() {
        var converter = new JwtAuthenticationConverter();
        converter.setJwtGrantedAuthoritiesConverter(jwt -> {
            var claims = jwt.getClaimAsStringList("scope");
            if (claims == null) claims = List.of();
            return claims.stream()
                .map(s -> new SimpleGrantedAuthority("SCOPE_" + s))
                .collect(Collectors.toCollection(ArrayList::new));
        });
        return converter;
    }
}
```

**For Spring Boot 2.x**: Replace `.oauth2ResourceServer(oauth2 -> oauth2.jwt(...))` with `.oauth2ResourceServer(OAuth2ResourceServerConfigurer::jwt)`. Replace `.csrf(csrf -> csrf.disable())` with `.csrf().disable()`.

### 2b. Keycloak Integration

Same as 2a, plus:

```yaml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: ${KEYCLOAK_URL:http://localhost:8080}/realms/${KEYCLOAK_REALM:my-realm}
```

For Keycloak's non-standard claim format (roles in `realm_access.roles`):
```java
converter.setJwtGrantedAuthoritiesConverter(jwt -> {
    var realmAccess = (Map<String, Object>) jwt.getClaims().get("realm_access");
    if (realmAccess == null) return Set.of();
    var roles = (List<String>) realmAccess.get("roles");
    return roles.stream()
        .map(r -> new SimpleGrantedAuthority("ROLE_" + r))
        .collect(Collectors.toSet());
});
```

Test with Testcontainers Keycloak:
```java
@Container
static KeycloakContainer keycloak = new KeycloakContainer("quay.io/keycloak/keycloak:24.0")
    .withRealmImportFile("test-realm.json");
```

### 2c. Method-Level Security

Enable in SecurityConfig: `@EnableMethodSecurity`

```java
// Ownership check — only the resource owner or admin can access
@PreAuthorize("hasAuthority('SCOPE_admin') or @resourceSecurity.isOwner(#id, authentication)")
@GetMapping("/{id}")
public ResponseEntity<ApiResponse<OrderResponse>> getOrder(@PathVariable UUID id) { ... }

// Ensure user only creates for themselves
@PreAuthorize("#request.customerId.toString() == authentication.principal.claims['sub']")
@PostMapping
public ResponseEntity<...> createOrder(@Valid @RequestBody CreateOrderRequest request) { ... }

// Filter results to only user's own data
@PostFilter("filterObject.customerId.toString() == authentication.principal.claims['sub']")
@GetMapping
public List<OrderResponse> listOrders() { ... }

// Role hierarchy
@PreAuthorize("hasAnyAuthority('SCOPE_admin', 'SCOPE_operator')")
@DeleteMapping("/{id}")
public ResponseEntity<Void> deleteOrder(@PathVariable UUID id) { ... }
```

**ResourceSecurity helper bean:**
```java
@Component("resourceSecurity")
public class ResourceSecurity {
    private final OrderRepository repository;

    public boolean isOwner(UUID resourceId, Authentication auth) {
        return repository.findById(resourceId)
            .map(o -> o.getCustomerId().toString().equals(auth.getName()))
            .orElse(false);
    }
}
```

### 2d. API Key Auth (Machine-to-Machine)

```java
@Component
@RequiredArgsConstructor
public class ApiKeyAuthFilter extends OncePerRequestFilter {
    private final ApiKeyService apiKeyService;

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                     FilterChain chain) throws ServletException, IOException {
        var apiKey = request.getHeader("X-API-Key");
        if (apiKey != null) {
            var validation = apiKeyService.validate(apiKey);
            if (validation.isValid()) {
                var auth = new PreAuthenticatedAuthenticationToken(
                    "service:" + validation.serviceName(), apiKey, validation.authorities());
                SecurityContextHolder.getContext().setAuthentication(auth);
            }
        }
        chain.doFilter(request, response);
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return request.getHeader("X-API-Key") == null;
    }
}
```

**ApiKeyService for validation:**
```java
@Service
public class ApiKeyService {
    // Store hash(apiKey) → {serviceName, scopes} in DB
    // Validate apiKey by hashing it and looking up the hash
    // Rotate: generate new key, update stored hash, notify consumer
}
```

Register filter before `SecurityFilterChain`:
```java
http.addFilterBefore(apiKeyAuthFilter, UsernamePasswordAuthenticationFilter.class);
```

### 2e. Rate Limiting (Bucket4j in Filter)

```java
@Component
public class RateLimitFilter extends OncePerRequestFilter {
    private final Map<String, Bucket> buckets = new ConcurrentHashMap<>();

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                     FilterChain chain) throws ServletException, IOException {
        var clientId = request.getHeader("X-API-Key") != null
            ? request.getHeader("X-API-Key")
            : SecurityContextHolder.getContext().getAuthentication().getName();
        var bucket = buckets.computeIfAbsent(clientId, this::newBucket);

        if (bucket.tryConsume(1)) {
            chain.doFilter(request, response);
        } else {
            response.setStatus(429);
            response.addHeader("Retry-After", "60");
            response.getWriter().write("{\"success\":false,\"errorCode\":\"RATE_LIMITED\",\"message\":\"Too many requests\"}");
        }
    }

    private Bucket newBucket(String key) {
        var limit = Bandwidth.classic(100, Refill.greedy(100, Duration.ofMinutes(1)));
        return Bucket.builder().addLimit(limit).build();
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return request.getRequestURI().startsWith("/actuator");
    }
}
```

Alternatively, use Resilience4j RateLimiter with Spring Cloud Gateway for API-gateway-level rate limiting.

### 2f. CORS Hardening

```java
@Bean
public CorsConfigurationSource corsConfigurationSource() {
    var config = new CorsConfiguration();
    config.setAllowedOrigins(List.of(
        "https://app.example.com",
        "https://admin.example.com"
    ));
    config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "OPTIONS"));
    config.setAllowedHeaders(List.of("Authorization", "Content-Type", "Idempotency-Key", "X-API-Key"));
    config.setExposedHeaders(List.of("Location", "Idempotency-Replayed", "Retry-After"));
    config.setAllowCredentials(true);
    config.setMaxAge(3600L);
    var source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/api/**", config);
    return source;
}
```

### 2g. Audit Logging

Create annotation, aspect, and register it:

```java
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface Auditable {
    String action();   // "CREATE", "UPDATE", "DELETE", "LOGIN"
    String target();   // "order", "account", "payment"
}

@Aspect
@Component
@Slf4j
public class AuditAspect {

    @Around("@annotation(auditable)")
    public Object audit(ProceedingJoinPoint jp, Auditable auditable) throws Throwable {
        var auth = SecurityContextHolder.getContext().getAuthentication();
        var who = auth != null ? auth.getName() : "anonymous";
        var start = Instant.now();
        try {
            var result = jp.proceed();
            log.info("AUDIT: who={} action={} target={} status=SUCCESS durationMs={}",
                who, auditable.action(), auditable.target(),
                Duration.between(start, Instant.now()).toMillis());
            return result;
        } catch (Exception e) {
            log.warn("AUDIT: who={} action={} target={} status=FAILURE reason={}",
                who, auditable.action(), auditable.target(), e.getClass().getSimpleName());
            throw e;
        }
    }
}
```

Apply on service methods:
```java
@Auditable(action = "CREATE", target = "order")
public OrderResponse createOrder(CreateOrderRequest request) { ... }
```

### 2h. Security Headers

Add to SecurityFilterChain:
```java
http.headers(headers -> headers
    .contentSecurityPolicy(csp -> csp.policyDirectives("default-src 'self'"))
    .frameOptions(frame -> frame.deny())
    .xssProtection(xss -> xss.headerValue(XXssProtectionHeaderWriter.HeaderValue.ENABLED_MODE_BLOCK))
    .contentTypeOptions(Customizer.withDefaults())
    .httpStrictTransportSecurity(hsts -> hsts
        .maxAgeInSeconds(31536000).includeSubDomains(true))
);
```

## Step 3: Update Tests

After adding security, update existing tests:

```java
// Controller tests — add mock user
@WebMvcTest(OrderController.class)
@Import(SecurityConfig.class)
class OrderControllerTest {
    @Autowired private MockMvc mockMvc;
    @MockBean private OrderService service;

    @Test
    @WithMockUser(authorities = "SCOPE_read")
    void shouldReturnOrder() throws Exception { ... }

    @Test
    @WithMockUser(authorities = "SCOPE_write")
    void shouldCreateOrder() throws Exception { ... }

    @Test
    void shouldReturn401WithoutAuth() throws Exception {
        mockMvc.perform(get("/api/v1/orders/{id}", UUID.randomUUID()))
            .andExpect(status().isUnauthorized());
    }

    @Test
    @WithMockUser(authorities = "SCOPE_read")
    void shouldReturn403OnInsufficientScope() throws Exception {
        mockMvc.perform(post("/api/v1/orders")...)
            .andExpect(status().isForbidden());
    }
}
```

### Integration test security
```java
@SpringBootTest(webEnvironment = RANDOM_PORT)
class SecureIntegrationTest {
    @Autowired private TestRestTemplate restTemplate;

    @Test
    void shouldAccessWithValidToken() {
        var headers = new HttpHeaders();
        headers.setBearerAuth(validJwtToken());
        var response = restTemplate.exchange("/api/v1/orders/{id}", GET,
            new HttpEntity<>(headers), ApiResponse.class, orderId);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }
}
```

## Step 4: Verify

```sh
# Run tests
mvn test -pl :module-name

# Verify security config loads
mvn spring-boot:run -Dspring-boot.run.profiles=dev
# Hit health endpoint → 200
# Hit protected endpoint without token → 401
# Hit protected endpoint with valid token → 200
```

## Checklist

- [ ] `spring-boot-starter-oauth2-resource-server` dependency added
- [ ] `SecurityFilterChain` bean defined (not `SecurityWebFilterChain` for reactive)
- [ ] `@EnableMethodSecurity` on config class
- [ ] JWT issuer URI and JWK Set URI configured
- [ ] Scope/role mapping correctly implemented in `JwtAuthenticationConverter`
- [ ] Stateless session management
- [ ] CSRF disabled (stateless APIs) or enabled (session-based)
- [ ] CORS locked down to explicit origins
- [ ] Rate limiting filter configured with reasonable thresholds
- [ ] Audit logging on mutating operations
- [ ] 401/403 error responses in standard format
- [ ] Security headers: CSP, HSTS, X-Frame-Options, X-Content-Type-Options
- [ ] Tests updated: auth success, 401, 403 test cases
- [ ] No secrets in code
- [ ] HTTPS enforced in production
