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
- GitHub CLI (`gh`) authenticated for the writable fork.
- A Linear personal API key in `.env` or exported as `LINEAR_API_KEY`.
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
- `codex.turn_sandbox_policy` must allow spawned workers to use the workspace root and GitHub
  network access. This repo's workflow uses `$SYMPHONY_WORKSPACE_ROOT` as the writable root,
  `readOnlyAccess: fullAccess` for local auth/config reads, and `networkAccess: true` for PR
  publishing and review checks.
- The Markdown body is the prompt template rendered for each Linear issue.

Do not create a second workflow file for the same behavior unless you are deliberately changing the
workflow contract. Keep business rules and state-transition policy in one place.

## Run Symphony Locally

Use the helper as the canonical local path. It loads `.env`, defaults
`SYMPHONY_WORKSPACE_ROOT` to `./symphony-workspaces` when unset, verifies Linear/GitHub/mise/remotes,
builds the Elixir CLI, and starts the dashboard.

```bash
cd symphony
scripts/run_symphony_dashboard.sh
```

The dashboard is available at `http://127.0.0.1:4000/`.

To run only the preflight:

```bash
cd symphony
scripts/preflight.sh
```

For debugging, the helper's raw equivalent is:

```bash
cd symphony
set -a
source .env
set +a
export SYMPHONY_WORKSPACE_ROOT="${SYMPHONY_WORKSPACE_ROOT:-$PWD/symphony-workspaces}"
cd elixir
mise trust
mise install
mise exec -- mix setup
mise exec -- mix build
mise exec -- ./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --port 4000 \
  ../WORKFLOW.md
```

To restrict polling to one assignee, put `LINEAR_ASSIGNEE=<linear-user-or-bot-id>` in `.env` before
running the helper.

The acknowledgement flag is required by the local CLI because Symphony launches Codex without the
usual interactive guardrails.

## Automation Preflight

`scripts/preflight.sh` fails fast before a demo run if any required automation dependency is
missing:

- `LINEAR_API_KEY` is exported and accepted by Linear's GraphQL API.
- `origin` is a writable GitHub fork, not `openai/symphony`.
- `upstream`, when configured, points to `openai/symphony`.
- `gh auth status` works for GitHub.
- `git ls-remote origin HEAD` and a `git push --dry-run` to a temporary branch both succeed.
- `mise` is available and the Elixir `mise.toml` is trusted.
- dashboard port `4000` is free, unless `SYMPHONY_DASHBOARD_PORT` chooses another port.
- root `WORKFLOW.md` includes the network-enabled worker sandbox contract.

If preflight passes, spawned workers should be able to implement, validate, push branches, create or
update PRs, read PR checks/comments, attach PRs to Linear, and move issues to `Human Review`
without parent-session intervention.

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
cd symphony
scripts/run_symphony_dashboard.sh
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
- If preflight fails GitHub auth, run `gh auth login` for the account that can write to the fork.
- If preflight fails the push dry run, confirm `origin` points to the fork and run
  `gh auth setup-git` if Git credential helper integration is missing.
- If a workspace fails to bootstrap, inspect `hooks.after_create` output and
  `.codex/worktree_init.sh`.
- If Codex cannot update Linear, confirm the app-server session exposes Symphony's
  `linear_graphql` tool and that `LINEAR_API_KEY` is loaded into the Symphony process.
- If a worker implements the change but cannot push or inspect PR feedback, rerun
  `scripts/preflight.sh`; the usual causes are missing `gh` auth, a read-only `origin`, blocked
  network access, or a worker sandbox that no longer includes `$SYMPHONY_WORKSPACE_ROOT` and
  `networkAccess: true`.
- If the dashboard is unavailable, restart with `--port 4000` and check that no other local service
  is using that port.
- If an issue is terminal, Symphony should stop active work and clean the matching workspace.
