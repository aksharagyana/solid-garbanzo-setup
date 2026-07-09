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

# ================================================
# Tenant-wide Azure inventory helpers
# ================================================
if [[ -n "${ZSH_VERSION:-}" ]]; then
    _AZ_UTILS_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
else
    _AZ_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
_AZ_LIST_RESOURCE_TYPES_PY="${_AZ_UTILS_DIR}/az_list_resource_types.py"

_az_require_python() {
    if [[ ! -f "$_AZ_LIST_RESOURCE_TYPES_PY" ]]; then
        echo "Error: Python helper not found: $_AZ_LIST_RESOURCE_TYPES_PY" >&2
        return 1
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        echo "Error: python3 is required but not installed" >&2
        return 1
    fi
}

# List unique resource types deployed across the current Azure tenant.
# Uses Azure CLI login credentials and Resource Graph (--allow-partial-scopes).
# Not limited to the CLI default subscription.
az_list_resource_types() {
    if ! _az_require_python; then
        return 1
    fi

    local -a py_args=()

    OPTIND=1
    while getopts "f:o:qh" opt; do
        case $opt in
            f) py_args+=(-f "$OPTARG") ;;
            o) py_args+=(-o "$OPTARG") ;;
            q) py_args+=(-q) ;;
            h)
                echo "Usage: az_list_resource_types [-f lines|txt|json] [-o <output_file>] [-q]"
                echo "  List unique Azure resource types deployed tenant-wide."
                echo ""
                echo "  Examples:"
                echo "    az_list_resource_types"
                echo "    az_list_resource_types -f json -o resource-types.json"
                echo ""
                echo "  Uses the logged-in Azure CLI user and tenant."
                echo "  Queries all subscriptions the user can access (not only the default subscription)."
                return 0
                ;;
            *) echo "Invalid option"; return 1 ;;
        esac
    done

    (cd "$_AZ_UTILS_DIR" && python3 "$_AZ_LIST_RESOURCE_TYPES_PY" "${py_args[@]}")
}