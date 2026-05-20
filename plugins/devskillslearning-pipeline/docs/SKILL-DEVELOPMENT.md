# Skill Development Guide

How to add, modify, and maintain skills in the DevSkillsLearning Pipeline plugin. Follow these conventions so every skill feels consistent, discoverable, and chainable.

## Skill File Format

Every skill is a single `SKILL.md` in its own directory under `skills/<skill-name>/`:

```
skills/
  <skill-name>/
    SKILL.md
```

### YAML Frontmatter

```yaml
---
name: devskillslearning-pipeline:<skill-name>
description: <One sentence — what it does and when to use it. Appears in the slash-command palette. Keep it specific.>
type: skill
---
```

**Rules:**
- `name`: fully qualified as `devskillslearning-pipeline:<skill-name>` — matches the directory name
- `description`: one sentence that tells the user WHEN to invoke this skill. Include trigger keywords (e.g., "Use when the user asks to..."). This is what the slash-command palette shows
- `type`: always `skill`

### Body Structure

Every skill follows this structure:

```
# <Skill Title>

[Intro paragraph — what you are (role) and what your goal is]

## What You Need to Provide
[Input table — Required? / Input / Example / Notes]

## Step 0: Discover the Project
[8-10 discovery steps — read CLAUDE.md, detect build system, architecture, version, conventions]

## Step 1: Determine Scope
[Decision table — maps user requests to what to implement]

## Step 2: Implement
[Subsections (2a, 2b, ...) — one per pattern/concern, each with code examples and rules]

## Step 3: Verify
[Shell commands to validate the work]

## Checklist
[Checkable items — each starts with `- [ ]`]

## Next Step
[One line recommending the next skill in the workflow chain]
```

## Step 0: Discovery Pattern

Every skill auto-discovers the target project. The Step 0 checklist is consistent across skills:

1. Read `CLAUDE.md` for project conventions
2. Check build file for relevant dependencies
3. Check `application.yml` for relevant config
4. Scan codebase for existing patterns in this skill's domain
5. Determine Spring Boot version (2.x → javax, 3.x → jakarta)
6. Determine architecture type (monolith, REST microservices, event-driven, gRPC, GraphQL, reactive)

**Rule:** Discovery before action. Never generate code without understanding the project first.

## Step 1: Scope Determination

Use a decision table to map user requests to implementation scope:

| Request | What to implement |
|---------|-------------------|
| "Specific ask" | Specific output |
| "Broader ask" | Broader output |

The table helps the skill (and the user) understand what will be produced for different request types.

## Step 2: Implementation Subsections

Each subsection (2a, 2b, etc.) covers one pattern or concern:

- **Code examples** — show the canonical pattern. Prefer Spring Boot 3.x (Jakarta) as the default, with Spring Boot 2.x notes where APIs differ
- **Rules** — bullet list of conventions that apply to that subsection
- **When to apply** — some subsections are conditional (e.g., "if event-driven", "if reactive")

### Architecture-Aware Code

Always show the servlet/blocking (default) pattern first. Add reactive/R2DBC variants in separate subsections or callout blocks. Add event-driven variants when relevant.

### Spring Boot Version Awareness

- Default all code examples to **Spring Boot 3.x** (Jakarta namespace, Lambda DSL for Security)
- When APIs differ significantly, add a "Spring Boot 2.x" callout with the `javax.*` equivalent
- Never mix `javax.*` and `jakarta.*` in the same example

## Checklist Conventions

Every skill ends with a checklist. Rules:

- Each item starts with `- [ ]` (Markdown task checkbox)
- Items are verification steps, not implementation steps
- Order items by dependency: structural checks → behavioral checks → integration checks
- Include architecture-specific items when conditional on project type
- Include security-sensitive items (no secrets in code, HTTPS enforced)
- The last few items should be build/tests-pass verification

## Cross-Referencing Other Skills

Skills don't exist in isolation. Cross-reference related skills at key decision points:

### In the Intro / Scope Section
When a user's request could be better served by a different skill:
```
**For comprehensive observability setup, use `/devskillslearning-pipeline:monitor`**
```

### In Implementation Subsections
When a pattern is the primary focus of another skill:
```
### 2e. Rate Limiting
**For full Resilience4j patterns (circuit breaker, retry, bulkhead), use
`/devskillslearning-pipeline:resilience`** — this section covers the Bucket4j filter approach.
```

### In Diagnostic Tables
When diagnosing failures, point to the skill that specializes in the fix:
```
| Circuit breaker open | Downstream failing | Use `/devskillslearning-pipeline:resilience` to review and tune |
```

### When NOT to Cross-Reference
- Don't cross-reference just because another skill exists — only when the user genuinely needs to know
- Don't cross-reference in the middle of a focused implementation flow
- The "Next Step" section at the end handles the primary handoff

## Next Step Handoff

Every skill MUST end with a `## Next Step` section that recommends the natural next skill:

```
## Next Step
After securing dependencies, use `/devskillslearning-pipeline:release` to cut a release
with the updated dependency versions documented in the changelog.
```

**Rules:**
- One sentence: "After <what this skill did>, use `<skill>` to <what next>."
- ALWAYS use the fully qualified skill name: `/devskillslearning-pipeline:<skill-name>`
- Optionally offer two paths if there's a natural fork: "use X to <reason> or Y to <reason>"

## Reference Files in docs/

When a skill needs large example files (full API specs, complete configs), extract them to `docs/` and reference them:

```
See `docs/api-examples.md` for the full annotated OpenAPI example.
```

This keeps skills lean — the skill teaches the WHY and HOW; the reference file shows the full WHAT.

**Existing reference files:**
- `docs/CONVENTIONS.md` — universal best practices (referenced by all skills as fallback when project conventions can't be discovered)
- `docs/api-examples.md` — full OpenAPI, AsyncAPI, gRPC, GraphQL spec examples (referenced by `design-api` and `document`)

## CONVENTIONS.md Integration

When a skill introduces new best-practice patterns, add corresponding sections to `docs/CONVENTIONS.md`:

- New conventions at the `##` level for top-level domains, `###` for sub-topics
- Include rules and minimal code snippets — full examples live in the skill or reference files
- Cross-reference the skill from conventions using "Use `/devskillslearning-pipeline:<skill>` to..."

## Skill Naming

- Use kebab-case for directory names: `write-code`, `design-api`, `perf-test`
- The fully qualified name in frontmatter uses the directory name: `devskillslearning-pipeline:write-code`
- Names should be verb-forward: `write-code` not `code-writer`, `design-api` not `api-designer`
- Exceptions for well-known terms: `github`, `database`, `monitor`

## Table of Contents (Mental Model)

When creating a new skill, place it in one of these phases:

| Phase | Skills | Entry criteria |
|-------|--------|---------------|
| Plan & Design | `design-api`, `database`, `github` | Before any code is written |
| Build & Implement | `scaffold`, `write-code`, `write-tests`, `refactor`, `migrate`, `document` | Code generation and modification |
| Verify & Harden | `code-review`, `diagnose`, `secure`, `resilience`, `dependency` | Quality gates and hardening |
| Ship & Operate | `perf-test`, `deploy`, `monitor`, `release` | Production readiness |

## Testing Changes Locally

1. Make your skill changes in the local clone
2. Run `./install.sh /path/to/test-java-project` to reinstall
3. In a Claude Code session in the test project: `/reload-plugins`
4. Invoke the skill: `/devskillslearning-pipeline:<skill-name>`
5. Verify Step 0 discovery works, the skill generates correct code, and the checklist is complete

## Commit Conventions

- `feat: add <skill-name> skill` — new skill
- `feat: add <feature> to <skill-name> skill` — significant new capability
- `fix: <description> in <skill-name> skill` — bug fix
- `docs: <description>` — documentation only
- Bump `version` in `plugin.json` on feature additions
