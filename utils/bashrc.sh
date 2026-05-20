#!/bin/bash

# Resolve utils dir from this script's location (works for any checkout path).
# UTILS_ON_CONT overrides when utils is mounted elsewhere (e.g. in Docker).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${UTILS_ON_CONT:-${SCRIPT_DIR}}"
BASHRC="/etc/bash.bashrc"
UTIL_EXCLUDES=(bashrc.sh source_all_sh.sh)

# shellcheck source=/dev/null
source "${UTILS_DIR}/source_all_sh.sh"

echo "🔧 Updating $BASHRC and setting up utility scripts..."
echo "📁 Utils directory: $UTILS_DIR"

source "${PROJECT_ENV_ON_CONT}"

register_all_sh "$BASHRC" "$UTILS_DIR" "${UTIL_EXCLUDES[@]}"
source_all_sh "$UTILS_DIR" "${UTIL_EXCLUDES[@]}"

# Source the updated bashrc
echo "🔄 Reloading $BASHRC..."
source "$BASHRC"

echo "🔧 Updating Git Config..."
switch_to_azure
echo "✅ Git config done"

TF_RC="${UTILS_DIR}/credentials.tfrc.json"
if [[ -f "${TF_RC}" ]]; then
    echo "🔧 Setting terrafrom cloud and Sclar ..."

    mkdir -p /root/.terraform.d/
    cat "${TF_RC}" > /root/.terraform.d/credentials.tfrc.json

    echo "✅ Terrafrom cloud and Sclar done"
else
    echo "❌ Warning: $TF_RC not found, skipping."
fi

# apt install -y pipx
# pipx install pre-commit
# pipx ensurepath
# source ~/.bashrc
# pre-commit --version

echo "✅ pre commit installed"

echo "✅ All done!"
