# Initialize
function oti() {
     tofu init
}

# Validate and Format
function otv() {
     oti
     tofu fmt -recursive 
     tofu validate
}

# Plan
function otplan() {
     otv
     tofu plan
}

# Apply
function otapply() {
     otv
     tofu apply
}

# ─────────────────────────────────────────────────────────────
# Interactive OpenTofu workspace switcher
# ─────────────────────────────────────────────────────────────
otws() {
    local IFS=$'\n'

    if ! command -v tofu >/dev/null 2>&1; then
        echo "Error: tofu not found in PATH" >&2
        return 1
    fi

    local current
    current=$(tofu workspace show 2>/dev/null || echo "default")

    local workspaces
    workspaces=$(tofu workspace list 2>/dev/null | sed 's/^\*\{0,1\} //; s/^[[:space:]]*//; s/[[:space:]]*$//' | sort)

    if [[ -z "$workspaces" ]]; then
        echo "No workspaces found." >&2
        return 1
    fi

    echo -e "Current Tofu workspace: \033[1;35;4m$current\033[0m" # Purple highlight for Tofu
    echo "Available workspaces:"
    echo

    while IFS= read -r ws; do
        if [[ "$ws" == "$current" ]]; then
            printf "  \033[1;35m➤ %s\033[0m  (current)\n" "$ws"
        else
            printf "    %s\n" "$ws"
        fi
    done <<< "$workspaces"

    echo

    if command -v fzf >/dev/null 2>&1; then
        selected=$(printf "%s\n" $workspaces | fzf --height=10 --prompt="Switch Tofu workspace (Enter to keep '$current'): " --query="$current" --select-1)
        [[ -z "$selected" ]] && selected="$current"
    else
        read -p "Enter workspace name (or press Enter to stay on '$current'): " selected
        [[ -z "$selected" ]] && selected="$current"
    fi

    if ! grep -Fxq "$selected" <<< "$workspaces"; then
        echo -e "\nError: Workspace '$selected' does not exist." >&2
        return 1
    fi

    if [[ "$selected" != "$current" ]]; then
        echo -e "\nSwitching to workspace: \033[1;34m$selected\033[0m"
        tofu workspace select "$selected"
    else
        echo -e "\nStaying on workspace: \033[1;35m$selected\033[0m"
    fi

    echo -e "Current workspace: \033[1;35m$(tofu workspace show 2>/dev/null)\033[0m"
}