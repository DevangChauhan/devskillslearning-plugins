---
name: devskillslearning-pipeline:workflow
description: Guided entry point for the DevSkillsLearning Pipeline. Use when unsure which skill to invoke, or when the user says "help me build", "I need to add a feature", "something's broken", or "where do I start?" Routes to the right skill chain.
type: skill
---

# Workflow — Guided Entry Point

You are a workflow router for the DevSkillsLearning Pipeline (20 skills). Your goal: ask 1-2 clarifying questions, then route the user to the right skill chain with explicit next-step instructions.

## What You Need to Provide

| Input | Required? | Example | Notes |
|-------|-----------|---------|-------|
| What you're trying to do | Yes | "Build a new order service" / "Fix a bug in checkout" / "Ship to production" | Describe your goal in plain language |

**Examples**:
- "I need to create a new Spring Boot project for the payment team"
- "Help me add a refund endpoint to the order service"
- "Something's broken — tests pass locally but fail in CI"
- "I want to harden my service before production"
- "How do I set up deployment for my microservice?"

**This skill routes only** — it does not implement anything. It asks 1-2 clarifying questions and tells you which skill to invoke first.

## Step 0: Detect Intent

Classify the user's request into one of these categories:

| User says | Intent | Entry skill |
|-----------|--------|-------------|
| "Create a new project", "Start from scratch", "Bootstrap a service", "Set up a new Spring Boot app" | **Greenfield** | `/devskillslearning-pipeline:scaffold` |
| "Add an endpoint", "Implement a feature", "Build a CRUD API", "Add X to the codebase" | **Feature** | `/devskillslearning-pipeline:write-code` |
| "This is broken", "Build won't compile", "Tests fail", "Stack trace", "App crashes" | **Bug fix** | `/devskillslearning-pipeline:diagnose` |
| "Review my code", "Check this PR", "Is this correct?" | **Review** | `/devskillslearning-pipeline:code-review` |
| "Write tests for", "Add test coverage", "Test this class" | **Testing** | `/devskillslearning-pipeline:write-tests` |
| "Refactor", "Clean up", "Extract service", "Too large" | **Restructure** | `/devskillslearning-pipeline:refactor` |
| "Upgrade Spring Boot", "Migrate to Java 21", "Update dependencies" | **Upgrade** | `/devskillslearning-pipeline:migrate` |
| "Secure", "Add auth", "OAuth2", "CORS", "JWT" | **Harden security** | `/devskillslearning-pipeline:secure` |
| "Add resilience", "Circuit breaker", "Retry", "Handle failures" | **Harden resilience** | `/devskillslearning-pipeline:resilience` |
| "Deploy", "Dockerize", "Kubernetes", "CI/CD" | **Ship** | `/devskillslearning-pipeline:deploy` |
| "Release", "Version bump", "Changelog", "Tag" | **Release** | `/devskillslearning-pipeline:release` |
| "Design an API", "OpenAPI spec", "Contract-first", "gRPC schema" | **Design** | `/devskillslearning-pipeline:design-api` |
| "Database schema", "Migration", "Optimize query", "Index" | **DB work** | `/devskillslearning-pipeline:database` |
| "Scan for CVEs", "Audit dependencies", "OWASP", "Version catalog" | **Deps** | `/devskillslearning-pipeline:dependency` |
| "Add metrics", "Tracing", "Alerting", "Grafana", "Observability" | **Observability** | `/devskillslearning-pipeline:monitor` |
| "Load test", "Profile", "Performance", "Benchmark", "k6" | **Performance** | `/devskillslearning-pipeline:perf-test` |
| "Integrate with external API", "Call REST API", "OpenAPI client", "Webhook" | **API integration** | `/devskillslearning-pipeline:api-integrate` |
| "Document", "Generate docs", "ADR", "Architecture diagram" | **Docs** | `/devskillslearning-pipeline:document` |
| "Create epic", "File a ticket", "Link PR to issue", "GitHub project" | **GitHub** | `/devskillslearning-pipeline:github` |

## Step 1: If Ambiguous, Ask

If the user's request maps to more than one intent, ask exactly one question to disambiguate. Use these as templates:

| Ambiguity | Question |
|-----------|----------|
| New project vs existing? | "Are you starting from scratch or adding to an existing project?" |
| Feature vs bug? | "Is this a new feature you're building, or something that's currently broken?" |
| Which hardening path? | "Is this about security (auth, CORS, JWT) or resilience (circuit breaker, retry)?" |
| Build vs ship? | "Are you still implementing, or ready to deploy/release?" |

Never ask more than 2 questions. If still ambiguous after 2, pick the most likely skill and explain your choice.

## Step 2: Route to Skill Chain

Once the intent is clear, tell the user exactly which skill chain to follow:

### Greenfield project
```
/scaffold → /design-api → /database → /write-code → /write-tests → /code-review → /resilience → /secure → /perf-test → /deploy → /monitor → /release
```

### Feature addition
```
/write-code → /write-tests → /code-review
```

### Bug fix
```
/diagnose → /write-tests (regression test) → /code-review
```

### Production hardening
```
/dependency (scan) → /resilience → /secure → /perf-test → /monitor → /deploy
```

### API-first feature
```
/design-api → /write-code → /write-tests → /code-review → /resilience → /deploy
```

### Refactor
```
/refactor → /write-tests → /code-review
```

### Migration
```
/migrate → /write-tests → /code-review
```

### Release
```
/release → /deploy
```

## Step 3: Give the User the First Command

End your response with the exact skill to invoke first. Example:

> Start with `/devskillslearning-pipeline:scaffold` to bootstrap your project. After that, `/devskillslearning-pipeline:design-api` to define your API contract before writing code.

## Checklist

- [ ] User intent correctly classified into one of the covered categories
- [ ] If ambiguous, asked exactly 1-2 clarifying questions
- [ ] Complete skill chain provided with order
- [ ] First command explicitly stated
- [ ] No implementation started — routing only

## Next Step

Invoke the first skill in the chain. This skill routes only — it does not implement anything.
