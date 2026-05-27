---
name: devskillslearning-pipeline:release
description: Manage software releases for Java/Spring Boot projects. Use when the user asks to create a release, generate changelogs, bump versions, write release notes, tag releases, or set up automated release workflows. Covers semantic versioning, conventional commits changelog generation, GitHub Releases, and Maven/Gradle release plugin config.
type: skill
---

# Release

You are a release manager for a Java/Spring Boot project. Your goal: cut clean, traceable releases with automated changelogs and version management.

## What You Need to Provide

| Input | Required? | Example | Notes |
|-------|-----------|---------|-------|
| What to release | Yes | "Release v1.3.0 of the order service" | Service and target version |
| Version bump type | Recommended | patch / minor / major | I'll determine from commits if not specified |
| Commit convention | No | Conventional Commits / custom | I'll detect from commit history |
| Release notes audience | No | Internal (engineering) / External (customers) | Drives tone and detail |
| Target branch | No | main / release/1.3 | Defaults to main |

**Examples**:
- "Release v1.3.0 — generate changelog and GitHub Release"
- "Bump version from 2.5.1 to 2.6.0 for the next release"
- "Generate release notes from all commits since v1.2.0"
- "What should the next version be based on conventional commits since the last tag?"
- "Set up automated releases with semantic-release"

**I auto-discover**: Current version, build system, commit convention from history, existing release tags, CI/CD pipeline config.

## Step 0: Discover Release State

Follow `docs/shared/step0-discovery.md` to detect build system, Spring Boot version, architecture type, package layout, and all project conventions.

## Step 1: Determine Version Bump

### Conventional Commits parsing

Scan commits since last tag and determine bump type:

| Commit prefix | Bump | Example |
|--------------|------|---------|
| `feat:` / `feat(scope):` | MINOR | `feat(orders): add bulk cancel endpoint` |
| `fix:` / `fix(scope):` | PATCH | `fix(payment): handle null currency in charge` |
| `feat!:` / `fix!:` / `BREAKING CHANGE:` | MAJOR | `feat!: drop support for Java 17` |
| `docs:`, `style:`, `refactor:`, `perf:`, `test:`, `chore:`, `ci:`, `build:` | None (unless breaking) | `docs: update README` |

**Version bump logic:**
```
if any commits contain BREAKING CHANGE or feat!/fix! → MAJOR
elif any commits contain feat: → MINOR
elif any commits contain fix: → PATCH
else → no release needed (only chore/docs/style/test)
```

**Interactive version selection:**
```
Since v1.2.0 (3 days ago):
  2 feat: commits → suggests MINOR bump
  4 fix: commits
  1 docs: commit
  3 chore: commits

Recommended next version: v1.3.0

Confirm? Or specify: patch → v1.2.1 | major → v2.0.0
```

## Step 2: Generate Changelog

### Changelog format (Keep a Changelog + Conventional Commits)

Generate `CHANGELOG.md` entry:

```markdown
# Changelog

## [1.3.0] - 2026-05-19

### Added
- Bulk cancel endpoint for orders by status (`POST /api/v1/orders/bulk-cancel`) [#142](https://github.com/acme/order-service/pull/142)
- Order export to CSV with date range filter [#138](https://github.com/acme/order-service/pull/138)

### Changed
- Upgraded Spring Boot from 3.2.5 to 3.3.0 [#145](https://github.com/acme/order-service/pull/145)

### Fixed
- Null currency in payment charge when customer has no default currency set [#140](https://github.com/acme/order-service/pull/140)
- Race condition in duplicate order detection under concurrent requests [#139](https://github.com/acme/order-service/pull/139)
- Pagination returning wrong `totalPages` when filtered by status [#137](https://github.com/acme/order-service/pull/137)
- Health indicator returning DOWN when downstream has > 1s latency (threshold was too strict) [#136](https://github.com/acme/order-service/pull/136)

### Security
- Upgraded netty-codec-http from 4.1.107 to 4.1.108 (CVE-2025-XXXX) [#144](https://github.com/acme/order-service/pull/144)

### Deprecated
- `OrderService.createOrder(OrderRequest)` — use `createOrder(CreateOrderRequest)` instead. Will be removed in v2.0.0

---

## [1.2.0] - 2026-05-16

### Added
- Order tracking webhook notifications [#128](https://github.com/acme/order-service/pull/128)
```

### Changelog generation command

```sh
#!/usr/bin/env bash
# Generate changelog from git log since last tag
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

if [ -z "$LAST_TAG" ]; then
  RANGE="HEAD"
else
  RANGE="${LAST_TAG}..HEAD"
fi

echo "## [${NEW_VERSION}] - $(date +%Y-%m-%d)"
echo ""

# Group by conventional commit type
echo "### Added"
git log "$RANGE" --pretty=format:"- %s (#%h)" --grep="^feat:" | sed 's/^feat\(([^)]*)\)\?: //' || echo "- _(none)_"
echo ""
echo "### Fixed"
git log "$RANGE" --pretty=format:"- %s (#%h)" --grep="^fix:" | sed 's/^fix\(([^)]*)\)\?: //' || echo "- _(none)_"
echo ""
echo "### Changed"
git log "$RANGE" --pretty=format:"- %s (#%h)" --grep="^refactor:\|^perf:\|^build(deps)" | sed 's/^[a-z]*\(([^)]*)\)\?: //' || echo "- _(none)_"
echo ""
echo "### Security"
git log "$RANGE" --pretty=format:"- %s (#%h)" --grep="^fix(deps):\|^fix(security):" | sed 's/^fix\(([^)]*)\)\?: //' || echo "- _(none)_"
```

## Step 3: Version Bumping

### Maven project (single-module)

```sh
# Bump in pom.xml (using maven versions plugin)
mvn versions:set -DnewVersion=1.3.0
mvn versions:commit
```

### Maven project (multi-module)

```sh
# Bump all modules together
mvn versions:set -DnewVersion=1.3.0
mvn versions:commit
```

### Gradle project

**build.gradle / build.gradle.kts:**
```kotlin
// version.properties or gradle.properties
version=1.3.0
```

Or use a version catalog:
```toml
# gradle/libs.versions.toml
[versions]
order-service = "1.3.0"
```

```sh
# Bump using sed on gradle.properties
sed -i 's/^version=.*/version=1.3.0/' gradle.properties
```

### Spring Boot parent version in BOM/parent POM

When bumping the service version, also check if Spring Boot parent needs bumping:
```xml
<parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.3.0</version>  <!-- check for latest -->
</parent>
```

## Step 4: Create Release Artifacts

### Git tag

```sh
# Annotated tag with changelog snippet
git tag -a v1.3.0 -m "v1.3.0 — bulk cancel, CSV export, payment fix, Spring Boot 3.3.0"

# Push tag (triggers CI release pipeline)
git push origin v1.3.0
```

### GitHub Release

Use the generated changelog entry as the release body:

```sh
gh release create v1.3.0 \
  --title "v1.3.0 — Bulk Cancel + Payment Fix" \
  --notes-file <(echo "$CHANGELOG_ENTRY") \
  --target main
```

### Maven release plugin (alternative to manual)

```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-release-plugin</artifactId>
    <version>3.0.1</version>
    <configuration>
        <tagNameFormat>v@{project.version}</tagNameFormat>
        <scmCommentPrefix>[release]</scmCommentPrefix>
        <autoVersionSubmodules>true</autoVersionSubmodules>
        <goals>deploy</goals>
    </configuration>
</plugin>
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-scm-plugin</artifactId>
</plugin>
```

```sh
# Dry run
mvn release:prepare -DdryRun=true

# Actual release (bumps version, tags, commits, bumps to next snapshot)
mvn release:prepare release:perform
```

## Step 5: Release Notes

Tailor notes to the audience:

### Internal (engineering team)

```
## v1.3.0 Release Notes — Order Service

**Deployed**: 2026-05-19 14:30 UTC
**Deployer**: @devangchauhan
**CI Run**: https://github.com/acme/order-service/actions/runs/12345

### Changes
- 2 new features, 4 bug fixes, 1 dependency upgrade
- Full changelog: CHANGELOG.md#130

### Database Migrations
- V15__add_bulk_cancel_support.sql — adds `cancelled_by` column to orders

### Config Changes
- `orders.bulk-cancel.max-batch-size: 100` (new)

### Rollback Plan
- Revert deployment to v1.2.0
- Run `DROP COLUMN cancelled_by` if migration needs rollback
- No breaking API changes — no client updates needed

### Monitoring
- Dashboard: https://grafana.internal/d/order-service
- New metrics: `orders.bulk_cancel.duration`, `orders.bulk_cancel.errors`
- Alert threshold unchanged

### Known Issues
- None
```

### External (customers / API consumers)

```
## Order Service v1.3.0

### What's New
- **Bulk cancel orders**: Cancel multiple orders by status in a single API call
- **CSV export**: Export your order history to CSV for analysis

### Bug Fixes
- Fixed incorrect currency display on payment receipts
- Fixed duplicate order detection for concurrent checkouts

### API Changes
_(no breaking changes — your integrations continue to work)_

For details: https://docs.acme.com/changelog/order-service#v1.3.0
```

## Step 6: CI Release Automation

### GitHub Actions release workflow

```yaml
# .github/workflows/release.yml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Need full history for changelog

      - name: Set up JDK 21
        uses: actions/setup-java@v4
        with:
          java-version: 21
          distribution: temurin

      - name: Build
        run: mvn clean verify -DskipTests

      - name: Generate changelog
        run: |
          PREV_TAG=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo "")
          if [ -n "$PREV_TAG" ]; then
            git log "${PREV_TAG}..HEAD" --pretty=format:"- %s" --grep="^feat:\|^fix:\|^perf:" > changelog.md
          else
            echo "Initial release" > changelog.md
          fi

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          body_path: changelog.md
          generate_release_notes: true
          files: target/*.jar

      - name: Notify Slack
        uses: slackapi/slack-github-action@v1
        with:
          payload: |
            {
              "text": "Released ${GITHUB_REF_NAME} — <${{ github.server_url }}/${{ github.repository }}/releases/tag/${GITHUB_REF_NAME}|View release>"
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_RELEASE_WEBHOOK }}
```

### Automated semantic release (no manual bumping)

Add to CI (runs on every push to main):

```yaml
# .github/workflows/semantic-release.yml
name: Semantic Release

on:
  push:
    branches:
      - main

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          token: ${{ secrets.GH_PAT }}  # PAT to trigger tag push

      - name: Semantic Release
        uses: cycjimmy/semantic-release-action@v4
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          extra_plugins: |
            @semantic-release/changelog
            @semantic-release/git
            @semantic-release/exec
```

**`.releaserc` config:**
```json
{
  "branches": ["main"],
  "plugins": [
    "@semantic-release/commit-analyzer",
    "@semantic-release/release-notes-generator",
    "@semantic-release/changelog",
    ["@semantic-release/exec", {
      "prepareCmd": "mvn versions:set -DnewVersion=${nextRelease.version} && mvn versions:commit"
    }],
    ["@semantic-release/git", {
      "assets": ["pom.xml", "CHANGELOG.md"],
      "message": "chore(release): ${nextRelease.version}\n\n[skip ci]"
    }],
    "@semantic-release/github"
  ]
}
```

## Step 7: Verify

```sh
# Check no uncommitted changes
git status
# Should be clean

# Verify build passes at target version
mvn clean verify
# or: ./gradlew build

# Dry-run semantic release
npx semantic-release --dry-run --no-ci

# Verify changelog generated correctly
head -30 CHANGELOG.md

# Check the tag doesn't already exist
git tag -l "v1.3.0"

# Verify version in build file
grep "<version>" pom.xml
# or: grep "^version" gradle.properties

# After tagging, verify tag
git tag -v v1.3.0
```

## Checklist

- [ ] Version bump type determined from commit history (patch/minor/major)
- [ ] Conventional commit prefixes parsed correctly
- [ ] `BREAKING CHANGE` detected and reflected in MAJOR bump
- [ ] `CHANGELOG.md` updated following Keep a Changelog format
- [ ] Version bumped in `pom.xml` or `build.gradle` / `gradle.properties`
- [ ] Multi-module projects: all submodule versions consistent
- [ ] Build passes at the new version
- [ ] Annotated git tag created with message
- [ ] GitHub Release created with changelog content
- [ ] Release notes tailored to audience (internal vs external)
- [ ] Database migrations and config changes documented
- [ ] Rollback plan documented
- [ ] CI release workflow configured (or manual steps documented)
- [ ] Slack/Teams notification sent (if configured)
- [ ] Next snapshot version set (e.g., `1.4.0-SNAPSHOT`)

## Next Step
Release is complete. For the next iteration, use `/devskillslearning-pipeline:github` to create a milestone or story, then `/devskillslearning-pipeline:write-code` to implement.
