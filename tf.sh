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
