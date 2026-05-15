---
name: devskillslearning-pipeline:deploy
description: Generate deployment artifacts for Java/Spring Boot applications. Use when the user asks to set up deployment, create Kubernetes manifests, generate CI/CD pipeline, write a Helm chart, or containerize an application. Detects project structure and generates appropriate artifacts.
type: skill
---

# Deploy

You are a DevOps engineer specializing in Java/Spring Boot deployment. Generate production-ready deployment artifacts that follow cloud-native best practices.

## What You Need to Provide

| Input | Required? | Example | Notes |
|-------|-----------|---------|-------|
| Deployment target | Yes | Kubernetes / Docker Compose / Cloud Foundry | I auto-detect if K8s manifests exist |
| Artifact types | Recommended | "Dockerfile + K8s manifests + CI/CD" | Or just "full deploy setup" |
| Container registry | For CI/CD | `ghcr.io/myorg` | Where to push images |
| Environment specifics | Recommended | "We use GKE with cert-manager and external-secrets-operator" | Helps me tailor manifests |
| Service port / health paths | No | I read application.yml | Auto-discovered |

**Examples**:
- "Generate a Dockerfile and K8s manifests for the order service"
- "Set up a GitHub Actions CI/CD pipeline that builds, tests, and deploys to staging"
- "Create a Helm chart for the payment service with dev/staging/prod values"
- "Containerize all 3 services and generate a docker-compose for local dev"

**I auto-discover**: Build system, Java version (for base image), server port, health endpoints, existing deployment config.

## Step 0: Discover the Project

1. Read `CLAUDE.md` for project conventions
2. Detect build system (Maven/Gradle) and module structure
3. Detect Spring Boot version (for Java base image compatibility)
4. Check for existing Dockerfile, K8s manifests, CI config
5. Check `application.yml` for server port, health endpoints, datasource config
6. Determine target environment: K8s / Docker Compose / Cloud Foundry / Bare metal

## Step 1: Determine Scope

Based on what the user asked for:

| Request | What to generate |
|---------|-----------------|
| "Containerize" / "Docker" | Dockerfile (multi-stage, distroless) + .dockerignore |
| "K8s" / "Kubernetes" | Deployment, Service, ConfigMap, Secret, Ingress, HPA, PDB |
| "CI/CD" / "Pipeline" | GitHub Actions workflow (build → test → scan → containerize → deploy) |
| "Helm" | Helm chart with values.yaml for dev/staging/prod |
| "Full deploy setup" | All of the above |

## Step 2: Generate Artifacts

### 2a. Dockerfile (Multi-Stage, Distroless)

```dockerfile
# Stage 1: Build
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /app
COPY pom.xml ./
# Or for Gradle: COPY build.gradle.kts settings.gradle.kts gradlew ./
# COPY gradle/ gradle/

# Cache dependencies
RUN ./mvnw dependency:go-offline -B
# Or: RUN ./gradlew dependencies --no-daemon

COPY src/ src/
RUN ./mvnw package -DskipTests -B
# Or: RUN ./gradlew bootJar --no-daemon

# Extract the layered jar for optimized Docker caching
RUN java -Djarmode=layertools -jar target/*.jar extract --destination target/extracted

# Stage 2: Runtime (distroless — minimal attack surface)
FROM gcr.io/distroless/java21-debian12:nonroot
WORKDIR /app
COPY --from=builder /app/target/extracted/dependencies/ ./
COPY --from=builder /app/target/extracted/spring-boot-loader/ ./
COPY --from=builder /app/target/extracted/snapshot-dependencies/ ./
COPY --from=builder /app/target/extracted/application/ ./

EXPOSE 8080
USER nonroot
ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]
```

**Alternative — Buildpacks (no Dockerfile needed):**
```sh
mvn spring-boot:build-image -Dspring-boot.build-image.imageName=registry.example.com/app:latest
# or
./gradlew bootBuildImage --imageName=registry.example.com/app:latest
```

**.dockerignore:**
```
target/
build/
.gradle/
.git/
.idea/
*.md
.env
*.log
```

### 2b. Kubernetes Manifests

**Deployment:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <service-name>
  labels:
    app: <service-name>
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: <service-name>
  template:
    metadata:
      labels:
        app: <service-name>
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/path: "/actuator/prometheus"
        prometheus.io/port: "8080"
    spec:
      terminationGracePeriodSeconds: 30
      serviceAccountName: <service-name>
      containers:
        - name: <service-name>
          image: registry.example.com/<service-name>:${VERSION}
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8080
              name: http
          env:
            - name: SERVER_PORT
              value: "8080"
            - name: JAVA_OPTS
              value: "-XX:+UseZGC -XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError"
            - name: SPRING_PROFILES_ACTIVE
              value: "prod"
          envFrom:
            - configMapRef:
                name: <service-name>-config
            - secretRef:
                name: <service-name>-secret
          resources:
            requests:
              cpu: "250m"
              memory: "512Mi"
            limits:
              cpu: "1000m"
              memory: "1Gi"
          startupProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            failureThreshold: 30
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            initialDelaySeconds: 0
            periodSeconds: 10
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 3
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "sleep 15"]  # grace period for draining
```

**application.yml — Kubernetes health probes:**
```yaml
management:
  endpoint:
    health:
      probes:
        enabled: true  # enable /actuator/health/liveness and /actuator/health/readiness
  server:
    port: 8081  # management on separate port (optional)

server:
  shutdown: graceful
spring:
  lifecycle:
    timeout-per-shutdown-phase: 20s
```

**Service:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: <service-name>
  labels:
    app: <service-name>
spec:
  type: ClusterIP
  ports:
    - port: 8080
      targetPort: http
      protocol: TCP
      name: http
  selector:
    app: <service-name>
```

**ConfigMap:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: <service-name>-config
data:
  SPRING_DATASOURCE_URL: "jdbc:postgresql://postgres:5432/<service-name>"
  LOGGING_LEVEL_COM_COMPANY: "INFO"
```

**Secret (reference only — use external secret manager):**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <service-name>-secret
type: Opaque
stringData:
  SPRING_DATASOURCE_USERNAME: "app-user"
  SPRING_DATASOURCE_PASSWORD: "<CHANGE-ME>"
  JWT_ISSUER_URI: "https://auth.example.com/realms/enterprise"
```

**HorizontalPodAutoscaler:**
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: <service-name>-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: <service-name>
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
```

**PodDisruptionBudget:**
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: <service-name>-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: <service-name>
```

**Ingress (optional):**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <service-name>-ingress
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - api.example.com
      secretName: api-tls
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /api/v1/<service-name>
            pathType: Prefix
            backend:
              service:
                name: <service-name>
                port:
                  number: 8080
```

### 2c. GitHub Actions CI/CD Pipeline

```yaml
name: Build and Deploy
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_DB: testdb
          POSTGRES_USER: testuser
          POSTGRES_PASSWORD: testpass
        ports:
          - 5432:5432
        options: --health-cmd pg_isready --health-interval 10s --health-timeout 5s --health-retries 5
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          java-version: '21'
          distribution: 'temurin'
          cache: 'maven'  # or 'gradle'

      - name: Build and test
        run: mvn clean verify -B
        # or: ./gradlew build --no-daemon
        env:
          SPRING_DATASOURCE_URL: jdbc:postgresql://localhost:5432/testdb
          SPRING_DATASOURCE_USERNAME: testuser
          SPRING_DATASOURCE_PASSWORD: testpass

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: '**/target/surefire-reports/*.xml'

      - name: Upload coverage
        if: success()
        uses: actions/upload-artifact@v4
        with:
          name: jacoco-report
          path: '**/target/site/jacoco/'

  security-scan:
    needs: build-and-test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run Trivy vulnerability scan
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'fs'
          scan-ref: '.'
          format: 'sarif'
          output: 'trivy-results.sarif'
      - name: Upload scan results
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: 'trivy-results.sarif'

  containerize:
    needs: build-and-test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          java-version: '21'
          distribution: 'temurin'
          cache: 'maven'

      - name: Build package
        run: mvn package -DskipTests -B

      - name: Log in to registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }},${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max

  deploy:
    needs: containerize
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4

      - name: Set up kubectl
        uses: azure/setup-kubectl@v3

      - name: Deploy to Kubernetes
        run: |
          kubectl set image deployment/<service-name> \
            <service-name>=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
          kubectl rollout status deployment/<service-name> --timeout=5m
          kubectl annotate deployment/<service-name> \
            kubernetes.io/change-cause="${{ github.event.head_commit.message }}"
```

### 2d. Helm Chart (optional)

```
helm/<service-name>/
├── Chart.yaml
├── values.yaml          # default values
├── values-dev.yaml      # dev overrides
├── values-staging.yaml  # staging overrides
├── values-prod.yaml     # prod overrides
└── templates/
    ├── deployment.yaml
    ├── service.yaml
    ├── configmap.yaml
    ├── secret.yaml      # (reference only — use external-secrets-operator)
    ├── hpa.yaml
    ├── pdb.yaml
    ├── ingress.yaml
    └── _helpers.tpl
```

**Chart.yaml:**
```yaml
apiVersion: v2
name: <service-name>
description: Helm chart for <service-name>
type: application
version: 0.1.0
appVersion: "1.0.0"
```

**values.yaml structure:**
```yaml
replicaCount: 2
image:
  repository: registry.example.com/<service-name>
  tag: latest
  pullPolicy: IfNotPresent

resources:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1Gi

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

config:
  springProfiles: prod
  datasourceUrl: jdbc:postgresql://postgres:5432/<service-name>
  loggingLevel: INFO

secrets:
  datasourceUsername: app-user
  datasourcePassword: CHANGEME

ingress:
  enabled: true
  host: api.example.com
  tls: true

serviceAccount:
  create: true
  name: <service-name>
```

## Step 3: Verify

```sh
# Validate Dockerfile
docker build -t <service-name>:test .

# Validate K8s manifests
kubectl apply --dry-run=client -f k8s/

# Validate Helm chart
helm lint helm/<service-name>/
helm template helm/<service-name/ --values helm/<service-name>/values-dev.yaml

# Test CI/CD (locally)
act push  # using nektos/act to test GitHub Actions locally
```

## Checklist

- [ ] Dockerfile uses multi-stage build with distroless base
- [ ] `.dockerignore` excludes build artifacts and secrets
- [ ] K8s: Deployment, Service, ConfigMap at minimum
- [ ] K8s: startup, liveness, and readiness probes configured
- [ ] K8s: resource requests AND limits set
- [ ] K8s: `securityContext` with nonroot user
- [ ] K8s: PodDisruptionBudget for HA
- [ ] K8s: HPA for auto-scaling
- [ ] K8s: graceful shutdown configured (`server.shutdown=graceful`)
- [ ] CI: build, test, security scan, containerize, deploy stages
- [ ] CI: Testcontainers or service containers for DB in CI
- [ ] CI: build cache (Maven/Gradle + Docker layer cache)
- [ ] CI: container pushed only on main branch
- [ ] Secrets referenced via K8s Secrets / external-secrets-operator / Vault — never committed
- [ ] JVM opts: `-XX:MaxRAMPercentage=75.0`, `-XX:+UseZGC` (Java 21+)
