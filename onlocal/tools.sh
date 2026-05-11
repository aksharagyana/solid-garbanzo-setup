install_or_upgrade_dev_tools() {

    local PACKAGES=(
        "azure-cli"
        "Azure/kubelogin/kubelogin"
        "kubectl"
        "helm"
        "k9s"
    )

    echo "=== Checking Homebrew ==="

    if ! command -v brew >/dev/null 2>&1; then
        echo "ERROR: Homebrew is not installed"
        return 1
    fi

    echo "=== Ensuring Homebrew PATH ==="

    export PATH="/opt/homebrew/bin:$PATH"

    # Persist for future shells
    if ! grep -q 'brew shellenv' ~/.zshrc 2>/dev/null; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
    fi

    eval "$(/opt/homebrew/bin/brew shellenv)"

    echo "=== Updating Homebrew metadata ==="

    brew update

    echo
    echo "=== Installing / Upgrading packages ==="

    local pkg
    local formula

    for pkg in "${PACKAGES[@]}"; do

        formula="$(basename "$pkg")"

        echo
        echo ">>> Processing: $pkg"

        # Install if missing
        if ! brew list --formula | grep -qx "$formula"; then

            echo "Installing $pkg..."

            if ! brew install "$pkg"; then
                echo "ERROR: Failed to install $pkg"
                continue
            fi

            echo "✓ Installed $pkg"

        else

            # Upgrade if outdated
            if brew outdated --formula | grep -qx "$formula"; then

                echo "Upgrading $pkg..."

                if ! brew upgrade "$pkg"; then
                    echo "ERROR: Failed to upgrade $pkg"
                    continue
                fi

                echo "✓ Upgraded $pkg"

            else
                echo "✓ Already latest: $pkg"
            fi
        fi
    done

    echo
    echo "=== Verifying binaries ==="

    local BINARIES=(
        az
        kubelogin
        kubectl
        helm
        k9s
    )

    local bin

    for bin in "${BINARIES[@]}"; do

        if command -v "$bin" >/dev/null 2>&1; then
            echo "✓ $bin -> $(which "$bin")"
        else
            echo "✗ $bin NOT FOUND"
        fi
    done

    echo
    echo "=== Installed Versions ==="

    echo
    az version 2>/dev/null | head -5 || true

    echo
    kubelogin --version 2>/dev/null || true

    echo
    kubectl version --client 2>/dev/null || true

    echo
    helm version 2>/dev/null || true

    echo
    k9s version 2>/dev/null || true

    echo
    echo "=== COMPLETE ==="
}