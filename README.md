# solid-garbanzo-setup

Personal dev-environment setup: shell utilities for cloud and infra work, plus macOS helpers for Docker-based development.

## Quick start

### macOS (local)

1. Clone this repo anywhere (path is not hardcoded).
2. Create `~/code/env.sh` with your machine-specific variables (`CODE_ON_MAC`, `UTILS_ON_MAC`, `GITHUB_TOKEN`, etc.).
3. Source the local setup:

```bash
source /path/to/solid-garbanzo-setup/onlocal/setup.sh
```

4. Generate a Docker env file when needed:

```bash
source onlocal/docker_env.sh   # writes .env from selected env vars
```

### Docker container

Inside a dev container, run the bootstrap script to register and load all utilities:

```bash
bash /path/to/solid-garbanzo-setup/bashrc.sh
```

Required environment variables:

| Variable | Purpose |
|----------|---------|
| `PROJECT_ENV_ON_CONT` | Path to the project env file inside the container |
| `UTILS_ON_CONT` | (Optional) Override utils mount path; defaults to `<repo>/utils` |

## Project layout

| Path | Purpose |
|------|---------|
| [`utils/`](utils/) | Shared shell functions — Azure, Terraform, git, ngrok, Vault, Helm, etc. |
| [`bashrc.sh`](bashrc.sh) | Container bootstrap: auto-discovers and sources every `utils/*.sh` |
| [`onlocal/`](onlocal/) | macOS-only helpers — Docker dev containers, DNS, ACR, AI tools |

### Utility scripts (`utils/`)

Each file covers one topic. Current scripts:

`az.sh` · `az_kv.sh` · `az_sa_blob.sh` · `gchr.sh` · `gitcmd.sh` · `helm.sh` · `ngrok.sh` · `ot.sh` · `pre-commit.sh` · `scp.sh` · `terragunt_setup.sh` · `tf.sh` · `util.sh` · `vault.sh`

**Adding a new utility:** drop a `*.sh` file in `utils/`. No changes to `bashrc.sh` are needed — it picks up all `*.sh` files automatically (except `source_all_sh.sh`, the shared loader).

**Adding a new local helper:** drop a `*.sh` file in `onlocal/`. `onlocal/setup.sh` picks it up automatically (excludes `setup.sh` and `docker_env.sh`).

### Local helpers (`onlocal/`)

| Script | Purpose |
|--------|---------|
| `setup.sh` | Entry point — sources all onlocal scripts |
| `docker_util.sh` | Dev containers (`dev_go`, `dev_python`, `dev_debian`, `dev_node`) and Docker build helpers |
| `docker_env.sh` | Generates `.env` for Docker from host environment variables |
| `dns.sh` | DNS utilities |
| `acr.sh` | Azure Container Registry helpers |
| `ai.sh` | AI tooling |
| `tools.sh` | Miscellaneous local tools |

## graphify

This repo supports [graphify](https://graphify.net/) for codebase navigation. The knowledge graph lives in `graphify-out/` (gitignored — regenerate locally):

```bash
graphify update .
```

See [`AGENTS.md`](AGENTS.md) for agent/AI assistant rules when working with this repo.

## License

Private personal setup — not intended for public distribution.
