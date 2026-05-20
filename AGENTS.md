# solid-garbanzo-setup

Personal dev-environment setup: shell utilities for cloud/infra work, plus local macOS helpers for Docker-based dev.

## Layout

| Path | Purpose |
|------|---------|
| `utils/` | Shared shell functions (Azure, Terraform, git, ngrok, etc.) — one topic per `*.sh` file |
| `utils/bashrc.sh` | Container bootstrap: registers and sources all `utils/*.sh` into `/etc/bash.bashrc` |
| `onlocal/` | macOS-only helpers (Docker dev containers, DNS, ACR, AI tools) — source via `onlocal/setup.sh` |

## Shell utilities

- Add a new utility by dropping a `*.sh` file in `utils/`. No edits to `utils/bashrc.sh` are needed — it auto-discovers every `utils/*.sh`.
- Add a new local helper by dropping a `*.sh` file in `onlocal/`. `onlocal/setup.sh` auto-discovers them (excludes `setup.sh` and `docker_env.sh`).
- Both `utils/bashrc.sh` and `onlocal/setup.sh` share `utils/source_all_sh.sh` for directory-wide sourcing (`source_all_sh` on host, `register_all_sh` + `source_all_sh` in container).
- `utils/bashrc.sh` resolves paths from its own location, so the repo can live anywhere on disk.
- In Docker, set `UTILS_ON_CONT` when `utils/` is mounted outside the project root (see `onlocal/docker_env.sh`).
- `PROJECT_ENV_ON_CONT` must point at the project env file when running `utils/bashrc.sh` inside a container.

## Local setup (macOS)

Source `onlocal/setup.sh` to load all local helpers (`dev_go`, `dev_python`, `dev_debian`, …). It expects a personal `~/code/env.sh` (override with `ENV_SH`) containing machine-specific variables (`CODE_ON_MAC`, `UTILS_ON_MAC`, `GITHUB_TOKEN`, etc.).

Generate a Docker env file explicitly when needed (not run on every setup):

```bash
source onlocal/docker_env.sh   # writes .env from selected env vars
```

## graphify

This project has a knowledge graph at `graphify-out/` with god nodes, community structure, and cross-file relationships. `graphify-out/` is gitignored — regenerate locally with `graphify update .` (AST-only, no API cost).

Rules:
- ALWAYS read `graphify-out/GRAPH_REPORT.md` before reading source files, running grep/glob searches, or answering codebase questions. The graph is your primary map of the codebase.
- IF `graphify-out/wiki/index.md` EXISTS, navigate it instead of reading raw files
- For cross-module "how does X relate to Y" questions, prefer graph traversal over grep:
  - MCP (when active): `query_graph`, `get_node`, `shortest_path`
  - CLI: `graphify query "<question>"`, `graphify path "<A>" "<B>"`, `graphify explain "<concept>"`
- After modifying code, run `graphify update .` to keep the graph current.
