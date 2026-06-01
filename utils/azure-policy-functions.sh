#!/bin/bash
# ================================================
# Azure Policy Management - Flag-based Reusable Functions
# ================================================
# ================================================
# Common Argument Parser
# ================================================
function _parse_args() {
    local func_name="$1"; shift
    POLICY_ID=""
    ASSIGNMENT_ID=""
    FILE_PATH=""
    SCOPE=""
    OUTPUT_FILE=""

    while getopts "p:a:f:s:o:h" opt; do
        case $opt in
            p) POLICY_ID="$OPTARG" ;;
            a) ASSIGNMENT_ID="$OPTARG" ;;
            f) FILE_PATH="$OPTARG" ;;
            s) SCOPE="$OPTARG" ;;
            o) OUTPUT_FILE="$OPTARG" ;;
            h) _show_help "$func_name"; exit 0 ;;
            *) echo "Invalid option"; _show_help "$func_name"; exit 1 ;;
        esac
    done
}

function _show_help() {
    local func="$1"
    case $func in
        az_policy_definition_download)
            echo "Usage: az_policy_definition_download -p <policy_id> [-o <output_file>]"
            echo "  -p  Policy Definition ID or Name"
            echo "  -o  Output JSON file path (optional)"
            ;;
        az_policy_assignment_download)
            echo "Usage: az_policy_assignment_download -a <assignment_id> [-o <output_file>]"
            echo "  -a  Policy Assignment ID or Name"
            echo "  -o  Output JSON file path (optional)"
            ;;
        az_policy_definition_deploy)
            echo "Usage: az_policy_definition_deploy -f <json_file> [-s <scope>]"
            echo "  -f  Local policy definition JSON file path"
            echo "  -s  Scope (Management Group ID or Subscription ID) - optional"
            ;;
        az_policy_assignment_deploy)
            echo "Usage: az_policy_assignment_deploy -f <json_file> [-s <scope>]"
            echo "  -f  Local policy assignment JSON file path"
            echo "  -s  Scope (e.g. /subscriptions/xxx) - recommended"
            ;;
        az_policy_definition_delete)
            echo "Usage: az_policy_definition_delete -p <policy_id> [-s <scope>]"
            echo "  -p  Policy Definition ID or Name"
            echo "  -s  Scope (Management Group) - optional"
            ;;
        az_policy_assignment_delete)
            echo "Usage: az_policy_assignment_delete -a <assignment_id> [-s <scope>]"
            echo "  -a  Policy Assignment ID or Name"
            echo "  -s  Scope - optional"
            ;;
        *)
            echo "Unknown function"
            ;;
    esac
}

# ================================================
# 1. Download Policy Definition
# ================================================
az_policy_definition_download() {
    _parse_args "${FUNCNAME[0]}" "$@"

    if [[ -z "$POLICY_ID" ]]; then
        echo "Error: -p <policy_id> is required"
        _show_help "${FUNCNAME[0]}"
        return 1
    fi

    local output="${OUTPUT_FILE:-${POLICY_ID##*/}.json}"

    echo "Downloading policy definition: $POLICY_ID"
    az policy definition show --id "$POLICY_ID" --output json > "$output"
    echo "Saved to: $output"
}

# ================================================
# 2. Download Policy Assignment
# ================================================
az_policy_assignment_download() {
    _parse_args "${FUNCNAME[0]}" "$@"

    if [[ -z "$ASSIGNMENT_ID" ]]; then
        echo "Error: -a <assignment_id> is required"
        _show_help "${FUNCNAME[0]}"
        return 1
    fi

    local output="${OUTPUT_FILE:-${ASSIGNMENT_ID##*/}.json}"

    echo "Downloading policy assignment: $ASSIGNMENT_ID"
    az policy assignment show --id "$ASSIGNMENT_ID" --output json > "$output"
    echo "Saved to: $output"
}

# ================================================
# 3. Deploy (Create/Update) Policy Definition - Idempotent
# ================================================
az_policy_definition_deploy() {
    _parse_args "${FUNCNAME[0]}" "$@"

    if [[ -z "$FILE_PATH" ]]; then
        echo "Error: -f <json_file> is required"
        _show_help "${FUNCNAME[0]}"
        return 1
    fi

    if [[ ! -f "$FILE_PATH" ]]; then
        echo "Error: File not found: $FILE_PATH"
        return 1
    fi

    local name
    name=$(jq -r '.name // .properties.name // empty' "$FILE_PATH")
    [[ -z "$name" ]] && name=$(basename "$FILE_PATH" .json)

    echo "Deploying policy definition: $name"

    local scope_arg=""
    [[ -n "$SCOPE" ]] && scope_arg="--management-group $SCOPE"

    if az policy definition show --name "$name" $scope_arg >/dev/null 2>&1; then
        echo "Policy exists → Updating..."
        az policy definition update \
            --name "$name" \
            $scope_arg \
            --rules "@$FILE_PATH" \
            --output none
    else
        echo "Policy does not exist → Creating..."
        az policy definition create \
            --name "$name" \
            $scope_arg \
            --rules "@$FILE_PATH" \
            --output none
    fi

    echo "Policy definition '$name' deployed successfully."
}

# ================================================
# 4. Deploy (Create/Update) Policy Assignment - Idempotent
# ================================================
az_policy_assignment_deploy() {
    _parse_args "${FUNCNAME[0]}" "$@"

    if [[ -z "$FILE_PATH" ]]; then
        echo "Error: -f <json_file> is required"
        _show_help "${FUNCNAME[0]}"
        return 1
    fi

    if [[ ! -f "$FILE_PATH" ]]; then
        echo "Error: File not found: $FILE_PATH"
        return 1
    fi

    local name
    name=$(jq -r '.name // .properties.name // empty' "$FILE_PATH")
    [[ -z "$name" ]] && name=$(basename "$FILE_PATH" .json)

    echo "Deploying policy assignment: $name"

    local scope_arg=""
    [[ -n "$SCOPE" ]] && scope_arg="--scope $SCOPE"

    if az policy assignment show --name "$name" $scope_arg >/dev/null 2>&1; then
        echo "Assignment exists → Updating..."
        az policy assignment update \
            --name "$name" \
            $scope_arg \
            --policy-assignment "@$FILE_PATH" \
            --output none 2>/dev/null || true
    else
        echo "Assignment does not exist → Creating..."
        az policy assignment create \
            --name "$name" \
            $scope_arg \
            --policy-assignment "@$FILE_PATH" \
            --output none
    fi

    echo "Policy assignment '$name' deployed successfully."
}

# ================================================
# 5. Delete Policy Definition
# ================================================
az_policy_definition_delete() {
    _parse_args "${FUNCNAME[0]}" "$@"

    if [[ -z "$POLICY_ID" ]]; then
        echo "Error: -p <policy_id> is required"
        _show_help "${FUNCNAME[0]}"
        return 1
    fi

    echo "Deleting policy definition: $POLICY_ID"
    local scope_arg=""
    [[ -n "$SCOPE" ]] && scope_arg="--management-group $SCOPE"

    az policy definition delete --name "$POLICY_ID" $scope_arg --yes || \
        echo "Warning: Delete command returned non-zero (may already be deleted)."
}

# ================================================
# 6. Delete Policy Assignment
# ================================================
az_policy_assignment_delete() {
    _parse_args "${FUNCNAME[0]}" "$@"

    if [[ -z "$ASSIGNMENT_ID" ]]; then
        echo "Error: -a <assignment_id> is required"
        _show_help "${FUNCNAME[0]}"
        return 1
    fi

    echo "Deleting policy assignment: $ASSIGNMENT_ID"
    local scope_arg=""
    [[ -n "$SCOPE" ]] && scope_arg="--scope $SCOPE"

    az policy assignment delete --name "$ASSIGNMENT_ID" $scope_arg --yes || \
        echo "Warning: Delete command returned non-zero (may already be deleted)."
}

# ================================================
# Help Command
# ================================================
az_policy_help() {
    echo "Azure Policy Management Helper Functions"
    echo ""
    echo "Available functions:"
    echo "  az_policy_definition_download   - Download policy definition"
    echo "  az_policy_assignment_download   - Download policy assignment"
    echo "  az_policy_definition_deploy     - Create/Update policy definition"
    echo "  az_policy_assignment_deploy     - Create/Update policy assignment"
    echo "  az_policy_definition_delete     - Delete policy definition"
    echo "  az_policy_assignment_delete     - Delete policy assignment"
    echo "  az_policy_help                  - Show this help"
    echo ""
    echo "Use -h with any function for detailed usage."
}

# Auto show help if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    az_policy_help
fi
