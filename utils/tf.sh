# Auto-install Terraform versions required by project .terraform-version files.
export TENV_AUTO_INSTALL="${TENV_AUTO_INSTALL:-true}"

# function tf_ls_workspace() {
#      terraform workspace list
# }

function tfv() {
     tfi
     terraform fmt -recursive 
     terraform validate
}

function tfi() {
     terraform init
}


function tfplan() {
     tfv
     terraform plan
}


# function tfapply() {
#      tfv
#      terraform apply
# }

# Reusable function to run terraform apply with external var files and targets
# Usage:
#   tfapply -d ./terraform-dir -v var1.tfvars -v var2.tfvars -t module.example_resource -t another_module
#   tfapply -v var1.tfvars -v var2.tfvars
#   tfapply -t module.example_resource
#   tfapply -d ./my-infra

tfapply() {
    # Default values
    local TF_DIR="$(pwd)"
    local VAR_FILES=()
    local TARGETS=()
    local AUTO_APPROVE=true   # Set to false if you want manual confirmation

    # Parse command-line options
    while getopts ":d:v:t:h" opt; do
        case "$opt" in
            d) TF_DIR="$OPTARG" ;;
            v) VAR_FILES+=("$OPTARG") ;;
            t) TARGETS+=("$OPTARG") ;;
            h)
                echo "Usage: tfapply [-d directory] [-v var-file]... [-t target]..."
                echo "  -d  Terraform working directory (default: current directory)"
                echo "  -v  Variable file (.tfvars) - can be used multiple times"
                echo "  -t  Target resource or module - can be used multiple times"
                echo "  -h  Show this help"
                return 0
                ;;
            \?)
                echo "Error: Invalid option '-$OPTARG'" >&2
                echo "Run 'tfapply -h' for usage." >&2
                return 1
                ;;
            :)
                echo "Error: Option '-$OPTARG' requires an argument." >&2
                return 1
                ;;
        esac
    done

    # Ensure the directory exists
    if [ ! -d "$TF_DIR" ]; then
        echo "Error: Directory '$TF_DIR' does not exist." >&2
        return 1
    fi

    # Build Terraform options safely using an array
    local TF_OPTS=()

    # Add variable files
    for VAR_FILE in "${VAR_FILES[@]}"; do
        if [ -f "$VAR_FILE" ]; then
            TF_OPTS+=("-var-file=$VAR_FILE")
        else
            echo "Warning: Variable file '$VAR_FILE' does not exist, skipping." >&2
        fi
    done

    # Add targets
    for TARGET in "${TARGETS[@]}"; do
        TF_OPTS+=("-target=$TARGET")
    done

    # Change to the Terraform directory
    local ORIGINAL_DIR="$(pwd)"
    cd "$TF_DIR" || { 
        echo "Error: Could not change to directory $TF_DIR" >&2
        return 1
    }

    # Check if Terraform is initialized
    if [ ! -d ".terraform" ] || ! terraform validate &>/dev/null; then
        echo "Terraform not initialized in $TF_DIR. Running terraform init..."
        tfv || { 
            echo "Error: terraform init failed." >&2
            cd "$ORIGINAL_DIR" >/dev/null
            return 1
        }
    fi

    echo "=== Running terraform apply in: $TF_DIR ==="
    if [ ${#TF_OPTS[@]} -gt 0 ]; then
        echo "Options: ${TF_OPTS[*]}"
    else
        echo "Options: (none)"
    fi

    # Run terraform apply
    terraform apply "${TF_OPTS[@]}"


    # Return to original directory
    cd "$ORIGINAL_DIR" >/dev/null
}


# ─────────────────────────────────────────────────────────────
# Interactive Terraform workspace switcher (copy-paste safe)
# Highlights the active workspace and lets you press Enter to stay
# ─────────────────────────────────────────────────────────────
tfws() {
    # Store original IFS to restore later
    local IFS=$'\n'

    # Check if terraform is available and we are in a TF dir
    if ! command -v terraform >/dev/null 2>&1; then
        echo "Error: terraform not found in PATH" >&2
        return 1
    fi

    # Get current workspace (works even if .terraform is missing)
    local current
    current=$(terraform workspace show 2>/dev/null || echo "default")

    # Get full list of workspaces (one per line, no asterisks)
    local workspaces
    workspaces=$(terraform workspace list 2>/dev/null | sed 's/^\*\{0,1\} //; s/^[[:space:]]*//; s/[[:space:]]*$//' | sort)

    if [[ -z "$workspaces" ]]; then
        echo "No workspaces found." >&2
        return 1
    fi

    echo -e "Current workspace: \033[1;32;4m$current\033[0m"
    echo "Available workspaces:"
    echo

    # Print list with current one highlighted in green
    while IFS= read -r ws; do
        if [[ "$ws" == "$current" ]]; then
            printf "  \033[1;32m➤ %s\033[0m  (current)\n" "$ws"
        else
            printf "    %s\n" "$ws"
        fi
    done <<< "$workspaces"

    echo

    # If fzf is installed → super fast fuzzy selection
    if command -v fzf >/dev/null 2>&1; then
        selected=$(printf "%s\n" $workspaces | fzf --height=10 --prompt="Switch to workspace (Enter to keep '$current'): " --query="$current" --select-1)
        # If user pressed Esc or Ctrl-C → keep current
        [[ -z "$selected" ]] && selected="$current"
    else
        # Classic input method
        read -p "Enter workspace name (or press Enter to stay on '$current'): " selected
        # If user pressed Enter only → keep current
        [[ -z "$selected" ]] && selected="$current"
    fi

    # Final validation (in case of typo when not using fzf)
    if ! grep -Fxq "$selected" <<< "$workspaces"; then
        echo -e "\nError: Workspace '$selected' does not exist." >&2
        return 1
    fi

    # Switch only if needed
    if [[ "$selected" != "$current" ]]; then
        echo -e "\nSwitching to workspace: \033[1;34m$selected\033[0m"
        terraform workspace select "$selected"
        local code=$?
        [[ $code -ne 0 ]] && return $code
    else
        echo -e "\nStaying on workspace: \033[1;32m$selected\033[0m"
    fi

    # Final confirmation
    echo -e "Current workspace: \033[1;32m$(terraform workspace show 2>/dev/null)\033[0m"
}

_tf_resolve_version() {
    local dir="${1:-$PWD}"
    local tenv_root="${TENV_ROOT:-${HOME}/.tenv}"

    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/.terraform-version" ]]; then
            tr -d '[:space:]' < "$dir/.terraform-version"
            return 0
        fi
        if [[ -f "$dir/.tfswitchrc" ]]; then
            tr -d '[:space:]' < "$dir/.tfswitchrc"
            return 0
        fi
        dir="$(dirname "$dir")"
    done

    if [[ -f "$tenv_root/Terraform/version" ]]; then
        tr -d '[:space:]' < "$tenv_root/Terraform/version"
        return 0
    fi

    return 1
}

_tf_ensure_terraform() {
    # Prefer tenv's package proxy — it handles .terraform-version and other resolution rules.
    if [[ -x /usr/bin/terraform ]]; then
        rm -f /usr/local/bin/terraform
        if command -v tenv >/dev/null 2>&1; then
            export PATH="$(tenv update-path)"
        fi
        command -v terraform >/dev/null 2>&1 && return 0
    fi

    if command -v terraform >/dev/null 2>&1; then
        return 0
    fi

    # Restore the package proxy if tenv was installed via dpkg but the binary was removed.
    if command -v dpkg >/dev/null 2>&1 && dpkg -L tenv 2>/dev/null | grep -qxF /usr/bin/terraform; then
        apt-get install --reinstall -y tenv >/dev/null 2>&1 && command -v terraform >/dev/null 2>&1 && return 0
    fi

    local tenv_root="${TENV_ROOT:-${HOME}/.tenv}"
    local proxy="/usr/local/bin/terraform"

    mkdir -p "$(dirname "$proxy")"
    cat > "$proxy" <<'WRAPPER'
#!/usr/bin/env bash
TENV_ROOT="${TENV_ROOT:-$HOME/.tenv}"
export TENV_AUTO_INSTALL="${TENV_AUTO_INSTALL:-true}"

_tf_resolve() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/.terraform-version" ]]; then
            tr -d '[:space:]' < "$dir/.terraform-version"
            return 0
        fi
        if [[ -f "$dir/.tfswitchrc" ]]; then
            tr -d '[:space:]' < "$dir/.tfswitchrc"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    if [[ -f "$TENV_ROOT/Terraform/version" ]]; then
        tr -d '[:space:]' < "$TENV_ROOT/Terraform/version"
        return 0
    fi
    return 1
}

version="$(_tf_resolve)" || {
    echo "Error: No Terraform version resolved (run tfsetup -v <version>)." >&2
    exit 1
}

bin="$TENV_ROOT/Terraform/$version/terraform"
if [[ ! -x "$bin" ]]; then
    if [[ "$TENV_AUTO_INSTALL" == true ]] && command -v tenv >/dev/null 2>&1; then
        tenv terraform install "$version" || exit 1
    else
        echo "Error: Terraform ${version} is not installed. Run: tenv terraform install ${version}" >&2
        exit 1
    fi
fi
exec "$bin" "$@"
WRAPPER
    chmod +x "$proxy"
}

tfsetup() {
    local version=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--version)
                version="$2"
                shift 2
                ;;
            *)
                echo "Error: Unknown argument '$1'"
                echo "Usage: tfsetup -v <version>"
                return 1
                ;;
        esac
    done

    # Validate that a version was provided
    if [[ -z "$version" ]]; then
        echo "Error: Missing required terraform version."
        echo "Usage: tfsetup -v <version>"
        return 1
    fi

    if ! command -v tenv >/dev/null 2>&1; then
        echo "Error: tenv not found in PATH." >&2
        return 1
    fi

    echo "[-] Setting up Terraform v${version} via tenv..."

    # Install the version if it is not already cached
    if ! tenv terraform list | grep -q "${version}"; then
        echo "[*] Version ${version} not found locally. Installing..."
        tenv terraform install "${version}" || return 1
    fi

    # Select the version globally (writes ${TENV_ROOT}/Terraform/version)
    tenv terraform use "${version}" || return 1

    # Keep tenv's /usr/bin/terraform proxy on PATH; recreate it if an older tfsetup removed it
    _tf_ensure_terraform || return 1
    export PATH="$(tenv update-path)"

    echo "[✓] Success! Active version is now:"
    terraform --version
}
