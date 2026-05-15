---
name: devskillslearning-pipeline:github
description: GitHub project management and PR review integration. Use when the user asks to create epics/stories/tickets, read or update issues, connect PRs to tickets, review a PR by URL or ticket ID, or manage GitHub project boards. Requires GitHub MCP tools to be configured.
type: skill
---

# GitHub Integration

You are an expert in GitHub project management and PR review automation. You use GitHub MCP tools to create, read, update, and manage issues, pull requests, and code reviews.

## What You Need to Provide

Before using this skill, ensure the GitHub MCP server is configured in your Claude Code settings. If you haven't set it up yet, see the [setup guide](#github-mcp-setup) at the bottom.

### For issue/ticket operations:

| What you want | What you need to provide |
|---------------|-------------------------|
| Create an epic | `owner/repo`, title, description, labels (e.g., `epic`) |
| Create a user story | `owner/repo`, title, description, labels, assignees (optional), linked epic issue number |
| Read an issue | `owner/repo`, issue number |
| List issues | `owner/repo`, optional filters (state, labels, assignee) |
| Update an issue | `owner/repo`, issue number, what to change (state, assignees, labels, title, body) |
| Comment on an issue | `owner/repo`, issue number, the comment text |
| Search issues | `owner/repo`, search query |

### For PR review operations:

| What you want | What you need to provide |
|---------------|-------------------------|
| Review a PR by URL | The PR URL (e.g., `https://github.com/owner/repo/pull/42`) |
| Review a PR by ticket ID | `owner/repo`, the ticket/issue number — I will find the linked PR |
| Get PR details | `owner/repo`, PR number |
| Submit a PR review | `owner/repo`, PR number, review decision (approve/request changes/comment) |
| Add inline review comments | `owner/repo`, PR number, file path, line number, comment text |

**If you only have the ticket/issue number**: I will find the linked PR automatically by searching for PRs that reference that issue.

**If you provide a PR URL**: I will parse `owner`, `repo`, and `pullNumber` from the URL automatically.

### Quick Examples

```
# Create an epic
/devskillslearning-pipeline:github
Create an epic in devangchauhan/myproject titled "User Authentication System"
with description "Implement OAuth2, JWT, and role-based access control for all services"

# Create a story
Create a user story under epic #42 for "Add JWT token refresh endpoint"
with acceptance criteria: "Given an expired token, when calling POST /auth/refresh,
then return a new valid token"

# Read and act on a ticket
Read ticket #15 from devangchauhan/myproject, understand the requirements,
and implement the changes.

# Review a PR
Review PR https://github.com/devangchauhan/myproject/pull/67

# Review by ticket
Review the PR linked to ticket #15 in devangchauhan/myproject
```

---

## Step 0: Determine What's Needed

Read the user's request and classify it into one of these workflows:

| User intent | Workflow |
|-------------|----------|
| Create/manage epics, stories, tickets | **Workflow A: Issue Management** |
| Read issues, search for tickets | **Workflow B: Issue Reading** |
| Review a PR by URL or ticket ID | **Workflow C: PR Review** |
| Create a PR linked to an issue | **Workflow D: PR Creation** |
| Full cycle: read ticket → implement → create PR → review | **Workflow E: End-to-End** |

**CRITICAL**: If the user provides just a project name (e.g., "myproject"), assume the owner is their GitHub username. Use `mcp__plugin_github_github__get_me` to discover the authenticated user's username if needed. The repo format is always `owner/repo`.

---

## Workflow A: Issue Management (Create & Update)

### A1: Create an Epic

An epic is a large body of work, tracked as a GitHub issue with an `epic` label.

```
Use: mcp__plugin_github_github__issue_write
  method: create
  owner: <owner>
  repo: <repo>
  title: "Epic: <descriptive title>"
  body: |
    ## Description
    <what this epic covers, why it matters>

    ## Stories
    - [ ] Story 1: <brief description>
    - [ ] Story 2: <brief description>
    - [ ] Story 3: <brief description>

    ## Success Criteria
    - <measurable outcome 1>
    - <measurable outcome 2>

    ## Dependencies
    - <any external dependencies>

  labels: ["epic"]
```

Take note of the returned issue number. This becomes the parent for child stories.

### A2: Create a User Story

A user story is a single unit of work, linked to its parent epic.

```
Use: mcp__plugin_github_github__issue_write
  method: create
  owner: <owner>
  repo: <repo>
  title: "<concise story title — no 'Story:' prefix needed>"
  body: |
    ## User Story
    As a <role>,
    I want <capability>,
    so that <benefit>.

    ## Acceptance Criteria
    - [ ] Given <precondition>, when <action>, then <expected result>
    - [ ] Given <precondition>, when <action>, then <expected result>

    ## Technical Notes
    <implementation hints, affected services, database changes>

    ## Definition of Done
    - [ ] Code implemented with tests
    - [ ] PR reviewed and merged
    - [ ] Deployed to staging and verified

    Parent: #{epic_number}
  labels: ["story", "<domain-label>"]
  assignees: ["<github-username>"]  # optional
```

Then link the story to its epic using a comment:
```
Use: mcp__plugin_github_github__add_issue_comment
  owner: <owner>
  repo: <repo>
  issue_number: <epic_number>
  body: "📎 Sub-task: #<story_number> — <story title>"
```

### A3: Create a Bug Ticket

```
Use: mcp__plugin_github_github__issue_write
  method: create
  owner: <owner>
  repo: <repo>
  title: "<concise bug description>"
  body: |
    ## Bug Description
    <what happens vs what should happen>

    ## Steps to Reproduce
    1. <step 1>
    2. <step 2>
    3. <step 3>

    ## Expected Behavior
    <what should happen>

    ## Actual Behavior
    <what actually happens>

    ## Environment
    - Service: <service-name>
    - Version: <version>
    - Branch: <branch>

    ## Logs / Stack Trace
    ```
    <paste logs>
    ```
  labels: ["bug", "severity:<high|medium|low>"]
```

### A4: Update an Issue

```
Use: mcp__plugin_github_github__issue_write
  method: update
  owner: <owner>
  repo: <repo>
  issue_number: <number>
  state: "closed"              # to close
  state_reason: "completed"    # "completed" or "not_planned" or "duplicate"
  labels: ["new-label"]       # overwrites existing labels
  assignees: ["username"]
```

### A5: Add a Comment

```
Use: mcp__plugin_github_github__add_issue_comment
  owner: <owner>
  repo: <repo>
  issue_number: <number>
  body: "<comment text — supports markdown>"
```

---

## Workflow B: Issue Reading

### B1: Read a Single Issue

```
Use: mcp__plugin_github_github__issue_read
  method: get
  owner: <owner>
  repo: <repo>
  issue_number: <number>
```

Also read its comments for full context:
```
Use: mcp__plugin_github_github__issue_read
  method: get_comments
  owner: <owner>
  repo: <repo>
  issue_number: <number>
```

### B2: List/Filter Issues

```
Use: mcp__plugin_github_github__list_issues
  owner: <owner>
  repo: <repo>
  state: "OPEN"          # or "CLOSED" — omit for both
  labels: ["story"]      # filter by label
  sort: "CREATED_AT"
  direction: "DESC"
  perPage: 30
```

### B3: Search Issues

```
Use: mcp__plugin_github_github__search_issues
  query: "repo:<owner>/<repo> is:issue is:open label:story"
  sort: "created"
  order: "desc"
  perPage: 30
```

### B4: Read Issue Labels

```
Use: mcp__plugin_github_github__issue_read
  method: get_labels
  owner: <owner>
  repo: <repo>
  issue_number: <number>
```

### B5: When User Wants to Act on a Ticket

If the user says "take ticket #15 and implement it" or "work on issue #23":

1. **Read the issue** to understand requirements, acceptance criteria, and technical notes.
2. **Read comments** for any additional context or clarifications.
3. **Read linked PRs** — check if there's already a PR referencing this issue by searching PRs with the issue number in the query.
4. **Report back** what you found: title, description, AC, assignee, labels.
5. **Proceed to implement** using `/devskillslearning-pipeline:write-code` conventions, referencing the ticket in your commits and messages.
6. When done, **update the issue** with a comment linking to the PR or summarizing the changes.

---

## Workflow C: PR Review

### C1: Parse PR URL or Ticket ID

**If the user gives a PR URL** like `https://github.com/owner/repo/pull/42`:
- Extract: `owner`, `repo`, `pullNumber=42`

**If the user gives a ticket/issue ID** like "ticket #15" or "issue 23":
1. First, find linked PRs by searching:
   ```
   Use: mcp__plugin_github_github__search_issues
     query: "repo:<owner>/<repo> type:pr linked:issue"  # or search PRs mentioning the issue
   ```
   Alternative: use `gh pr list --search "fixes #15"` via Bash.
2. If multiple PRs found, ask the user which one to review.
3. If no PR found, tell the user no PR is linked to that ticket yet.

### C2: Gather PR Context

Get full PR details:
```
Use: mcp__plugin_github_github__pull_request_read
  method: get
  owner: <owner>
  repo: <repo>
  pullNumber: <number>
```

Get the diff:
```
Use: mcp__plugin_github_github__pull_request_read
  method: get_diff
  owner: <owner>
  repo: <repo>
  pullNumber: <number>
```

Get changed files list:
```
Use: mcp__plugin_github_github__pull_request_read
  method: get_files
  owner: <owner>
  repo: <repo>
  pullNumber: <number>
  perPage: 100
```

Get existing reviews:
```
Use: mcp__plugin_github_github__pull_request_read
  method: get_reviews
  owner: <owner>
  repo: <repo>
  pullNumber: <number>
```

Get existing review comments:
```
Use: mcp__plugin_github_github__pull_request_read
  method: get_review_comments
  owner: <owner>
  repo: <repo>
  pullNumber: <number>
  perPage: 100
```

Get CI check runs:
```
Use: mcp__plugin_github_github__pull_request_read
  method: get_check_runs
  owner: <owner>
  repo: <repo>
  pullNumber: <number>
```

### C3: Perform the Review

Now apply the full code review process from `/devskillslearning-pipeline:code-review` to the PR diff. Check:

1. **Architecture checks** — package placement, dependency direction, constructor injection
2. **Spring Boot version consistency** — javax vs jakarta
3. **Transaction correctness** — self-invocation, missing @Transactional, read-only writes
4. **N+1 query detection** — loops with repository calls
5. **Security** — auth, input validation, CORS, secrets
6. **Conventions** — entities, DTOs, controllers, services, naming
7. **Testing** — coverage for happy path and error cases
8. **Observability** — @Slf4j, @Timed, counters

### C4: Submit the Review

After analysis, submit the review using one of these methods:

**To submit a complete review with a summary**:
```
Use: mcp__plugin_github_github__pull_request_review_write
  method: create
  owner: <owner>
  repo: <repo>
  pullNumber: <number>
  event: "APPROVE"           # or "REQUEST_CHANGES" or "COMMENT"
  body: |
    ## Review Summary

    ### ✅ What's Good
    - <positive observations>

    ### ❌ Issues Found

    | Severity | File | Line | Issue | Fix |
    |----------|------|------|-------|-----|
    | BLOCKER  | ...  | ...  | ...   | ... |
    | HIGH     | ...  | ...  | ...   | ... |
    | MEDIUM   | ...  | ...  | ...   | ... |

    ### 🔧 Recommended Changes
    <actionable recommendations>
```

**To add inline comments on specific lines**:
```
Use: mcp__plugin_github_github__add_comment_to_pending_review
  owner: <owner>
  repo: <repo>
  pullNumber: <number>
  path: "<relative file path>"
  body: "<specific comment about this line>"
  line: <line number>
  side: "RIGHT"
  subjectType: "LINE"
```

For multi-line comments:
```
Use: mcp__plugin_github_github__add_comment_to_pending_review
  ...
  startLine: <start line>
  line: <end line>
  startSide: "RIGHT"
  side: "RIGHT"
  subjectType: "LINE"
```

**Workflow for inline comments**:
1. First create a pending review (pull_request_review_write with method="create", no event)
2. Add all inline comments (add_comment_to_pending_review for each)
3. Submit the pending review (pull_request_review_write with method="submit_pending", event="APPROVE"/"REQUEST_CHANGES"/"COMMENT")

### C5: Also Run the Local Code Review

After submitting the GitHub review, also run through the `/devskillslearning-pipeline:code-review` checklist locally. Read the changed files from the PR diff and apply all 100+ checks. This provides complementary analysis that the GitHub review summary alone can't capture.

---

## Workflow D: PR Creation (Linked to Issue)

When the user has implemented a fix/feature and wants to create a PR:

```
Use: mcp__plugin_github_github__create_pull_request
  owner: <owner>
  repo: <repo>
  title: "<PR title — under 70 chars>"
  head: "<feature-branch>"
  base: "main"
  body: |
    ## Summary
    <1-3 bullet points describing the changes>

    ## Related Issue
    Closes #<issue_number>

    ## Changes
    <list key changes>

    ## Test Plan
    - [ ] Unit tests pass
    - [ ] Integration tests pass
    - [ ] Manual verification steps

    🤖 Generated with [Claude Code](https://claude.com/claude-code)
  draft: false
```

To link a PR to an issue without closing it: use `Refs #<number>` instead of `Closes #<number>`.

---

## Workflow E: End-to-End (Read Ticket → Implement → PR → Review)

Full cycle workflow:

1. **Read the ticket** — `issue_read` method=get + method=get_comments
2. **Understand requirements** — summarize AC, technical notes, DoD
3. **Check for existing work** — search for linked PRs, check if someone else is assigned
4. **Assign yourself** — `issue_write` method=update, assignees=[your-username]
5. **Add a progress comment** — "Starting work on this. Branch: `feature/#{number}-description`"
6. **Implement** — use `/devskillslearning-pipeline:write-code` conventions
7. **Create the PR** — use Workflow D, linked to the issue
8. **Request review** — `update_pull_request` with reviewers if needed
9. **Update the issue** — add comment with PR link and implementation notes

---

## GitHub MCP Setup

If the GitHub MCP tools are not yet available, guide the user to set them up:

### Step 1: Get a GitHub Personal Access Token (PAT)

Go to https://github.com/settings/tokens → Generate new token (classic) with these scopes:
- `repo` (full control of private repositories)
- `read:org` (read org and team membership)
- `workflow` (if you need to trigger GitHub Actions)

### Step 2: Configure the MCP Server

Add to `~/.claude/settings.json` under `mcpServers`:

```json
{
  "mcpServers": {
    "github": {
      "type": "http",
      "url": "https://mcp.github.com/mcp",
      "headers": {
        "Authorization": "Bearer <your-github-token>"
      }
    }
  }
}
```

### Step 3: Verify

In a Claude Code session, run `/reload-plugins` and then ask: "List my open issues in owner/repo". If the MCP tools respond, everything is configured.

---

## Reference: MCP Tool Quick Reference

| Tool | Purpose |
|------|---------|
| `mcp__plugin_github_github__issue_write` | Create or update issues |
| `mcp__plugin_github_github__issue_read` | Read issue details, comments, labels |
| `mcp__plugin_github_github__list_issues` | List issues with filters |
| `mcp__plugin_github_github__search_issues` | Search issues across repos |
| `mcp__plugin_github_github__add_issue_comment` | Add comment to issue/PR |
| `mcp__plugin_github_github__list_pull_requests` | List PRs |
| `mcp__plugin_github_github__search_pull_requests` | Search PRs |
| `mcp__plugin_github_github__pull_request_read` | Get PR details, diff, files, reviews, comments, checks |
| `mcp__plugin_github_github__pull_request_review_write` | Create/submit/delete PR review |
| `mcp__plugin_github_github__add_comment_to_pending_review` | Add inline comment to pending review |
| `mcp__plugin_github_github__create_pull_request` | Create a PR |
| `mcp__plugin_github_github__update_pull_request` | Update PR metadata |
| `mcp__plugin_github_github__get_me` | Get authenticated user info |
| `mcp__plugin_github_github__get_file_contents` | Read file from GitHub |
| `mcp__plugin_github_github__search_code` | Search code on GitHub |
| `mcp__plugin_github_github__request_copilot_review` | Request Copilot code review |

---

## Checklist

- [ ] GitHub owner/repo identified correctly
- [ ] Issue created/updated with proper labels and structure
- [ ] Epic → Story parent-child linked via comments
- [ ] PR review: all checks applied (architecture, security, N+1, conventions)
- [ ] Inline comments created before submitting review
- [ ] PR linked to issue via `Closes #N` or `Refs #N`
- [ ] CI check runs reviewed before approval
- [ ] Comments are constructive and actionable
