# Usage: tgsetup [ot|tf] [version]
# Example: tgsetup ot 1.7.0
# Example: tgsetup tf
terragrunt_setup() {
    local tool_type=$1
    local version=${2:-latest}
    local binary_path

    case "$tool_type" in
        ot|tofu|opentofu)
            echo "Switching Terragrunt engine to OpenTofu ($version)..."
            tofuenv install "$version"
            tofuenv use "$version"
            binary_path=$(which tofu)
            ;;
        tf|terraform)
            echo "Switching Terragrunt engine to Terraform ($version)..."
            tfenv install "$version"
            tfenv use "$version"
            binary_path=$(which terraform)
            ;;
        *)
            echo "Error: Use 'ot' (OpenTofu/tofuenv) or 'tf' (Terraform/tfenv)."
            return 1
            ;;
    esac

    # Validate binary and set Terragrunt path
    if [[ -x "$binary_path" ]]; then
        export TERRAGRUNT_TFPATH="$binary_path"
        echo -e "\033[1;32mDONE:\033[0m Terragrunt is now using: $($TERRAGRUNT_TFPATH --version | head -n 1)"
    else
        echo "Error: Could not locate or execute the binary at $binary_path."
        return 1
    fi
}
