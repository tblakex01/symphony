# Symphony

Symphony turns project work into isolated, autonomous implementation runs, allowing teams to manage
work instead of supervising coding agents.

[![Symphony demo video preview](.github/media/symphony-demo-poster.jpg)](.github/media/symphony-demo.mp4)

_In this [demo video](.github/media/symphony-demo.mp4), Symphony monitors a Linear board for work and spawns agents to handle the tasks. The agents complete the tasks and provide proof of work: CI status, PR review feedback, complexity analysis, and walkthrough videos. When accepted, the agents land the PR safely. Engineers do not need to supervise Codex; they can manage the work at a higher level._

> [!WARNING]
> Symphony is a low-key engineering preview for testing in trusted environments.

## Running Symphony

### Requirements

Symphony works best in codebases that have adopted
[harness engineering](https://openai.com/index/harness-engineering/). Symphony is the next step --
moving from managing coding agents to managing work that needs to get done.

### Option 1. Make your own

Tell your favorite coding agent to build Symphony in a programming language of your choice:

> Implement Symphony according to the following spec:
> https://github.com/openai/symphony/blob/main/SPEC.md

### Option 2. Use our experimental reference implementation

Check out [elixir/README.md](elixir/README.md) for instructions on how to set up your environment
and run the Elixir-based Symphony implementation. You can also ask your favorite coding agent to
help with the setup:

> Set up Symphony for my repository based on
> https://github.com/openai/symphony/blob/main/elixir/README.md

## Local Development

This repository now includes a repo-local [WORKFLOW.md](WORKFLOW.md) configured for running the
Elixir reference implementation against this checkout.

### Prerequisites

- [mise](https://mise.jdx.dev/) for Erlang/Elixir toolchain management
- [GitHub CLI](https://cli.github.com/) authenticated for the writable fork
- a Linear personal API key in `.env` or exported as `LINEAR_API_KEY`
- optional:
  - `LINEAR_ASSIGNEE` to restrict polling to a specific assignee
  - `SYMPHONY_WORKSPACE_ROOT` to choose where per-issue workspaces are created

### Start a local development instance

Use the repo helper as the canonical local startup path:

```bash
git clone https://github.com/tblakex01/symphony.git
cd symphony
scripts/run_symphony_dashboard.sh
```

The repo-level `WORKFLOW.md` uses the existing [`.codex/worktree_init.sh`](.codex/worktree_init.sh)
bootstrap script, so each issue workspace clones this repository and runs the Elixir setup flow
automatically.

The helper loads `.env`, verifies Linear/GitHub/mise/remotes with
[`scripts/preflight.sh`](scripts/preflight.sh), builds the Elixir CLI, and starts the observability
UI at `http://127.0.0.1:4000/`.

For debugging, the raw dashboard command is:

```bash
cd symphony/elixir
mise exec -- ./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --port 4000 \
  ../WORKFLOW.md
```

`WORKFLOW.md` enables worker network access and writable access to `$SYMPHONY_WORKSPACE_ROOT` so
spawned agents can push branches, create or update PRs, read PR checks and review comments, and
finish the Linear handoff without a parent session doing GitHub work manually.

### Development loop

- edit the implementation under [elixir/](elixir)
- validate targeted changes with `mise exec -- mix test ...`
- run the broader gate with `make -C elixir all`

---

## License

This project is licensed under the [Apache License 2.0](LICENSE).
