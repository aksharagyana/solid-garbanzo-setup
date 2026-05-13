az_key_get_secret() {
    local vault_name=$1
    local secret_name=$2

    # Check if arguments are provided
    if [[ -z "$vault_name" || -z "$secret_name" ]]; then
        echo "Usage: get_azure_secret <vault_name> <secret_name>"
        return 1
    fi

    # Retrieve the secret value
    # --query 'value' -o tsv ensures we get raw text without quotes or JSON formatting
    local secret_value=$(az keyvault secret show \
        --name "$secret_name" \
        --vault-name "$vault_name" \
        --query 'value' \
        -o tsv 2>/dev/null)

    if [[ -z "$secret_value" ]]; then
        echo "Error: Could not retrieve secret '$secret_name' from vault '$vault_name'."
        return 1
    else
        echo "$secret_value"
    fi
}
