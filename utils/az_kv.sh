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

# Remediation: enable soft delete + purge protection (irreversible once purge protection is on).

_KV_POLICY_DELETION_PROTECTION_ID="0b60c0b2-2dc2-4e1c-b5c9-abbed971de53"

function _kv_show_help() {
    local func="$1"
    case $func in
        kv_remediate_deletion_protection)
            echo "Usage: kv_remediate_deletion_protection (-i <vault_id> | -g <resource_group> -n <vault_name>) [-s <subscription>] [-yq]"
            echo "  Remediate Azure Policy 'Key vaults should have deletion protection enabled'"
            echo "  (${_KV_POLICY_DELETION_PROTECTION_ID}) by enabling purge protection"
            echo "  (soft delete is required and is on by default for modern vaults)."
            echo ""
            echo "  Provide either:"
            echo "    -i  Full Key Vault ARM resource id"
            echo "        /subscriptions/.../resourceGroups/.../providers/Microsoft.KeyVault/vaults/<name>"
            echo "  or both:"
            echo "    -g  Resource group name"
            echo "    -n  Key Vault name"
            echo ""
            echo "  Optional:"
            echo "    -s  Subscription id or name (default: current az account, or from -i)"
            echo "    -y  Skip confirmation (purge protection cannot be turned off once enabled)"
            echo "    -q  Quiet — only print errors and final status"
            echo "    -h  Show this help"
            echo ""
            echo "Examples:"
            echo "  kv_remediate_deletion_protection -i /subscriptions/.../resourceGroups/rg/providers/Microsoft.KeyVault/vaults/mykv"
            echo "  kv_remediate_deletion_protection -g rg-app -n kv-app -y"
            ;;
        kv_show_deletion_protection)
            echo "Usage: kv_show_deletion_protection (-i <vault_id> | -g <resource_group> -n <vault_name>) [-s <subscription>]"
            echo "  Show soft-delete / purge-protection state for a Key Vault (policy ${_KV_POLICY_DELETION_PROTECTION_ID})."
            ;;
        *)
            echo "Unknown function"
            ;;
    esac
}

function _kv_require_az() {
    if ! command -v az >/dev/null 2>&1; then
        echo "Error: Azure CLI (az) is required but not installed" >&2
        return 1
    fi

    if ! az account show >/dev/null 2>&1; then
        echo "Error: not logged in to Azure CLI (az login)" >&2
        return 1
    fi
}

# Parse Key Vault ARM id into subscription / resource group / name.
# Sets: KV_SUBSCRIPTION_ID, KV_RESOURCE_GROUP, KV_NAME, KV_ID
function _kv_parse_vault_id() {
    local id="${1%/}"
    KV_SUBSCRIPTION_ID=""
    KV_RESOURCE_GROUP=""
    KV_NAME=""
    KV_ID=""

    local id_lc
    id_lc="$(printf '%s' "$id" | tr '[:upper:]' '[:lower:]')"

    case "$id_lc" in
        /subscriptions/*/resourcegroups/*/providers/microsoft.keyvault/vaults/*) ;;
        *)
            echo "Error: invalid Key Vault resource id: $id" >&2
            echo "Expected: /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<name>" >&2
            return 1
            ;;
    esac

    # Portable path-segment extraction (bash + zsh)
    KV_SUBSCRIPTION_ID="$(printf '%s' "$id" | cut -d'/' -f3)"
    KV_RESOURCE_GROUP="$(printf '%s' "$id" | cut -d'/' -f5)"
    KV_NAME="$(printf '%s' "$id" | cut -d'/' -f9)"

    if [[ -z "$KV_SUBSCRIPTION_ID" || -z "$KV_RESOURCE_GROUP" || -z "$KV_NAME" ]]; then
        echo "Error: invalid Key Vault resource id: $id" >&2
        return 1
    fi

    KV_ID="/subscriptions/${KV_SUBSCRIPTION_ID}/resourceGroups/${KV_RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KV_NAME}"
}

# Resolve targeting args into KV_SUBSCRIPTION_ID / KV_RESOURCE_GROUP / KV_NAME / KV_ID.
# Usage: _kv_resolve_target <vault_id> <resource_group> <vault_name> <subscription>
function _kv_resolve_target() {
    local vault_id="$1"
    local resource_group="$2"
    local vault_name="$3"
    local subscription="$4"

    KV_SUBSCRIPTION_ID=""
    KV_RESOURCE_GROUP=""
    KV_NAME=""
    KV_ID=""

    if [[ -n "$vault_id" ]]; then
        if [[ -n "$resource_group" || -n "$vault_name" ]]; then
            echo "Error: when -i is set, do not also pass -g / -n" >&2
            return 1
        fi
        if ! _kv_parse_vault_id "$vault_id"; then
            return 1
        fi
        [[ -n "$subscription" ]] && KV_SUBSCRIPTION_ID="$subscription"
        return 0
    fi

    if [[ -z "$resource_group" || -z "$vault_name" ]]; then
        echo "Error: provide -i <vault_id>, or both -g <resource_group> and -n <vault_name>" >&2
        return 1
    fi

    KV_RESOURCE_GROUP="$resource_group"
    KV_NAME="$vault_name"
    if [[ -n "$subscription" ]]; then
        KV_SUBSCRIPTION_ID="$subscription"
    else
        KV_SUBSCRIPTION_ID="$(az account show --query id -o tsv 2>/dev/null)" || true
    fi

    if [[ -z "$KV_SUBSCRIPTION_ID" ]]; then
        echo "Error: could not determine subscription; pass -s <subscription>" >&2
        return 1
    fi

    KV_ID="/subscriptions/${KV_SUBSCRIPTION_ID}/resourceGroups/${KV_RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KV_NAME}"
}

function _kv_norm_bool() {
    # Azure may return true/false/null/None/empty — map to true|false|""
    local v
    v="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    case "$v" in
        true) printf 'true' ;;
        false|null|none|"") printf 'false' ;;
        *) printf '' ;;
    esac
}

function _kv_read_protection_state() {
    # Sets: KV_SOFT_DELETE, KV_PURGE_PROTECTION (true/false)
    # az --query '[a,b]' -o tsv emits one value per line.
    local -a show_args=(
        keyvault show
        --name "$KV_NAME"
        --resource-group "$KV_RESOURCE_GROUP"
        --query "[properties.enableSoftDelete, properties.enablePurgeProtection]"
        --output tsv
    )
    [[ -n "$KV_SUBSCRIPTION_ID" ]] && show_args+=(--subscription "$KV_SUBSCRIPTION_ID")

    local out soft purge
    if ! out="$(az "${show_args[@]}" 2>/dev/null)"; then
        echo "Error: Key Vault not found or inaccessible: ${KV_ID:-$KV_NAME}" >&2
        return 1
    fi

    soft="$(printf '%s\n' "$out" | sed -n '1p')"
    purge="$(printf '%s\n' "$out" | sed -n '2p')"
    KV_SOFT_DELETE="$(_kv_norm_bool "$soft")"
    KV_PURGE_PROTECTION="$(_kv_norm_bool "$purge")"
}

# ================================================
# Show soft-delete / purge-protection state
# ================================================
kv_show_deletion_protection() {
    local vault_id="" resource_group="" vault_name="" subscription=""

    OPTIND=1
    while getopts "i:g:n:s:h" opt; do
        case $opt in
            i) vault_id="$OPTARG" ;;
            g) resource_group="$OPTARG" ;;
            n) vault_name="$OPTARG" ;;
            s) subscription="$OPTARG" ;;
            h) _kv_show_help "kv_show_deletion_protection"; return 0 ;;
            *) echo "Invalid option"; _kv_show_help "kv_show_deletion_protection"; return 1 ;;
        esac
    done

    if ! _kv_require_az; then
        return 1
    fi

    if ! _kv_resolve_target "$vault_id" "$resource_group" "$vault_name" "$subscription"; then
        _kv_show_help "kv_show_deletion_protection"
        return 1
    fi

    if ! _kv_read_protection_state; then
        return 1
    fi

    local compliant="false"
    if [[ "$KV_SOFT_DELETE" == "true" && "$KV_PURGE_PROTECTION" == "true" ]]; then
        compliant="true"
    fi

    echo "vaultId:            $KV_ID"
    echo "enableSoftDelete:   ${KV_SOFT_DELETE:-unknown}"
    echo "enablePurgeProtection: ${KV_PURGE_PROTECTION:-unknown}"
    echo "policyCompliant:    $compliant  (${_KV_POLICY_DELETION_PROTECTION_ID})"
}

# ================================================
# Remediate deletion protection (soft delete + purge protection)
# ================================================
kv_remediate_deletion_protection() {
    local vault_id="" resource_group="" vault_name="" subscription=""
    local assume_yes="false" quiet="false"

    OPTIND=1
    while getopts "i:g:n:s:yqh" opt; do
        case $opt in
            i) vault_id="$OPTARG" ;;
            g) resource_group="$OPTARG" ;;
            n) vault_name="$OPTARG" ;;
            s) subscription="$OPTARG" ;;
            y) assume_yes="true" ;;
            q) quiet="true" ;;
            h) _kv_show_help "kv_remediate_deletion_protection"; return 0 ;;
            *) echo "Invalid option"; _kv_show_help "kv_remediate_deletion_protection"; return 1 ;;
        esac
    done

    if ! _kv_require_az; then
        return 1
    fi

    if ! _kv_resolve_target "$vault_id" "$resource_group" "$vault_name" "$subscription"; then
        _kv_show_help "kv_remediate_deletion_protection"
        return 1
    fi

    if ! _kv_read_protection_state; then
        return 1
    fi

    [[ "$quiet" != "true" ]] && {
        echo "Key Vault: $KV_ID"
        echo "  enableSoftDelete:      ${KV_SOFT_DELETE:-unknown}"
        echo "  enablePurgeProtection: ${KV_PURGE_PROTECTION:-unknown}"
        echo "Policy: ${_KV_POLICY_DELETION_PROTECTION_ID} (deletion protection)"
    }

    if [[ "$KV_SOFT_DELETE" == "true" && "$KV_PURGE_PROTECTION" == "true" ]]; then
        [[ "$quiet" != "true" ]] && echo "Already compliant — no changes required."
        return 0
    fi

    if [[ "$KV_SOFT_DELETE" != "true" ]]; then
        echo "Error: soft delete is not enabled on '$KV_NAME'." >&2
        echo "Modern az CLI cannot toggle soft delete on update (vaults created after 2019-09-01 enable it by default)." >&2
        return 1
    fi

    if [[ "$assume_yes" != "true" ]]; then
        echo ""
        echo "This will enable purge protection (soft delete is already on)."
        echo "Purge protection cannot be disabled once enabled."
        printf "Continue? [y/N] "
        local reply
        read -r reply
        if [[ ! "$reply" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            return 1
        fi
    fi

    local -a update_args=(
        keyvault update
        --name "$KV_NAME"
        --resource-group "$KV_RESOURCE_GROUP"
        --enable-purge-protection true
    )
    [[ -n "$KV_SUBSCRIPTION_ID" ]] && update_args+=(--subscription "$KV_SUBSCRIPTION_ID")

    [[ "$quiet" != "true" ]] && echo "Enabling purge protection on Key Vault..."
    if ! az "${update_args[@]}" --output none; then
        echo "Error: failed to update Key Vault '$KV_NAME'" >&2
        return 1
    fi

    if ! _kv_read_protection_state; then
        return 1
    fi

    if [[ "$KV_SOFT_DELETE" == "true" && "$KV_PURGE_PROTECTION" == "true" ]]; then
        [[ "$quiet" != "true" ]] && echo "Remediation complete — vault is policy-compliant."
        return 0
    fi

    echo "Error: update finished but vault is still non-compliant (softDelete=${KV_SOFT_DELETE:-unknown}, purgeProtection=${KV_PURGE_PROTECTION:-unknown})" >&2
    return 1
}

# ================================================
# Help Command
# ================================================
_kv_help() {
    echo "Azure Key Vault Helper Functions"
    echo ""
    echo "Available functions:"
    echo "  kv_remediate_deletion_protection - Enable soft delete + purge protection"
    echo "  kv_show_deletion_protection      - Show soft delete / purge protection state"
    echo "  kv_help                          - Show this help"
    echo ""
    echo "Policy: Key vaults should have deletion protection enabled"
    echo "  ${_KV_POLICY_DELETION_PROTECTION_ID}"
    echo "  https://www.azadvertizer.net/azpolicyadvertizer/${_KV_POLICY_DELETION_PROTECTION_ID}.html"
    echo ""
    echo "Use -h with any function for detailed usage."
    echo ""
    echo "Example:"
    echo "  source utils/keyvault.sh"
    echo "  kv_show_deletion_protection -g my-rg -n my-kv"
    echo "  kv_remediate_deletion_protection -i /subscriptions/.../resourceGroups/my-rg/providers/Microsoft.KeyVault/vaults/my-kv -y"
    echo "  kv_remediate_deletion_protection -g my-rg -n my-kv -s <subscription-id>"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _kv_help
fi

