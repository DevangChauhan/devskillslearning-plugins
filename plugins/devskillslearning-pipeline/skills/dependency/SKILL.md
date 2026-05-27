---
name: devskillslearning-pipeline:dependency
description: Manage project dependencies and security vulnerabilities for Java/Spring Boot projects. Use when the user asks to scan for CVEs, audit dependencies, set up OWASP dependency-check, configure Gradle version catalogs or Maven BOMs, resolve transitive conflicts, set up Renovate or Dependabot, or upgrade dependency versions.
type: skill
---

# Dependency

You are a dependency management and supply chain security expert for a Java/Spring Boot project. Your goal: keep dependencies up-to-date, secure, and conflict-free.

## What You Need to Provide

| Input | Required? | Example | Notes |
|-------|-----------|---------|-------|
| What to do | Yes | "Scan for vulnerabilities" | The action |
| Dependency concern | Recommended | "Spring Framework has CVE-2025-XXXXX — is our version affected?" | Specific CVE or package |
| Upgrade policy | No | "Patch only / minor allowed / no restrictions" | Drives Renovate/Dependabot config |
| Dependency management style | No | Version catalog / BOM / direct | I'll detect from build files |

**Examples**:
- "Scan the project for known vulnerabilities"
- "Set up OWASP dependency-check in the CI pipeline"
- "Resolve the Guava version conflict between modules"
- "Are we affected by CVE-2025-XXXXX in Spring?"
- "Set up Renovate for automated dependency updates"
- "Create a Maven BOM for shared dependency versions across microservices"

**I auto-discover**: Build system, dependency management style, current versions, existing vulnerability scanning config, CI pipeline config.

## Step 0: Discover Dependency State

Follow `docs/shared/step0-discovery.md` to detect build system, Spring Boot version, architecture type, package layout, and all project conventions.

## Step 1: Determine Scope

| Request | What to implement |
|---------|-------------------|
| "Scan for vulnerabilities" | OWASP dependency-check setup + report analysis |
| "Audit dependencies" | Full dependency tree analysis, stale deps, conflicts |
| "Resolve conflict" | Transitive dependency conflict resolution |
| "Set up auto-updates" | Renovate or Dependabot config |
| "Create version catalog / BOM" | Gradle version catalog or Maven BOM for multi-module/multi-service |
| "Upgrade dependency" | Single dependency upgrade with compatibility check |
| "Full dependency hardening" | Scan + version catalog + auto-update config + CI enforcement |

## Step 2: Implement

### 2a. OWASP Dependency-Check

**Maven plugin:**
```xml
<plugin>
    <groupId>org.owasp</groupId>
    <artifactId>dependency-check-maven</artifactId>
    <version>10.0.4</version>
    <configuration>
        <!-- Fail the build on CVSS score >= 7.0 (HIGH and CRITICAL) -->
        <failBuildOnCVSS>7</failBuildOnCVSS>
        <formats>
            <format>HTML</format>
            <format>JSON</format>
        </formats>
        <!-- Suppress false positives -->
        <suppressionFiles>
            <suppressionFile>owasp-suppressions.xml</suppressionFile>
        </suppressionFiles>
        <!-- Exclude test dependencies -->
        <skipTestScope>true</skipTestScope>
        <!-- NVD API key (get one at https://nvd.nist.gov/developers/request-an-api-key) -->
        <nvdApiKey>${env.NVD_API_KEY}</nvdApiKey>
    </configuration>
    <executions>
        <execution>
            <goals>
                <goal>check</goal>
            </goals>
        </execution>
    </executions>
</plugin>
```

**Run:**
```sh
mvn dependency-check:check -pl :module-name
# Report at: target/dependency-check-report.html
```

**Gradle plugin:**
```kotlin
// build.gradle.kts
plugins {
    id("org.owasp.dependencycheck") version "10.0.4"
}

dependencyCheck {
    failBuildOnCVSS = 7.0f
    formats = listOf("HTML", "JSON")
    suppressionFile = "owasp-suppressions.xml"
    skipTestScope = true
    nvd.apiKey = System.getenv("NVD_API_KEY") ?: ""
}
```

```sh
./gradlew dependencyCheckAnalyze
# Report at: build/reports/dependency-check-report.html
```

### 2b. False Positive Suppression

When a reported CVE is a false positive (doesn't apply to how you use the library):

**`owasp-suppressions.xml`:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<suppressions xmlns="https://jeremylong.github.io/DependencyCheck/dependency-suppression.1.3.xsd">
    <suppress>
        <notes><![CDATA[
            CVE-2025-XXXXX: Spring Framework RCE via DataBinder.
            We don't use DataBinder with untrusted input — all bindings are internal.
            Reviewed by security team on 2026-05-19.
        ]]></notes>
        <cve>CVE-2025-XXXXX</cve>
    </suppress>
    <suppress>
        <notes><![CDATA[
            CVE-2025-YYYYY: SnakeYAML deserialization.
            We use SnakeYAML only to parse our own application.yml at startup,
            never with user-provided YAML.
            Reviewed by security team on 2026-05-19.
        ]]></notes>
        <cve>CVE-2025-YYYYY</cve>
    </suppress>
</suppressions>
```

**Rules for suppressions:**
- Every suppression must explain WHY it's a false positive for YOUR usage
- Include a review date and reviewer
- Review suppressions quarterly — the library usage may have changed
- Prefer upgrading the dependency over suppressing the CVE

### 2c. Dependency Audit — Find Problems

```sh
# Maven: dependency tree with conflicts
mvn dependency:tree -Dverbose -Dincludes=com.google.guava:guava

# Maven: check for dependency convergence (same version across transitive deps)
mvn enforcer:enforce

# Maven: find unused dependencies
mvn org.apache.maven.plugins:maven-dependency-plugin:3.7.0:analyze

# Gradle: dependency tree
./gradlew dependencies --configuration compileClasspath

# Gradle: check for dependency updates
./gradlew dependencyUpdates

# Gradle: find unused dependencies
./gradlew buildHealth
```

**Common issues to flag:**

| Issue | Detection | Fix |
|-------|-----------|-----|
| Multiple versions of same library | `dependency:tree -Dverbose` — look for "omitted for conflict" | Add `<dependencyManagement>` or version catalog entry |
| Unused declared dependency | `dependency:analyze` — "used undeclared" or "unused declared" | Remove unused, add missing to dependency management |
| Direct dependency on a transitive dep | `dependency:tree` — project directly declares what a framework brings | Remove direct declaration, rely on managed version |
| Overriding Spring Boot managed version | Version differs from `spring-boot-starter-parent` BOM | Use `spring-boot-starter-parent` version unless explicitly needed |
| SNAPSHOT in release build | `dependency:tree | grep SNAPSHOT` | Lock to a release version |

### 2d. Resolve Transitive Version Conflicts

**Problem:**
```
com.google.guava:guava
  ├── module-a requires 33.0.0-jre
  └── module-b requires 32.1.2-jre  ← conflict, Maven picks nearest
```

**Maven fix — add to `<dependencyManagement>`:**
```xml
<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>com.google.guava</groupId>
            <artifactId>guava</artifactId>
            <version>33.0.0-jre</version>
        </dependency>
    </dependencies>
</dependencyManagement>
```

**Gradle fix — add constraint in version catalog or `build.gradle.kts`:**
```kotlin
configurations.all {
    resolutionStrategy {
        force("com.google.guava:guava:33.0.0-jre")
    }
    // Better: fail on conflict so they're explicit
    // failOnVersionConflict()
}
```

**Best approach: use `maven-enforcer-plugin` to fail on conflicts:**
```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-enforcer-plugin</artifactId>
    <version>3.4.1</version>
    <executions>
        <execution>
            <id>enforce-dependency-convergence</id>
            <goals><goal>enforce</goal></goals>
            <configuration>
                <rules>
                    <dependencyConvergence/>
                    <requireUpperBoundDeps/>
                    <banDuplicatePomDependencyVersions/>
                </rules>
            </configuration>
        </execution>
    </executions>
</plugin>
```

### 2e. Maven BOM (Bill of Materials)

For multi-service organizations, create a shared BOM to centralize version management:

```xml
<!-- shared-bom/pom.xml -->
<project>
    <groupId>com.acme</groupId>
    <artifactId>acme-dependencies</artifactId>
    <version>2025.05.0</version>
    <packaging>pom</packaging>

    <properties>
        <spring-boot.version>3.3.0</spring-boot.version>
        <spring-cloud.version>2023.0.2</spring-cloud.version>
        <guava.version>33.0.0-jre</guava.version>
        <mapstruct.version>1.5.5.Final</mapstruct.version>
        <testcontainers.version>1.19.8</testcontainers.version>
        <resilience4j.version>2.2.0</resilience4j.version>
    </properties>

    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-dependencies</artifactId>
                <version>${spring-boot.version}</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
            <dependency>
                <groupId>org.springframework.cloud</groupId>
                <artifactId>spring-cloud-dependencies</artifactId>
                <version>${spring-cloud.version}</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
            <dependency>
                <groupId>com.google.guava</groupId>
                <artifactId>guava</artifactId>
                <version>${guava.version}</version>
            </dependency>
            <!-- ... all shared dependencies -->
        </dependencies>
    </dependencyManagement>
</project>
```

**Consume in services:**
```xml
<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>com.acme</groupId>
            <artifactId>acme-dependencies</artifactId>
            <version>2025.05.0</version>
            <type>pom</type>
            <scope>import</scope>
        </dependency>
    </dependencies>
</dependencyManagement>
```

### 2f. Gradle Version Catalog

**`gradle/libs.versions.toml`** (Gradle 7.4+):
```toml
[versions]
spring-boot = "3.3.0"
spring-cloud = "2023.0.2"
spring-dependency-management = "1.1.5"
guava = "33.0.0-jre"
mapstruct = "1.5.5.Final"
testcontainers = "1.19.8"
resilience4j = "2.2.0"
kotlin = "1.9.24"

[libraries]
spring-boot-starter-web = { module = "org.springframework.boot:spring-boot-starter-web" }
spring-boot-starter-data-jpa = { module = "org.springframework.boot:spring-boot-starter-data-jpa" }
spring-boot-starter-validation = { module = "org.springframework.boot:spring-boot-starter-validation" }
spring-boot-starter-actuator = { module = "org.springframework.boot:spring-boot-starter-actuator" }
spring-boot-starter-test = { module = "org.springframework.boot:spring-boot-starter-test" }
mapstruct = { module = "org.mapstruct:mapstruct", version.ref = "mapstruct" }
mapstruct-processor = { module = "org.mapstruct:mapstruct-processor", version.ref = "mapstruct" }
guava = { module = "com.google.guava:guava", version.ref = "guava" }
resilience4j-circuitbreaker = { module = "io.github.resilience4j:resilience4j-circuitbreaker", version.ref = "resilience4j" }
resilience4j-retry = { module = "io.github.resilience4j:resilience4j-retry", version.ref = "resilience4j" }
testcontainers-postgresql = { module = "org.testcontainers:postgresql", version.ref = "testcontainers" }
testcontainers-kafka = { module = "org.testcontainers:kafka", version.ref = "testcontainers" }

[bundles]
testcontainers = ["testcontainers-postgresql", "testcontainers-kafka"]
resilience4j = ["resilience4j-circuitbreaker", "resilience4j-retry"]

[plugins]
spring-boot = { id = "org.springframework.boot", version.ref = "spring-boot" }
spring-dependency-management = { id = "io.spring.dependency-management", version.ref = "spring-dependency-management" }
kotlin-jvm = { id = "org.jetbrains.kotlin.jvm", version.ref = "kotlin" }
```

**Consume in `build.gradle.kts`:**
```kotlin
dependencies {
    implementation(libs.spring.boot.starter.web)
    implementation(libs.guava)
    implementation(libs.bundles.resilience4j)
    testImplementation(libs.bundles.testcontainers)
}
```

### 2g. Renovate Configuration

**`.github/renovate.json`:**
```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:recommended",
    ":separateMajorMinor",
    ":combinePatchMinorUpdates"
  ],
  "labels": ["dependencies"],
  "packageRules": [
    {
      "matchPackagePatterns": ["^org\\.springframework"],
      "groupName": "Spring Framework",
      "automerge": false
    },
    {
      "matchPackagePatterns": ["^org\\.springframework\\.boot"],
      "groupName": "Spring Boot",
      "automerge": false
    },
    {
      "matchUpdateTypes": ["patch"],
      "matchCurrentVersion": "!/^0/",
      "automerge": true,
      "automergeType": "pr",
      "platformAutomerge": true
    },
    {
      "matchUpdateTypes": ["minor"],
      "matchCurrentVersion": "!/^0/",
      "automerge": false,
      "addLabels": ["needs-review"]
    },
    {
      "matchUpdateTypes": ["major"],
      "addLabels": ["major-upgrade", "needs-review"],
      "dependencyDashboardApproval": true
    },
    {
      "matchManagers": ["maven", "gradle"],
      "matchPackageNames": ["com.google.guava:guava"],
      "allowedVersions": "!/jre$/"
    }
  ],
  "vulnerabilityAlerts": {
    "labels": ["security"],
    "automerge": true
  },
  "prHourlyLimit": 5,
  "prConcurrentLimit": 10,
  "schedule": ["before 9am on Monday"]
}
```

### 2h. Dependabot Configuration

**`.github/dependabot.yml`:**
```yaml
version: 2
updates:
  - package-ecosystem: maven
    directory: /
    schedule:
      interval: weekly
      day: monday
      time: "09:00"
      timezone: America/Chicago
    labels:
      - dependencies
    open-pull-requests-limit: 10
    reviewers:
      - devangchauhan
    groups:
      spring:
        patterns:
          - "org.springframework*"
          - "org.springframework.boot*"
        update-types:
          - minor
          - patch
      test-deps:
        patterns:
          - "org.testcontainers*"
          - "org.junit*"
          - "org.mockito*"
        update-types:
          - minor
          - patch

  - package-ecosystem: docker
    directory: /
    schedule:
      interval: weekly
```

### 2i. Dependency Upgrade — Single Library

When upgrading a specific dependency, check:

```sh
# 1. Check current version
mvn dependency:tree -Dincludes=com.google.guava:guava

# 2. Check available versions
mvn versions:display-dependency-updates -Dincludes=com.google.guava:guava

# 3. Check for breaking changes (compare changelogs)
# Open: https://github.com/google/guava/releases

# 4. Check downstream compatibility (what else uses it?)
mvn dependency:tree -Dverbose -Dincludes=com.google.guava:guava

# 5. Update in dependency management (if BOM/version catalog)
# or update directly in pom.xml

# 6. Build and test
mvn clean verify

# 7. Check for deprecation warnings in build output
```

**Spring Boot version upgrade checklist:**
- [ ] Check release notes for breaking changes
- [ ] Check deprecated APIs removed in this version
- [ ] Update `spring-boot-starter-parent` version (Maven) or plugin version (Gradle)
- [ ] Check Spring Cloud compatibility matrix if using Spring Cloud
- [ ] Check javax→jakarta implications (if going 2.x→3.x)
- [ ] Run `mvn clean verify` — check all tests pass
- [ ] Check config properties: `spring-boot-properties-migrator` helps
- [ ] Check security config — `SecurityFilterChain` DSL may have changed

### 2j. CI Pipeline Integration

**GitHub Actions — OWASP scan on PR:**
```yaml
# .github/workflows/security-scan.yml
name: Dependency Security Scan

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 7 * * 1'  # Every Monday at 7am

jobs:
  owasp-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { java-version: 21, distribution: temurin }
      - name: OWASP Dependency Check
        run: mvn dependency-check:check -pl :service-name
        env:
          NVD_API_KEY: ${{ secrets.NVD_API_KEY }}
      - name: Upload report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: dependency-check-report
          path: target/dependency-check-report.html

  snyk:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Snyk scan
        uses: snyk/actions/maven@master
        env:
          SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
        with:
          args: --severity-threshold=high
```

## Step 3: Verify

```sh
# Run dependency-check
mvn dependency-check:check -pl :module-name

# Check the report
open target/dependency-check-report.html
# or: cat target/dependency-check-report.json | jq '.dependencies[] | select(.vulnerabilities != null) | { name: .fileName, vulns: .vulnerabilities }'

# List all dependencies and their versions
mvn dependency:tree > dependency-tree.txt

# Check for stale dependencies
mvn versions:display-dependency-updates

# Check Maven enforcer
mvn validate  # enforcer runs in validate phase

# Gradle: list outdated
./gradlew dependencyUpdates
```

## Checklist

- [ ] OWASP dependency-check plugin configured (Maven or Gradle)
- [ ] `failBuildOnCVSS` set to 7.0 (fail on HIGH and CRITICAL)
- [ ] NVD API key configured (prevents rate limiting)
- [ ] False positive suppressions documented with justification and review date
- [ ] `maven-enforcer-plugin` with `dependencyConvergence` rule (Maven)
- [ ] No SNAPSHOT dependencies in build files (unless in dev profile)
- [ ] Dependency convergence: no version conflicts in multi-module
- [ ] No unused declared dependencies (or kept intentionally with comment)
- [ ] Gradle version catalog (`libs.versions.toml`) or Maven BOM for shared versions
- [ ] Spring Boot parent/BOM version explicit and consistent across modules
- [ ] Renovate or Dependabot configured for automated updates
- [ ] Patch updates auto-merged, minor updates auto-PR, major updates require approval
- [ ] Vulnerability alerts labeled `security` and auto-PR'd
- [ ] CI pipeline runs dependency scan on PRs and scheduled weekly
- [ ] Dependency scan report archived as build artifact
- [ ] Known CVEs with HIGH/CRITICAL score addressed (upgraded or suppressed)
- [ ] Spring Boot + Spring Cloud versions compatible (check compatibility matrix)

## Next Step
After securing dependencies, use `/devskillslearning-pipeline:release` to cut a release with the updated dependency versions documented in the changelog.
