#!/bin/bash

# Resolve project root from this script's location (works for any checkout path).
# UTILS_ON_CONT overrides utils dir when utils is mounted elsewhere (e.g. in Docker).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"
UTILS_DIR="${UTILS_ON_CONT:-${PROJECT_ROOT}/utils}"
BASHRC="/etc/bash.bashrc"

# shellcheck source=/dev/null
source "${UTILS_DIR}/source_all_sh.sh"

echo "🔧 Updating $BASHRC and setting up utility scripts..."
echo "📁 Utils directory: $UTILS_DIR"

source "${PROJECT_ENV_ON_CONT}"

shopt -s nullglob
util_scripts=("$UTILS_DIR"/*.sh)
shopt -u nullglob

if [[ ${#util_scripts[@]} -eq 0 ]]; then
    echo "❌ Warning: No .sh files found in $UTILS_DIR"
fi

for SCRIPT_PATH in "${util_scripts[@]}"; do
    script="$(basename "$SCRIPT_PATH")"

    # Infrastructure helper — not a container utility.
    [[ "$script" == "source_all_sh.sh" ]] && continue

    echo "⚙️  Processing $script..."

    # Make the script executable
    chmod u+x "$SCRIPT_PATH"

    # Add source line to bashrc if not already present
    SOURCE_LINE="source $SCRIPT_PATH"
    if ! grep -Fxq "$SOURCE_LINE" "$BASHRC"; then
        echo "$SOURCE_LINE" >> "$BASHRC"
        echo "✅ Added source line for $script"
    else
        echo "ℹ️  Source line for $script already exists in $BASHRC"
    fi
done

source_all_sh "$UTILS_DIR"

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
