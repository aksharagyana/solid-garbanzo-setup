# Auto-install Terraform versions required by project .terraform-version files.
export TENV_AUTO_INSTALL="${TENV_AUTO_INSTALL:-true}"

# function tf_ls_workspace() {
#      terraform workspace list
# }

function tfv() {
    #  tfi
     terraform fmt -recursive 
     terraform validate
}

# Usage:
#   tfi [-d directory] [-b backend-config]...
#   tfi -backend-config=backend_config/nonlive.conf
#   tfi -d ./infra -b backend_config/nonlive.conf -- -upgrade
tfi() {
    local TF_DIR="$(pwd)"
    local BACKEND_CONFIGS=()
    local PASSTHROUGH=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d)
                [[ -n "${2:-}" ]] || { echo "Error: -d requires a directory." >&2; return 1; }
                TF_DIR="$2"
                shift 2
                ;;
            -b|-backend-config)
                [[ -n "${2:-}" ]] || { echo "Error: $1 requires a backend config path." >&2; return 1; }
                BACKEND_CONFIGS+=("$2")
                shift 2
                ;;
            -backend-config=*)
                BACKEND_CONFIGS+=("${1#-backend-config=}")
                shift
                ;;
            -h|--help)
                echo "Usage: tfi [-d directory] [-b backend-config | -backend-config=path]... [-- terraform-init-args...]"
                echo "  -d  Terraform working directory (default: current directory)"
                echo "  -b  Backend config file (repeatable; also accepts -backend-config=path)"
                echo "  --  Pass remaining args through to terraform init (e.g. -upgrade, -reconfigure)"
                return 0
                ;;
            --)
                shift
                PASSTHROUGH+=("$@")
                break
                ;;
            *)
                PASSTHROUGH+=("$1")
                shift
                ;;
        esac
    done

    if [[ ! -d "$TF_DIR" ]]; then
        echo "Error: Directory '$TF_DIR' does not exist." >&2
        return 1
    fi

    _tf_ensure_ready "$TF_DIR" || return 1

    local ORIGINAL_DIR="$(pwd)"
    cd "$TF_DIR" || {
        echo "Error: Could not change to directory $TF_DIR" >&2
        return 1
    }

    local INIT_OPTS=()
    local cfg
    for cfg in "${BACKEND_CONFIGS[@]}"; do
        if [[ -f "$cfg" ]]; then
            INIT_OPTS+=("-backend-config=$cfg")
        else
            echo "Warning: Backend config '$cfg' not found in $TF_DIR" >&2
            INIT_OPTS+=("-backend-config=$cfg")
        fi
    done

    echo "=== Running terraform init in: $TF_DIR ==="
    if [[ ${#INIT_OPTS[@]} -gt 0 || ${#PASSTHROUGH[@]} -gt 0 ]]; then
        echo "Options: ${INIT_OPTS[*]} ${PASSTHROUGH[*]}"
    fi

    terraform init "${INIT_OPTS[@]}" "${PASSTHROUGH[@]}"
    local code=$?

    cd "$ORIGINAL_DIR" >/dev/null
    return $code
}


# Usage:
#   tfplan [-d directory] [-v var-file]... [-t target]... [extra terraform plan args...]
#   tfplan -v var1.tfvars -out=tf_plan.out
#   tfplan -d ./infra -v env/nonlive.tfvars -t module.vnet -out=plans/nonlive.out
tfplan() {
    local TF_DIR="$(pwd)"
    local VAR_FILES=()
    local TARGETS=()
    local PASSTHROUGH=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d)
                [[ -n "${2:-}" ]] || { echo "Error: -d requires a directory." >&2; return 1; }
                TF_DIR="$2"
                shift 2
                ;;
            -v|-var-file)
                [[ -n "${2:-}" ]] || { echo "Error: $1 requires a var file path." >&2; return 1; }
                VAR_FILES+=("$2")
                shift 2
                ;;
            -var-file=*)
                VAR_FILES+=("${1#-var-file=}")
                shift
                ;;
            -t|-target)
                [[ -n "${2:-}" ]] || { echo "Error: $1 requires a target." >&2; return 1; }
                TARGETS+=("$2")
                shift 2
                ;;
            -target=*)
                TARGETS+=("${1#-target=}")
                shift
                ;;
            -h|--help)
                echo "Usage: tfplan [-d directory] [-v var-file]... [-t target]... [terraform-plan-args...]"
                echo "  -d  Terraform working directory (default: current directory)"
                echo "  -v  Variable file (.tfvars) - can be used multiple times"
                echo "  -t  Target resource or module - can be used multiple times"
                echo "  Any other args are passed to terraform plan (e.g. -out=tf_plan.out, -destroy)"
                return 0
                ;;
            --)
                shift
                PASSTHROUGH+=("$@")
                break
                ;;
            *)
                PASSTHROUGH+=("$1")
                shift
                ;;
        esac
    done

    if [[ ! -d "$TF_DIR" ]]; then
        echo "Error: Directory '$TF_DIR' does not exist." >&2
        return 1
    fi

    local TF_OPTS=()
    local VAR_FILE TARGET
    for VAR_FILE in "${VAR_FILES[@]}"; do
        if [[ -f "$VAR_FILE" ]]; then
            TF_OPTS+=("-var-file=$VAR_FILE")
        else
            echo "Warning: Variable file '$VAR_FILE' does not exist, skipping." >&2
        fi
    done

    for TARGET in "${TARGETS[@]}"; do
        TF_OPTS+=("-target=$TARGET")
    done

    _tf_ensure_ready "$TF_DIR" || return 1

    local ORIGINAL_DIR="$(pwd)"
    cd "$TF_DIR" || {
        echo "Error: Could not change to directory $TF_DIR" >&2
        return 1
    }

    tfv || {
        cd "$ORIGINAL_DIR" >/dev/null
        return 1
    }

    echo "=== Running terraform plan in: $TF_DIR ==="
    if [[ ${#TF_OPTS[@]} -gt 0 || ${#PASSTHROUGH[@]} -gt 0 ]]; then
        echo "Options: ${TF_OPTS[*]} ${PASSTHROUGH[*]}"
    else
        echo "Options: (none)"
    fi

    terraform plan "${TF_OPTS[@]}" "${PASSTHROUGH[@]}"
    local code=$?

    cd "$ORIGINAL_DIR" >/dev/null
    return $code
}

_tf_pager() {
    if [[ -n "${PAGER:-}" ]]; then
        $PAGER
    elif command -v less >/dev/null 2>&1; then
        less -R
    elif command -v more >/dev/null 2>&1; then
        more
    else
        cat
    fi
}

# Usage:
#   tfshow [plan-file] [-d directory] [-e] [--no-pager] [terraform show args...]
#   tfshow                         # page through tf_plan.out in less
#   tfshow -e tf_plan.out          # open plan in vi ($EDITOR)
#   tfshow -json tf_plan.out       # page JSON output
tfshow() {
    local TF_DIR="$(pwd)"
    local PLAN_FILE="tf_plan.out"
    local PASSTHROUGH=()
    local USE_EDITOR=false
    local NO_PAGER=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d)
                [[ -n "${2:-}" ]] || { echo "Error: -d requires a directory." >&2; return 1; }
                TF_DIR="$2"
                shift 2
                ;;
            -e|--edit)
                USE_EDITOR=true
                shift
                ;;
            --no-pager)
                NO_PAGER=true
                shift
                ;;
            -h|--help)
                echo "Usage: tfshow [plan-file] [-d directory] [-e] [--no-pager] [terraform-show-args...]"
                echo "  plan-file   Saved plan to display (default: tf_plan.out)"
                echo "  -d          Terraform working directory (default: current directory)"
                echo "  -e          Open in \$EDITOR (default: vi) instead of paging"
                echo "  --no-pager  Print full output without less/vi"
                echo "  Other args are passed to terraform show (e.g. -json, -no-color)"
                return 0
                ;;
            --)
                shift
                PASSTHROUGH+=("$@")
                break
                ;;
            -*)
                PASSTHROUGH+=("$1")
                shift
                ;;
            *)
                PLAN_FILE="$1"
                shift
                ;;
        esac
    done

    if [[ ! -d "$TF_DIR" ]]; then
        echo "Error: Directory '$TF_DIR' does not exist." >&2
        return 1
    fi

    _tf_ensure_ready "$TF_DIR" || return 1

    local ORIGINAL_DIR="$(pwd)"
    cd "$TF_DIR" || {
        echo "Error: Could not change to directory $TF_DIR" >&2
        return 1
    }

    if [[ ! -f "$PLAN_FILE" ]]; then
        echo "Error: Plan file '$PLAN_FILE' not found in $TF_DIR" >&2
        cd "$ORIGINAL_DIR" >/dev/null
        return 1
    fi

    local code=0
    local tmp editor

    if [[ "$USE_EDITOR" == true ]]; then
        tmp="$(mktemp "${TMPDIR:-/tmp}/tfshow.XXXXXX")"
        terraform show "${PASSTHROUGH[@]}" "$PLAN_FILE" > "$tmp" || code=$?
        if [[ $code -eq 0 ]]; then
            editor="${EDITOR:-${VISUAL:-vi}}"
            "$editor" "$tmp"
            code=$?
        fi
        rm -f "$tmp"
    elif [[ "$NO_PAGER" == true ]] || [[ ! -t 1 ]]; then
        terraform show "${PASSTHROUGH[@]}" "$PLAN_FILE"
        code=$?
    else
        echo "=== Showing plan: $PLAN_FILE (less: q=quit, / = search) ===" >&2
        terraform show "${PASSTHROUGH[@]}" "$PLAN_FILE" | _tf_pager
        code=${PIPESTATUS[0]}
    fi

    cd "$ORIGINAL_DIR" >/dev/null
    return $code
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

_tf_install_version() {
    local version="$1"

    if ! tenv terraform list | grep -q "${version}"; then
        echo "[*] Installing Terraform ${version}..."
        tenv terraform install "${version}" || return 1
    fi
}

_tf_ensure_ready() {
    local dir="${1:-$PWD}"

    if ! command -v tenv >/dev/null 2>&1; then
        echo "Error: tenv not found in PATH." >&2
        return 1
    fi

    _tf_ensure_terraform || return 1
    export PATH="$(tenv update-path)"

    local version
    version="$(_tf_resolve_version "$dir")" || {
        echo "Error: No Terraform version found. Add .terraform-version or run: tfsetup -v <version>" >&2
        return 1
    }

    _tf_install_version "$version" || return 1
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

    echo "[-] Setting up Terraform v${version} via tenv..."

    _tf_install_version "$version" || return 1

    # Select the version globally (writes ${TENV_ROOT}/Terraform/version)
    tenv terraform use "${version}" || return 1

    _tf_ensure_terraform || return 1
    export PATH="$(tenv update-path)"

    echo "[✓] Success! Active version is now:"
    terraform --version
}
