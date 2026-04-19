# Main transfer function
scp_pull() {
    local DB_FILE="$HOME/.ssh/pull_vault.db"
    local CONFIG_FILE="$HOME/.ssh/config"
    local LAST_HOST_FILE="$HOME/.ssh/.pull_last_host"
    touch "$DB_FILE"

    # 1. Resolve Hostname (Input or Cache)
    local INPUT_CONN="${1}" 
    local INPUT_KEY="${2}"
    
    [[ -f "$LAST_HOST_FILE" ]] && local PREV_HOST=$(cat "$LAST_HOST_FILE")
    
    local HOST_NAME="${INPUT_CONN#*@}"
    [[ -z "$HOST_NAME" ]] && HOST_NAME="${PREV_HOST}"

    if [[ -z "$HOST_NAME" ]]; then
        echo "Error: No hostname provided and no history found."
        echo "Usage: pull [user@host] [key_path]"
        return 1
    fi

    # 2. Load Metadata for this specific host
    local SAVED_ENTRY=$(grep "^${HOST_NAME}|" "$DB_FILE" | tail -n 1)
    if [[ -n "$SAVED_ENTRY" ]]; then
        IFS='|' read -r _ CACHED_REMOTE CACHED_LOCAL CACHED_USER CACHED_KEY <<< "$SAVED_ENTRY"
    fi

    # Set initial values for prompts
    local REMOTE_FILE="${CACHED_REMOTE:-/var/log/azure/Qualys.QualysAgentLinux/*.log}"
    local LOCAL_DEST="${CACHED_LOCAL:-./downloads}"
    local USER_NAME="${INPUT_CONN%@*}"
    [[ "$USER_NAME" == "$HOST_NAME" ]] && USER_NAME="${CACHED_USER:-azureuser}"
    local KEY_PATH="${INPUT_KEY:-$CACHED_KEY}"

    echo "--- Session: $HOST_NAME ---"

    # 3. Interactive Prompts
    read -p "Remote Source Path [$REMOTE_FILE]: " NEW_REMOTE
    REMOTE_FILE="${NEW_REMOTE:-$REMOTE_FILE}"

    read -p "Local Destination  [$LOCAL_DEST]: " NEW_LOCAL
    LOCAL_DEST="${NEW_LOCAL:-$LOCAL_DEST}"

    # 4. Environment Prep (Local dir + SSH Config)
    mkdir -p "$LOCAL_DEST"
    if ! grep -qW "Host $HOST_NAME" "$CONFIG_FILE" 2>/dev/null; then
        echo "Configuring SSH alias for $HOST_NAME..."
        {
            echo -e "\nHost $HOST_NAME\n    HostName $HOST_NAME\n    User $USER_NAME"
            [[ -n "$KEY_PATH" ]] && echo "    IdentityFile $KEY_PATH"
        } >> "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE"
    fi

    # 5. Execute Transfer
    echo "Executing: scp $HOST_NAME:$REMOTE_FILE -> $LOCAL_DEST"
    if scp "$HOST_NAME":"$REMOTE_FILE" "$LOCAL_DEST"; then
        # 6. Update Vault (Delete old record, add new)
        sed -i "/^${HOST_NAME}|/d" "$DB_FILE"
        echo "${HOST_NAME}|${REMOTE_FILE}|${LOCAL_DEST}|${USER_NAME}|${KEY_PATH}" >> "$DB_FILE"
        echo "${HOST_NAME}" > "$LAST_HOST_FILE"
        echo "Done."
    fi
}

# Helper to see your saved connections
scp_list() {
    local DB_FILE="$HOME/.ssh/pull_vault.db"
    if [[ -s "$DB_FILE" ]]; then
        echo -e "HOST\tREMOTE_PATH\tLOCAL_DEST\tUSER\tKEY"
        column -t -s '|' "$DB_FILE"
    else
        echo "Vault is empty."
    fi
}

# Main push function
scp_push() {
    local DB_FILE="$HOME/.ssh/pull_vault.db"
    local CONFIG_FILE="$HOME/.ssh/config"
    local LAST_HOST_FILE="$HOME/.ssh/.pull_last_host"
    touch "$DB_FILE"

    # 1. Resolve Hostname
    local INPUT_CONN="${1}" 
    [[ -f "$LAST_HOST_FILE" ]] && local PREV_HOST=$(cat "$LAST_HOST_FILE")
    local HOST_NAME="${INPUT_CONN#*@}"
    [[ -z "$HOST_NAME" ]] && HOST_NAME="${PREV_HOST}"

    if [[ -z "$HOST_NAME" ]]; then
        echo "Error: No hostname provided. Usage: push [user@host]"
        return 1
    fi

    # 2. Load Metadata (Reusing the same vault)
    local SAVED_ENTRY=$(grep "^${HOST_NAME}|" "$DB_FILE" | tail -n 1)
    if [[ -n "$SAVED_ENTRY" ]]; then
        IFS='|' read -r _ CACHED_REMOTE CACHED_LOCAL CACHED_USER CACHED_KEY <<< "$SAVED_ENTRY"
    fi

    # Set initial values (Push is Local -> Remote)
    local LOCAL_SRC="${CACHED_LOCAL:-./uploads}"
    local REMOTE_DEST="${CACHED_REMOTE:-/tmp/}"
    local USER_NAME="${INPUT_CONN%@*}"
    [[ "$USER_NAME" == "$HOST_NAME" ]] && USER_NAME="${CACHED_USER:-azureuser}"

    echo "--- Push Session: $HOST_NAME ---"

    # 3. Interactive Prompts
    read -p "Local Source Path [$LOCAL_SRC]: " NEW_LOCAL
    LOCAL_SRC="${NEW_LOCAL:-$LOCAL_SRC}"

    read -p "Remote Destination [$REMOTE_DEST]: " NEW_REMOTE
    REMOTE_DEST="${NEW_REMOTE:-$REMOTE_DEST}"

    # 4. Preparation (Remote side)
    # We use ssh to ensure the remote directory exists before pushing
    echo "Ensuring remote directory exists..."
    ssh "$HOST_NAME" "mkdir -p $(dirname "$REMOTE_DEST")"

    # 5. Execute Transfer
    echo "Executing: scp $LOCAL_SRC -> $HOST_NAME:$REMOTE_DEST"
    if scp -r "$LOCAL_SRC" "$HOST_NAME":"$REMOTE_DEST"; then
        # 6. Update Vault
        sed -i "/^${HOST_NAME}|/d" "$DB_FILE"
        echo "${HOST_NAME}|${REMOTE_DEST}|${LOCAL_SRC}|${USER_NAME}|${CACHED_KEY}" >> "$DB_FILE"
        echo "${HOST_NAME}" > "$LAST_HOST_FILE"
        echo "Push complete."
    fi
}
