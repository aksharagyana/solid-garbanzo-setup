#!/usr/bin/env bash

# Resolve paths from this script's location (works for any checkout path).
if [[ -n "${ZSH_VERSION:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
UTILS_DIR="${UTILS_ON_MAC:-${PROJECT_ROOT}/utils}"
ONLOCAL_DIR="${SCRIPT_DIR}"
ENV_SH="${ENV_SH:-${HOME}/code/env.sh}"

# shellcheck source=/dev/null
source "${UTILS_DIR}/source_all_sh.sh"

# shellcheck source=/dev/null
source "${ENV_SH}"

# Load all onlocal helpers except this entrypoint and docker_env.sh
# (docker_env.sh generates .env on source — run it explicitly when needed).
source_all_sh "${ONLOCAL_DIR}" setup.sh docker_env.sh
