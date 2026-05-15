# DevSkillsLearning Plugins

Claude Code skill pack for AI-first Java/Spring Boot microservices development. Provides slash-command skills that automate the SDLC: spec-driven code generation, architectural code review, and more.

## Quick Start

```sh
# Install into a project
./install.sh /path/to/your-project

# Or install into current directory
./install.sh .
```

The installer copies skills into `<project>/.claude/skills/devskillslearning-plugins/`. After install, the skills are available as slash commands:

```
/devskillslearning-plugins:write-code
/devskillslearning-plugins:code-review
```

## Skills

| Skill | What it does |
|-------|-------------|
| `write-code` | Implements a service endpoint or feature following project conventions (OpenAPI-first, constructor injection, ErrorCode catalog, ArchUnit-compliant packages) |
| `code-review` | Reviews code against architecture rules, naming conventions, error handling patterns, and test coverage — catches issues before CI does |

## Requirements

- Claude Code CLI installed
- Project must have an OpenAPI spec at `services/<name>/src/main/resources/openapi/openapi.yaml`
- Project should follow the EasyBank package structure conventions (see `docs/CONVENTIONS.md`)

## Conventions Reference

The skills encode these rules (customize `docs/CONVENTIONS.md` for your project):

- Constructor injection only — no `@Autowired` on fields
- Records for DTOs, `@Getter`/`@Setter`/`@NoArgsConstructor` on entities
- `ApiResponse<T>` envelope from every controller
- `ErrorCode` enum for all error responses (never ad-hoc strings)
- Controllers in `*.controller`, services in `*.service.impl`, repos in `*.repository`, entities in `*.entity`, mappers in `*.mapper`
- Controllers implement OpenAPI-generated interfaces
- ArchUnit tests enforce package structure at build time
