# Function to ensure Azure login and set subscription
az_set_subscription() {
    local subscription_id="$1"

    # Check if a subscription ID was provided
    if [[ -z "$subscription_id" ]]; then
        echo "❌ Error: No subscription ID provided."
        echo "Usage: set_azure_subscription <subscription_id>"
        return 1
    fi

    echo "🔍 Checking Azure CLI login status..."
    
    # Check if the user is logged in
    if ! az account show >/dev/null 2>&1; then
        echo "⚠️  Not logged into Azure. Logging in using device code..."
        az login --use-device-code
        if ! az account show  >/dev/null 2>&1; then
            echo "❌ Azure login failed. Please try again."
            return 1
        fi
        echo "✅ Successfully logged into Azure."
    else
        echo "✅ Already logged into Azure."
    fi

    echo "🔧 Setting subscription to: $subscription_id"
    if ! az account set --subscription "$subscription_id" >/dev/null 2>&1; then
        echo "❌ Failed to set subscription. Please check if the subscription ID is correct and accessible."
        return 1
    fi

    echo "✅ Subscription set successfully."
    az account show --query "{Name:name, ID:id, Tenant:tenantId}" -o table
}


az_kv_upsert_secret() {
# ------------------------------------------------------------------------------
# Function: az_kv_upsert_secret
# Create or update a secret in Azure Key Vault.
#
# Usage:
#   az_kv_upsert_secret <subscription_id> <resource_group> <keyvault_name> <secret_name> <secret_value_or_file>
#
# Example:
#   az_kv_upsert_secret "00000000-0000-0000-0000-000000000000" \
#       "my-rg" "my-keyvault" "my-private-key" "~/.ssh/id_rsa"
#
#   az_kv_upsert_secret "00000000-0000-0000-0000-000000000000" \
#       "my-rg" "my-keyvault" "api-key" "super-secret-token"
#
# Requirements:
#   - Azure CLI (az) must be installed and logged in
#   - Sufficient permissions to read/write secrets in the target Key Vault
# --------------------------------------------------------------------------
# Example calls:
#
# Inline string:
# az_kv_upsert_secret "sub-id" "rg-demo" "kv-demo" "api-token" "abcd1234"
#
# File-based (e.g. private key):
# az_kv_upsert_secret "sub-id" "rg-demo" "kv-demo" "ssh-private-key" "~/.ssh/id_ed25519"
# --------------------------------------------------------------------------
  local subscription_id="$1"
  local resource_group="$2"
  local kv_name="$3"
  local secret_name="$4"
  local secret_value_or_file="$5"

  # --- Validation ---
  if [[ -z "$subscription_id" || -z "$resource_group" || -z "$kv_name" || -z "$secret_name" || -z "$secret_value_or_file" ]]; then
    echo "Usage: az_kv_upsert_secret <subscription_id> <resource_group> <keyvault_name> <secret_name> <secret_value_or_file>" >&2
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

# Run on specific instance
# run_vmss_script \
#   -r myResourceGroup \
#   -v myScaleSet \
#   -i 3 \
#   -p ./install-nginx.sh

# Run on any instance (auto-select first)
# run_vmss_script \
#   -r myResourceGroup \
#   -v myScaleSet \
#   -p ./install-nginx.sh

run_vmss_script() {

    local RESOURCE_GROUP=""
    local VMSS_NAME=""
    local INSTANCE_ID=""
    local SCRIPT_PATH=""

    # Reset OPTIND so getopts parses from $1 when function is called from a sourced script
    OPTIND=1
    # Parse flags
    while getopts "r:v:i:p:h" opt; do
        case ${opt} in
            r ) RESOURCE_GROUP=$OPTARG ;;
            v ) VMSS_NAME=$OPTARG ;;
            i ) INSTANCE_ID=$OPTARG ;;
            p ) SCRIPT_PATH=$OPTARG ;;
            h )
                echo "Usage: run_vmss_script -r <resource-group> -v <vmss-name> [-i instance-id] -p <script-path>"
                return 0
                ;;
            \? )
                echo "Invalid option: -$OPTARG"
                return 1
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "$RESOURCE_GROUP" || -z "$VMSS_NAME" || -z "$SCRIPT_PATH" ]]; then
        echo "ERROR: Missing required parameters."
        echo "Usage: run_vmss_script -r <resource-group> -v <vmss-name> [-i instance-id] -p <script-path>"
        return 1
    fi

    if [[ ! -f "$SCRIPT_PATH" ]]; then
        echo "ERROR: Script file not found: $SCRIPT_PATH"
        return 1
    fi

    # If instance ID not provided pick first instance
    if [[ -z "$INSTANCE_ID" ]]; then
        echo "No instance ID provided. Selecting first VMSS instance..."

        INSTANCE_ID=$(az vmss list-instances \
            --resource-group "$RESOURCE_GROUP" \
            --name "$VMSS_NAME" \
            --query "[0].instanceId" \
            -o tsv)

        if [[ -z "$INSTANCE_ID" ]]; then
            echo "ERROR: Could not determine VMSS instance."
            return 1
        fi
    fi

    echo "Executing script on:"
    echo "Resource Group : $RESOURCE_GROUP"
    echo "VMSS           : $VMSS_NAME"
    echo "Instance ID    : $INSTANCE_ID"
    echo "Script         : $SCRIPT_PATH"
    echo ""

    az vmss run-command invoke \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VMSS_NAME" \
        --instance-id "$INSTANCE_ID" \
        --command-id RunShellScript \
        --scripts @"$SCRIPT_PATH"
}

az_set_access_token(){
  export AZURE_ACCESS_TOKEN="$(az account get-access-token --resource https://management.azure.com/ --query accessToken -o tsv)"
  echo "Azure access token set in environment variable AZURE_ACCESS_TOKEN"
}