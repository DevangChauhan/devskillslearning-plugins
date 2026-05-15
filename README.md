# DevSkillsLearning Pipeline

Claude Code plugin pack for AI-first Java/Spring Boot microservices development. Provides slash-command skills that automate the SDLC: spec-driven code generation, architectural code review, and more.

## Installation

### Prerequisites

- [Claude Code](https://claude.ai/code) CLI installed and authenticated
- Verify with: `claude --version`

### Option 1: One-command install (recommended)

```sh
# Clone and install into your project in one go
git clone https://github.com/DevangChauhan/devskillslearning-plugins.git ~/devskillslearning-pipeline && \
  cd ~/devskillslearning-pipeline && \
  ./install.sh /path/to/your-project
```

### Option 2: Step-by-step install

```sh
# Step 1: Clone the marketplace repo
git clone https://github.com/DevangChauhan/devskillslearning-plugins.git ~/devskillslearning-pipeline

# Step 2: Navigate to your project
cd /path/to/your-java-project

# Step 3: Register the marketplace (one-time)
claude plugins marketplace add ~/devskillslearning-pipeline

# Step 4: Install the plugin at project scope
claude plugins install devskillslearning-pipeline --scope project

# Step 5: Activate in your Claude Code session
# Type: /reload-plugins
```

### Verify Installation

```sh
# List installed plugins — you should see devskillslearning-pipeline
claude plugins list

# Show plugin details
claude plugins details devskillslearning-pipeline
```

After running `/reload-plugins` in Claude Code, these slash commands become available:

| Skill | Invocation | What it does |
|-------|-----------|--------------|
| Write Code | `/devskillslearning-pipeline:write-code` | Reads OpenAPI spec, implements full stack: entity → repo → DTO → mapper → service → controller → tests |
| Code Review | `/devskillslearning-pipeline:code-review` | Reviews code against architecture rules, conventions, error handling — reports issues with file:line references and severity |

## Updating

When new versions are released, update to get the latest skills, conventions, and fixes:

```sh
# Step 1: Pull latest changes from GitHub
cd ~/devskillslearning-pipeline
git pull origin main

# Step 2: Update the plugin in Claude Code
claude plugins update devskillslearning-pipeline

# Step 3: Activate
# Type /reload-plugins in Claude Code
```

To check which version you have:

```sh
claude plugins list                  # Shows installed version
claude plugins details devskillslearning-pipeline  # Full details
```

## Uninstall

```sh
# Step 1: Uninstall the plugin from your project
cd /path/to/your-java-project
claude plugins uninstall devskillslearning-pipeline

# Step 2: Remove the marketplace registry (optional)
claude plugins marketplace remove devskillslearning-pipeline

# Step 3: Delete the cloned repo (optional)
rm -rf ~/devskillslearning-pipeline
```

## Requirements

For the skills to work effectively, your project needs:

- Java 21, Spring Boot 3.2.x, Maven multi-module
- OpenAPI specs at `services/<name>/src/main/resources/openapi/openapi.yaml`
- The EasyBank package structure (see [docs/CONVENTIONS.md](plugins/devskillslearning-pipeline/docs/CONVENTIONS.md))
- `easybank-common` library with `ErrorCode` enum, `BaseException`, `ApiResponse<T>`

## Conventions Encoded

The skills automatically enforce these rules:

| Rule | Enforced by |
|------|------------|
| Constructor injection only | `write-code` + `code-review` |
| Records for DTOs | `write-code` + `code-review` |
| `BigDecimal` for money (never `Double`) | `write-code` + `code-review` |
| `ErrorCode` enum (never ad-hoc strings) | `write-code` + `code-review` |
| `@Getter`/`@Setter`/`@NoArgsConstructor` on entities (no `@Data`) | `write-code` + `code-review` |
| Controllers implement OpenAPI-generated interfaces | `write-code` + `code-review` |
| Controllers → Services → Repositories (no skipping layers) | `code-review` |
| `*.controller`, `*.service.impl`, `*.repository`, `*.entity`, `*.dto`, `*.mapper`, `*.exception` | Both + ArchUnit CI |

## License

MIT
