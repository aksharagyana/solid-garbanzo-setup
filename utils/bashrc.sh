#!/bin/bash

# List your utility script filenames here (space-separated)
UTIL_SCRIPTS=("envvars.sh" "tf.sh" "az.sh" "util.sh" "gitcmd.sh" "gchr.sh" "pre-commit.sh" "ngrok.sh" "terragunt_setup.sh" "ot.sh" "scp.sh" "az_sa_blob.sh")

# Base directory for utility scripts
UTILS_DIR="/code/utils"
BASHRC="/etc/bash.bashrc"

echo "🔧 Updating $BASHRC and setting up utility scripts..."

for script in "${UTIL_SCRIPTS[@]}"; do
    SCRIPT_PATH="$UTILS_DIR/$script"

    if [[ -f "$SCRIPT_PATH" ]]; then
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
    else
        echo "❌ Warning: $SCRIPT_PATH not found, skipping."
    fi
done

# Source the updated bashrc
echo "🔄 Reloading $BASHRC..."
source "$BASHRC"

echo "🔧 Updating Git Config..."
switch_to_azure
echo "✅ Git config done"

echo "🔧 Setting terrafrom cloud and Sclar ..."

mkdir -p /root/.terraform.d/
cat /code/utils/credentials.tfrc.json > /root/.terraform.d/credentials.tfrc.json


echo "✅ Terrafrom cloud and Sclar done"

# apt install -y pipx
# pipx install pre-commit
# pipx ensurepath
# source ~/.bashrc
# pre-commit --version

echo "✅ pre commit installed"

echo "✅ All done!"
