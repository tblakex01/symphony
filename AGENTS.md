# Symphony Repository

This repository has two roles:

1. The root repo is the product and documentation surface (`README.md`, `SPEC.md`, repo-level `WORKFLOW.md`, `.codex/skills/*`).
2. [`elixir/`](./elixir) is the current reference implementation.

## Scope Rules

- Prefer the single canonical path for behavior and docs. Do not add parallel setup flows when the repo already has one.
- Keep repo-level Symphony workflow guidance in the root `WORKFLOW.md`.
- Keep Elixir runtime and implementation details in [`elixir/`](./elixir).
- When working inside [`elixir/`](./elixir), also follow [`elixir/AGENTS.md`](./elixir/AGENTS.md). The subtree instructions there are stricter and more specific.

## Repository Conventions

- Keep the implementation aligned with [`SPEC.md`](./SPEC.md) where practical.
- If behavior changes materially, update the matching docs in the same change:
  - [`README.md`](./README.md) for repo-level usage
  - [`WORKFLOW.md`](./WORKFLOW.md) for orchestration contract changes
  - [`elixir/README.md`](./elixir/README.md) for Elixir runtime/setup changes
- Reuse the existing repo-local Codex skills in [`.codex/skills`](./.codex/skills) instead of duplicating prompt logic in new files.
- Reuse [`.codex/worktree_init.sh`](./.codex/worktree_init.sh) as the bootstrap path for cloned workspaces unless the bootstrap contract itself is being changed.

## Local Development

- The root [`WORKFLOW.md`](./WORKFLOW.md) is the repo-local workflow used to run Symphony against this repository.
- The expected local run flow is:
  1. install the Elixir toolchain with `mise`
  2. build from [`elixir/`](./elixir)
  3. launch `./bin/symphony ../WORKFLOW.md`
- Keep root usage instructions accurate enough that a fresh local checkout can be brought up without reading source code.

## Validation

- For root workflow or Elixir config contract changes, run targeted Elixir tests that exercise `SymphonyElixir.Workflow` / `SymphonyElixir.Config`.
- For Elixir implementation changes, prefer targeted tests while iterating and `make all` before handoff when the change touches runtime behavior broadly.
