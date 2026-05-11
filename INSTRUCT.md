# Using Symphony

Symphony is a long-running orchestration service for coding-agent work. It watches a Linear project,
creates one isolated workspace per eligible issue, starts Codex in that workspace, and gives Codex
the repo-owned instructions from `WORKFLOW.md`.

Use this repository's root `WORKFLOW.md` as the canonical workflow contract. The Elixir reference
implementation lives in `elixir/`, but the workflow policy for this checkout is kept at the repo
root.

## What Symphony Needs

- A repository that is ready for unattended coding-agent work: deterministic setup, tests, and clear
  contribution rules.
- `mise` for the Elixir/Erlang toolchain.
- A Linear personal API key exported as `LINEAR_API_KEY`.
- A Linear project slug configured in `WORKFLOW.md`.
- Optional environment:
  - `LINEAR_ASSIGNEE` to restrict polling to work assigned to one person or bot.
  - `SYMPHONY_WORKSPACE_ROOT` to choose where per-issue workspaces are created.

The current root workflow is configured for Linear and polls issues in these active states:
`Todo`, `In Progress`, `Merging`, and `Rework`. It treats `Closed`, `Cancelled`, `Canceled`,
`Duplicate`, and `Done` as terminal states.

## Configure The Workflow

Edit `WORKFLOW.md` when you need to change orchestration behavior. Keep all runtime policy there:

- `tracker` selects Linear, the API key environment variable, project slug, assignee filter, and
  active or terminal states.
- `polling.interval_ms` controls how often Symphony checks Linear.
- `workspace.root` controls where issue workspaces are created.
- `hooks.after_create` bootstraps each fresh workspace. This fork clones
  `https://github.com/tblakex01/symphony.git` and runs `.codex/worktree_init.sh`.
- `hooks.before_remove` runs cleanup before terminal-state workspaces are removed.
- `agent.max_concurrent_agents` and `agent.max_turns` bound parallelism and retry depth.
- `codex.command`, `codex.approval_policy`, and sandbox fields define how Codex is launched.
- The Markdown body is the prompt template rendered for each Linear issue.

Do not create a second workflow file for the same behavior unless you are deliberately changing the
workflow contract. Keep business rules and state-transition policy in one place.

## Run Symphony Locally

From a fresh checkout:

```bash
cd symphony/elixir
mise trust
mise install
mise exec -- mix setup
mise exec -- mix build
export LINEAR_API_KEY=lin_api_...
export SYMPHONY_WORKSPACE_ROOT="$HOME/code/symphony-workspaces"
mise exec -- ./bin/symphony ../WORKFLOW.md
```

To restrict polling to one assignee:

```bash
export LINEAR_ASSIGNEE=your-linear-user-or-bot-id
mise exec -- ./bin/symphony ../WORKFLOW.md
```

To enable the dashboard:

```bash
mise exec -- ./bin/symphony --port 4000 ../WORKFLOW.md
```

Then open `http://127.0.0.1:4000` and watch active sessions, retries, token counts, and issue
state.

## Normal Operating Loop

1. Create or move a Linear issue into an active state, usually `Todo`.
2. Symphony polls Linear and claims eligible work up to `agent.max_concurrent_agents`.
3. Symphony creates a per-issue workspace under `workspace.root`.
4. `hooks.after_create` bootstraps the workspace.
5. Symphony renders the `WORKFLOW.md` prompt with issue fields such as `issue.identifier`,
   `issue.title`, `issue.description`, labels, URL, and state.
6. Codex works inside only that issue workspace.
7. The agent keeps one `## Codex Workpad` comment on the Linear issue current with plan,
   acceptance criteria, validation, blockers, and handoff notes.
8. The issue moves through the workflow policy:
   - `Todo` -> `In Progress` when execution starts.
   - `In Progress` -> `Human Review` only after implementation, validation, PR feedback sweep, and
     green checks.
   - `Merging` runs the repo `land` skill and lands the approved PR.
   - Terminal states stop active runs and trigger workspace cleanup.

## Demo With `@linear`

Use the Linear plugin to create or inspect work, then let Symphony execute the issue. This example is
safe to adapt to your own project slug and team names.

### 1. Ask `@linear` to create a small issue

```text
@linear Create an issue in the Symphony project titled "Docs: clarify local dashboard startup".

Put it in Todo. Use this description:

Add a short docs update explaining how to launch Symphony with the optional dashboard.

Acceptance Criteria:
- The docs mention the exact command for starting the dashboard on port 4000.
- The docs explain that the dashboard is available at http://127.0.0.1:4000.
- The change does not introduce a second setup path.

Validation:
- Run the most targeted docs or formatting check available.
- If there is no docs check, inspect the changed Markdown manually and say so in the workpad.
```

Expected result: Linear creates a `Todo` issue in the configured project. On the next poll, Symphony
sees the issue, creates a workspace, moves it to `In Progress`, writes or updates the
`## Codex Workpad` comment, implements the docs change, validates it, opens or updates the PR, and
moves the issue to `Human Review` when the workflow quality bar is met.

### 2. Start Symphony

```bash
cd symphony/elixir
export LINEAR_API_KEY=lin_api_...
export SYMPHONY_WORKSPACE_ROOT="$HOME/code/symphony-workspaces"
mise exec -- ./bin/symphony --port 4000 ../WORKFLOW.md
```

Expected result: the terminal logs and dashboard show the issue as claimed and running. The
workspace path includes the issue identifier, and the Linear issue gets one persistent
`## Codex Workpad` comment.

### 3. Ask `@linear` for a read-only progress check

```text
@linear Summarize the current status of the issue titled
"Docs: clarify local dashboard startup". Include its state, PR link if present,
and the latest unchecked items from the Codex Workpad comment.
```

Expected result: Linear reports whether the issue is still in progress, blocked, ready for human
review, or terminal. Use the workpad as the source of truth for what the agent has done and what is
left.

### 4. Review and merge

When the issue reaches `Human Review`, review the PR normally. If changes are needed, move the issue
to `Rework`. If it is approved, move it to `Merging`; Symphony will run the repo `land` flow and
move the issue toward completion according to `WORKFLOW.md`.

## Troubleshooting

- If no work starts, confirm `LINEAR_API_KEY`, `tracker.project_slug`, active issue state, and
  optional `LINEAR_ASSIGNEE`.
- If a workspace fails to bootstrap, inspect `hooks.after_create` output and
  `.codex/worktree_init.sh`.
- If Codex cannot update Linear, confirm the app-server session exposes Linear access. This repo's
  workflow expects either the Linear MCP integration or Symphony's `linear_graphql` tool.
- If the dashboard is unavailable, restart with `--port 4000` and check that no other local service
  is using that port.
- If an issue is terminal, Symphony should stop active work and clean the matching workspace.
