az_kv_get_secret() {
# ------------------------------------------------------------------------------
# Function: az_kv_get_secret
# Retrieve a secret value from Azure Key Vault.
#
# Usage:
#   az_kv_get_secret -k <keyvault_name> -n <secret_name>
#
# Example:
#   az_kv_get_secret -k "my-keyvault" -n "my-secret"
# ------------------------------------------------------------------------------
    local vault_name=""
    local secret_name=""

    # Reset OPTIND so getopts parses from $1 when function is called from a sourced script
    local OPTIND
    OPTIND=1
    while getopts "k:n:h" opt; do
        case ${opt} in
            k ) vault_name=$OPTARG ;;
            n ) secret_name=$OPTARG ;;
            h )
                echo "Usage: az_kv_get_secret -k <keyvault_name> -n <secret_name>"
                return 0
                ;;
            \? )
                echo "Invalid option: -$OPTARG" >&2
                return 1
                ;;
        esac
    done

    # Check if arguments are provided
    if [[ -z "$vault_name" || -z "$secret_name" ]]; then
        echo "Usage: az_kv_get_secret -k <keyvault_name> -n <secret_name>" >&2
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
        echo "Error: Could not retrieve secret '$secret_name' from vault '$vault_name'." >&2
        return 1
    else
        echo "$secret_value"
    fi
}

az_kv_upsert_secret() {
# ------------------------------------------------------------------------------
# Function: az_kv_upsert_secret
# Create or update a secret in Azure Key Vault.
#
# Usage:
#   az_kv_upsert_secret -s <subscription_id> -g <resource_group> -k <keyvault_name> -n <secret_name> -v <secret_value_or_file>
#
# Example:
#   az_kv_upsert_secret -s "00000000-0000-0000-0000-000000000000" \
#       -g "my-rg" -k "my-keyvault" -n "my-private-key" -v "~/.ssh/id_rsa"
#
# Requirements:
#   - Azure CLI (az) must be installed and logged in
#   - Sufficient permissions to read/write secrets in the target Key Vault
# ------------------------------------------------------------------------------
  local subscription_id=""
  local resource_group=""
  local kv_name=""
  local secret_name=""
  local secret_value_or_file=""

  # Reset OPTIND so getopts parses from $1 when function is called from a sourced script
  local OPTIND
  OPTIND=1
  while getopts "s:g:k:n:v:h" opt; do
    case ${opt} in
      s ) subscription_id=$OPTARG ;;
      g ) resource_group=$OPTARG ;;
      k ) kv_name=$OPTARG ;;
      n ) secret_name=$OPTARG ;;
      v ) secret_value_or_file=$OPTARG ;;
      h )
        echo "Usage: az_kv_upsert_secret -s <subscription_id> -g <resource_group> -k <keyvault_name> -n <secret_name> -v <secret_value_or_file>"
        return 0
        ;;
      \? )
        echo "Invalid option: -$OPTARG" >&2
        return 1
        ;;
    esac
  done

  # --- Validation ---
  if [[ -z "$subscription_id" || -z "$resource_group" || -z "$kv_name" || -z "$secret_name" || -z "$secret_value_or_file" ]]; then
    echo "Usage: az_kv_upsert_secret -s <subscription_id> -g <resource_group> -k <keyvault_name> -n <secret_name> -v <secret_value_or_file>" >&2
    return 1
  fi

  if ! command -v az >/dev/null 2>&1; then
    echo "Error: Azure CLI (az) is not installed or not in PATH." >&2
    return 2
  fi

  # --- Set subscription context ---
  az_set_subscription "$subscription_id" 

  # --- Check Key Vault existence ---
  if ! az keyvault show -n "$kv_name" -g "$resource_group" >/dev/null 2>&1; then
    echo "Error: Key Vault '$kv_name' not found in resource group '$resource_group'." >&2
    return 4
  fi

  local secret_value=""
  local is_file="false"

  # --- Detect if value is a file path ---
  if [[ -f "$secret_value_or_file" ]]; then
    is_file="true"
    # Read full file content safely (preserve newlines)
    secret_value=$(<"$secret_value_or_file")
  else
    secret_value="$secret_value_or_file"
  fi

  # --- Check if secret already exists ---
  if az keyvault secret show --vault-name "$kv_name" --name "$secret_name" >/dev/null 2>&1; then
    echo "🔁 Secret '$secret_name' exists — updating in Key Vault '$kv_name'..."
  else
    echo "🆕 Secret '$secret_name' does not exist — creating new secret in Key Vault '$kv_name'..."
  fi

  # --- Upload or update secret ---
  if [[ "$is_file" == "true" ]]; then
    # Use --file to properly upload multiline secrets
    az keyvault secret set --vault-name "$kv_name" --name "$secret_name" --file "$secret_value_or_file" >/dev/null 2>&1
  else
    az keyvault secret set --vault-name "$kv_name" --name "$secret_name" --value "$secret_value" >/dev/null 2>&1
  fi

  if [[ $? -eq 0 ]]; then
    echo "✅ Secret '$secret_name' successfully upserted in Key Vault '$kv_name'."
  else
    echo "❌ Failed to upsert secret '$secret_name' in Key Vault '$kv_name'." >&2
    return 5
  fi
}

az_kv_delete_secret() {
# ------------------------------------------------------------------------------
# Function: az_kv_delete_secret
# Delete a secret from Azure Key Vault.
#
# Usage:
#   az_kv_delete_secret -s <subscription_id> -g <resource_group> -k <keyvault_name> -n <secret_name>
#
# Example:
#   az_kv_delete_secret -s "00000000-0000-0000-0000-000000000000" \
#       -g "my-rg" -k "my-keyvault" -n "api-key"
#
# Requirements:
#   - Azure CLI (az) must be installed and logged in
#   - Sufficient permissions to delete secrets in the target Key Vault
# ------------------------------------------------------------------------------
  local subscription_id=""
  local resource_group=""
  local kv_name=""
  local secret_name=""

  # Reset OPTIND so getopts parses from $1 when function is called from a sourced script
  local OPTIND
  OPTIND=1
  while getopts "s:g:k:n:h" opt; do
    case ${opt} in
      s ) subscription_id=$OPTARG ;;
      g ) resource_group=$OPTARG ;;
      k ) kv_name=$OPTARG ;;
      n ) secret_name=$OPTARG ;;
      h )
        echo "Usage: az_kv_delete_secret -s <subscription_id> -g <resource_group> -k <keyvault_name> -n <secret_name>"
        return 0
        ;;
      \? )
        echo "Invalid option: -$OPTARG" >&2
        return 1
        ;;
    esac
  done

  # --- Validation ---
  if [[ -z "$subscription_id" || -z "$resource_group" || -z "$kv_name" || -z "$secret_name" ]]; then
    echo "Usage: az_kv_delete_secret -s <subscription_id> -g <resource_group> -k <keyvault_name> -n <secret_name>" >&2
    return 1
  fi

  if ! command -v az >/dev/null 2>&1; then
    echo "Error: Azure CLI (az) is not installed or not in PATH." >&2
    return 2
  fi

  # --- Set subscription context ---
  az_set_subscription "$subscription_id"

  # --- Check Key Vault existence ---
  if ! az keyvault show -n "$kv_name" -g "$resource_group" >/dev/null 2>&1; then
    echo "Error: Key Vault '$kv_name' not found in resource group '$resource_group'." >&2
    return 4
  fi

  # --- Check if secret exists ---
  if ! az keyvault secret show --vault-name "$kv_name" --name "$secret_name" >/dev/null 2>&1; then
    echo "⚠️ Secret '$secret_name' does not exist in Key Vault '$kv_name'."
    return 0
  fi

  echo "🗑️ Deleting secret '$secret_name' from Key Vault '$kv_name'..."
  az keyvault secret delete --vault-name "$kv_name" --name "$secret_name" >/dev/null 2>&1

  if [[ $? -eq 0 ]]; then
    echo "✅ Secret '$secret_name' successfully deleted from Key Vault '$kv_name'."
  else
    echo "❌ Failed to delete secret '$secret_name' from Key Vault '$kv_name'." >&2
    return 5
  fi
}

az_kv_help() {
  echo "Azure Key Vault Shell Utilities"
  echo "==============================="
  echo "Available functions:"
  echo ""
  echo "1. az_kv_get_secret"
  echo "   Retrieve a secret value from Azure Key Vault."
  echo "   Usage:   az_kv_get_secret -k <keyvault_name> -n <secret_name>"
  echo "   Example: az_kv_get_secret -k \"my-keyvault\" -n \"my-secret\""
  echo ""
  echo "2. az_kv_upsert_secret"
  echo "   Create or update a secret in Azure Key Vault."
  echo "   Usage:   az_kv_upsert_secret -s <subscription_id> -g <resource_group> -k <keyvault_name> -n <secret_name> -v <secret_value_or_file>"
  echo "   Example: az_kv_upsert_secret -s \"sub-id\" -g \"my-rg\" -k \"my-keyvault\" -n \"api-key\" -v \"super-secret-value\""
  echo ""
  echo "3. az_kv_delete_secret"
  echo "   Delete a secret from Azure Key Vault."
  echo "   Usage:   az_kv_delete_secret -s <subscription_id> -g <resource_group> -k <keyvault_name> -n <secret_name>"
  echo "   Example: az_kv_delete_secret -s \"sub-id\" -g \"my-rg\" -k \"my-keyvault\" -n \"api-key\""
  echo ""
}

