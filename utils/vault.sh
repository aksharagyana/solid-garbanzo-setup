export VAULT_START="secret"

vault_tree() {
  local path=$1
  # List keys and handle the case where a path might not be listable
  vault kv list -format=json "$path" 2>/dev/null | jq -r '.[]' | while read -r key; do
    if [[ "$key" == */ ]]; then
      # If it ends in a slash, it's a folder: recurse
      vault_tree "$path$key"
    else
      # If no slash, it's a secret: print the full path
      echo "$path$key"
    fi
  done
}

vault_key_list() {
    local start_path=$1

    # Default to root "secret/" if no path provided
    if [ -z "$start_path" ]; then
        echo "No path provided, starting from 'secret/'..."
        start_path="secret/"
    fi

    # Ensure path ends with a slash for the list command
    [[ "$start_path" != */ ]] && start_path="$start_path/"

    _recurse_vault() {
        local current_path=$1
        # List keys; 2>/dev/null hides errors if a path isn't a folder or lacks permissions
        local keys=$(vault kv list -format=json "$current_path" 2>/dev/null | jq -r '.[]' 2>/dev/null)

        for key in $keys; do
            if [[ "$key" == */ ]]; then
                # If it's a folder, dive deeper
                _recurse_vault "$current_path$key"
            else
                # If it's a secret, print the full path
                echo "$current_path$key"
            fi
        done
    }

    _recurse_vault "$start_path"
}

# Get a specific key value from HashiCorp Vault
vault_get_secret() {

    local PATH_NAME=$1

    if [ -z "$PATH_NAME" ]; then
        echo "Usage: vault_get_secret <path> [key]"
        return 1
    fi

    vault read "$PATH_NAME"

}
