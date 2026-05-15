# DevSkillsLearning Plugins

Claude Code skill pack for AI-first Java/Spring Boot microservices development. Provides slash-command skills that automate the SDLC: spec-driven code generation, architectural code review, and more.

## Installation

### Prerequisites

- [Claude Code](https://claude.ai/code) CLI installed (`which claude`)
- Verify: `claude --version`

### Option 1: Install from GitHub (recommended)

```sh
# Step 1: Clone the marketplace repo
git clone https://github.com/DevangChauhan/devskillslearning-plugins.git ~/devskillslearning-plugins

# Step 2: Register as a Claude Code marketplace
claude plugins marketplace add ~/devskillslearning-plugins

# Step 3: Install the plugin
claude plugins install devskillslearning-plugins

# Step 4: Activate
# Type /reload-plugins in your Claude Code session, or restart Claude Code
```

### Option 2: Install from local directory

```sh
# Step 1: Register the marketplace
claude plugins marketplace add /path/to/devskillslearning-plugins

# Step 2: Install the plugin
claude plugins install devskillslearning-plugins

# Step 3: Activate
# Type /reload-plugins in your Claude Code session
```

### Verify Installation

```sh
# List installed plugins — you should see devskillslearning-plugins
claude plugins list

# Show plugin details
claude plugins details devskillslearning-plugins
```

In your Claude Code session, run `/reload-plugins`. You should see:

```
Reloaded: 19 plugins · 8 skills · 34 agents · 4 hooks ...
```

## Available Skills

After installation, these slash commands become available:

| Skill | Invocation | What it does |
|-------|-----------|--------------|
| Write Code | `/devskillslearning-plugins:write-code` | Implements a service endpoint or feature following project conventions — reads OpenAPI spec, generates entity → repository → DTO → mapper → service → controller with tests |
| Code Review | `/devskillslearning-plugins:code-review` | Reviews code against architecture rules, naming conventions, error handling patterns, and test coverage — reports issues with severity and file:line references |

## Requirements

For the skills to work effectively, your project needs:

- Java 21, Spring Boot 3.2.x, Maven multi-module
- OpenAPI specs at `services/<name>/src/main/resources/openapi/openapi.yaml`
- The EasyBank package structure (see [docs/CONVENTIONS.md](plugins/devskillslearning-plugins/docs/CONVENTIONS.md))
- `easybank-common` library with `ErrorCode` enum, `BaseException`, `ApiResponse<T>`

## Conventions Encoded

The skills automatically enforce these rules:

| Rule | Enforced by |
|------|------------|
| Constructor injection only | `write-code` + `code-review` |
| Records for DTOs | `write-code` + `code-review` |
| `BigDecimal` for money | `write-code` + `code-review` |
| `ErrorCode` enum (never ad-hoc strings) | `write-code` + `code-review` |
| `@Getter`/`@Setter`/`@NoArgsConstructor` on entities (no `@Data`) | `write-code` + `code-review` |
| Controllers implement OpenAPI-generated interfaces | `write-code` + `code-review` |
| Controllers → Services → Repositories (no skipping layers) | `code-review` |
| Packages: `*.controller`, `*.service.impl`, `*.repository`, `*.entity`, `*.dto`, `*.mapper`, `*.exception` | Both + ArchUnit CI |

## Uninstall

```sh
claude plugins uninstall devskillslearning-plugins
claude plugins marketplace remove devskillslearning-plugins
```

## License

MIT
