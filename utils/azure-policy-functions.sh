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
    TARGET_DIR=""
    POLICY_NAME=""
    DISPLAY_NAME=""
    RULE_FILE=""
    PARAMS_FILE=""
    MANAGEMENT_GROUP=""
    INITIATIVE_ID=""

    # getopts uses global OPTIND; reset so repeat calls in the same shell work.
    OPTIND=1

    while getopts "p:a:f:s:o:d:hn:D:r:u:g:i:" opt; do
        case $opt in
            p) POLICY_ID="$OPTARG" ;;
            a) ASSIGNMENT_ID="$OPTARG" ;;
            f) FILE_PATH="$OPTARG" ;;
            s) SCOPE="$OPTARG" ;;
            o) OUTPUT_FILE="$OPTARG" ;;
            d) TARGET_DIR="$OPTARG" ;;
            n) POLICY_NAME="$OPTARG" ;;
            D) DISPLAY_NAME="$OPTARG" ;;
            r) RULE_FILE="$OPTARG" ;;
            u) PARAMS_FILE="$OPTARG" ;;
            g) MANAGEMENT_GROUP="$OPTARG" ;;
            i) INITIATIVE_ID="$OPTARG" ;;
            h) _show_help "$func_name"; exit 0 ;;
            *) echo "Invalid option"; _show_help "$func_name"; exit 1 ;;
        esac
    done
}

# ARM IDs are case-insensitive; bash =~ is not unless nocasematch is on.
_with_nocasematch() {
    local _restore=0
    shopt -q nocasematch || { shopt -s nocasematch; _restore=1; }
    "$@"
    local _rc=$?
    ((_restore)) && shopt -u nocasematch
    return "$_rc"
}

_canonicalize_management_group_scope() {
    local mg="$1"
    echo "/providers/Microsoft.Management/managementGroups/${mg}"
}

# Parse full ARM resource ID (or short name) into az CLI flags.
_parse_policy_definition_id() {
    local id="$1"
    POLICY_DEF_NAME=""
    POLICY_DEF_MG=""
    POLICY_DEF_SUB=""

    _with_nocasematch _parse_policy_definition_id_impl "$id"
}

_parse_policy_definition_id_impl() {
    local id="$1"

    if [[ "$id" =~ /managementGroups/([^/]+)/providers/Microsoft\.Authorization/policyDefinitions/([^/]+)$ ]]; then
        POLICY_DEF_MG="${BASH_REMATCH[1]}"
        POLICY_DEF_NAME="${BASH_REMATCH[2]}"
    elif [[ "$id" =~ /subscriptions/([^/]+)/providers/Microsoft\.Authorization/policyDefinitions/([^/]+)$ ]]; then
        POLICY_DEF_SUB="${BASH_REMATCH[1]}"
        POLICY_DEF_NAME="${BASH_REMATCH[2]}"
    elif [[ "$id" =~ ^/providers/Microsoft\.Authorization/policyDefinitions/([^/]+)$ ]]; then
        POLICY_DEF_NAME="${BASH_REMATCH[1]}"
    else
        POLICY_DEF_NAME="${id##*/}"
        POLICY_DEF_NAME="${POLICY_DEF_NAME%.json}"
    fi
}

_parse_policy_assignment_id() {
    local id="$1"
    ASSIGN_NAME=""
    ASSIGN_SCOPE=""

    _with_nocasematch _parse_policy_assignment_id_impl "$id"
}

_parse_policy_assignment_id_impl() {
    local id="$1"

    if [[ "$id" =~ ^(.+)/providers/Microsoft\.Authorization/policyAssignments/([^/]+)$ ]]; then
        ASSIGN_SCOPE="${BASH_REMATCH[1]}"
        ASSIGN_NAME="${BASH_REMATCH[2]}"
        if [[ "$ASSIGN_SCOPE" =~ ^/providers/Microsoft\.Management/managementGroups/([^/]+)$ ]]; then
            ASSIGN_SCOPE="$(_canonicalize_management_group_scope "${BASH_REMATCH[1]}")"
        fi
    else
        ASSIGN_NAME="${id##*/}"
        ASSIGN_NAME="${ASSIGN_NAME%.json}"
    fi
}

_parse_policy_set_definition_id() {
    local id="$1"
    POLICY_SET_DEF_NAME=""
    POLICY_SET_DEF_MG=""
    POLICY_SET_DEF_SUB=""

    _with_nocasematch _parse_policy_set_definition_id_impl "$id"
}

_parse_policy_set_definition_id_impl() {
    local id="$1"

    if [[ "$id" =~ /managementGroups/([^/]+)/providers/Microsoft\.Authorization/policySetDefinitions/([^/]+)$ ]]; then
        POLICY_SET_DEF_MG="${BASH_REMATCH[1]}"
        POLICY_SET_DEF_NAME="${BASH_REMATCH[2]}"
    elif [[ "$id" =~ /subscriptions/([^/]+)/providers/Microsoft\.Authorization/policySetDefinitions/([^/]+)$ ]]; then
        POLICY_SET_DEF_SUB="${BASH_REMATCH[1]}"
        POLICY_SET_DEF_NAME="${BASH_REMATCH[2]}"
    elif [[ "$id" =~ ^/providers/Microsoft\.Authorization/policySetDefinitions/([^/]+)$ ]]; then
        POLICY_SET_DEF_NAME="${BASH_REMATCH[1]}"
    else
        POLICY_SET_DEF_NAME="${id##*/}"
        POLICY_SET_DEF_NAME="${POLICY_SET_DEF_NAME%.json}"
    fi
}

_az_policy_definition_download_to_file() {
    local policy_id="$1"
    local output="$2"

    _parse_policy_definition_id "$policy_id"

    local out_dir
    out_dir=$(dirname "$output")
    [[ "$out_dir" != "." && -n "$out_dir" ]] && mkdir -p "$out_dir"

    local az_args=(--name "$POLICY_DEF_NAME")
    [[ -n "$POLICY_DEF_MG" ]] && az_args+=(--management-group "$POLICY_DEF_MG")
    [[ -n "$POLICY_DEF_SUB" ]] && az_args+=(--subscription "$POLICY_DEF_SUB")

    az policy definition show "${az_args[@]}" --output json > "$output"
}

_az_policy_set_definition_download_to_file() {
    local initiative_id="$1"
    local output="$2"

    _parse_policy_set_definition_id "$initiative_id"

    local out_dir
    out_dir=$(dirname "$output")
    [[ "$out_dir" != "." && -n "$out_dir" ]] && mkdir -p "$out_dir"

    local az_args=(--name "$POLICY_SET_DEF_NAME")
    [[ -n "$POLICY_SET_DEF_MG" ]] && az_args+=(--management-group "$POLICY_SET_DEF_MG")
    [[ -n "$POLICY_SET_DEF_SUB" ]] && az_args+=(--subscription "$POLICY_SET_DEF_SUB")

    az policy set-definition show "${az_args[@]}" --output json > "$output"
}

# Download member policy/set definitions referenced by an initiative JSON file.
# $1 initiative JSON path, $2 base target directory, $3 newline-separated visited initiative ARM ids
_az_policy_initiative_download_members() {
    local initiative_file="$1"
    local base_dir="$2"
    local visited_initiatives="${3:-}"

    local member_ids
    member_ids=$(jq -r '
        (.policyDefinitions // .properties.policyDefinitions // [])[]
        | .policyDefinitionId // empty
    ' "$initiative_file")

    if [[ -z "$member_ids" ]]; then
        echo "  No member policy definitions found in initiative."
        return 0
    fi

    local policy_dir="${base_dir}/policies"
    local initiative_dir="${base_dir}/initiatives"
    mkdir -p "$policy_dir" "$initiative_dir"

    local member_id member_name output_file
    while IFS= read -r member_id; do
        [[ -z "$member_id" ]] && continue
        member_name="${member_id##*/}"

        if _with_nocasematch [[ "$member_id" =~ /policySetDefinitions/ ]]; then
            output_file="${initiative_dir}/${member_name}.json"
            if printf '%s\n' "$visited_initiatives" | grep -Fxq "$member_id"; then
                echo "  Skipping nested initiative (already downloaded): $member_id"
                continue
            fi

            echo "  Downloading nested initiative: $member_id"
            if ! _az_policy_set_definition_download_to_file "$member_id" "$output_file"; then
                echo "  Warning: failed to download nested initiative: $member_id"
                rm -f "$output_file"
                continue
            fi
            echo "    Saved to: $output_file"

            local new_visited="${visited_initiatives}"$'\n'"${member_id}"
            _az_policy_initiative_download_members "$output_file" "$base_dir" "$new_visited"
        else
            output_file="${policy_dir}/${member_name}.json"
            echo "  Downloading policy definition: $member_id"
            if ! _az_policy_definition_download_to_file "$member_id" "$output_file"; then
                echo "  Warning: failed to download policy definition: $member_id"
                rm -f "$output_file"
                continue
            fi
            echo "    Saved to: $output_file"
        fi
    done <<< "$member_ids"
}

function _show_help() {
    local func="$1"
    case $func in
        az_policy_definition_download)
            echo "Usage: az_policy_definition_download -p <policy_id> [-o <output_file>]"
            echo "  -p  Policy Definition ID or Name"
            echo "  -o  Output JSON file path (optional)"
            ;;
        az_policy_initiative_download)
            echo "Usage: az_policy_initiative_download -i <initiative_id> [-d <target_directory>] [-o <output_file>]"
            echo "  -i  Policy Initiative (set definition) ID or Name"
            echo "  -d  Target directory — downloads initiative plus all member policies/initiatives"
            echo "  -o  Output JSON file path for initiative only (ignored when -d is set)"
            ;;
        az_policy_assignment_download)
            echo "Usage: az_policy_assignment_download -a <assignment_arm_id> [-o <output_file>]"
            echo "  -a  Full policy assignment ARM resource ID (required for MG/subscription scope)"
            echo "  -o  Output JSON file path (optional)"
            echo "  Note: display name is not supported; use the assignment name from the ARM id."
            ;;
        az_policy_definition_deploy)
            echo "Usage: az_policy_definition_deploy -n <name> -D <display_name> -r <rule.json> (-g <mg> | -s <subscription>) [-u <parameters.json>]"
            echo "  -n  Policy definition name (required)"
            echo "  -D  Policy definition display name (required)"
            echo "  -r  Policy rule JSON file (required)"
            echo "  -u  Policy parameters JSON file (optional)"
            echo "  -g  Management group id or name (required if -s not set)"
            echo "  -s  Subscription id or name (required if -g not set)"
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
        az_policy_prepare_artifacts)
            echo "Usage: az_policy_prepare_artifacts -f <policy_definition.json> -d <target_directory>"
            echo "  -f  Local Azure Policy Definition JSON (from download or export)"
            echo "  -d  Base directory for policyrule/ and parameters/ subfolders"
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

    _parse_policy_definition_id "$POLICY_ID"

    local output="${OUTPUT_FILE:-${POLICY_DEF_NAME}.json}"

    echo "Downloading policy definition: $POLICY_ID"
    if ! _az_policy_definition_download_to_file "$POLICY_ID" "$output"; then
        echo "Error: failed to download policy definition (name=$POLICY_DEF_NAME)"
        rm -f "$output"
        return 1
    fi
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

    _parse_policy_assignment_id "$ASSIGNMENT_ID"

    local output="${OUTPUT_FILE:-${ASSIGN_NAME}.json}"
    local out_dir
    out_dir=$(dirname "$output")
    [[ "$out_dir" != "." && -n "$out_dir" ]] && mkdir -p "$out_dir"

    local az_args=(--name "$ASSIGN_NAME")
    [[ -n "$ASSIGN_SCOPE" ]] && az_args+=(--scope "$ASSIGN_SCOPE")

    echo "Downloading policy assignment: $ASSIGNMENT_ID"
    if ! az policy assignment show "${az_args[@]}" --output json > "$output"; then
        echo "Error: failed to download policy assignment (name=$ASSIGN_NAME)"
        rm -f "$output"
        return 1
    fi
    echo "Saved to: $output"
}

# ================================================
# 2b. Download Policy Initiative (set definition) and member policies
# ================================================
az_policy_initiative_download() {
    _parse_args "${FUNCNAME[0]}" "$@"

    if [[ -z "$INITIATIVE_ID" ]]; then
        echo "Error: -i <initiative_id> is required"
        _show_help "${FUNCNAME[0]}"
        return 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: jq is required but not installed"
        return 1
    fi

    _parse_policy_set_definition_id "$INITIATIVE_ID"

    if [[ -n "$TARGET_DIR" ]]; then
        mkdir -p "$TARGET_DIR"
        local initiative_file="${TARGET_DIR}/${POLICY_SET_DEF_NAME}.json"

        echo "Downloading policy initiative: $INITIATIVE_ID"
        if ! _az_policy_set_definition_download_to_file "$INITIATIVE_ID" "$initiative_file"; then
            echo "Error: failed to download policy initiative (name=$POLICY_SET_DEF_NAME)"
            rm -f "$initiative_file"
            return 1
        fi
        echo "Saved initiative to: $initiative_file"

        echo "Downloading member policies for initiative: $POLICY_SET_DEF_NAME"
        _az_policy_initiative_download_members "$initiative_file" "$TARGET_DIR" "$INITIATIVE_ID"
        echo "Initiative bundle saved under: $TARGET_DIR"
        return 0
    fi

    local output="${OUTPUT_FILE:-${POLICY_SET_DEF_NAME}.json}"

    echo "Downloading policy initiative: $INITIATIVE_ID"
    if ! _az_policy_set_definition_download_to_file "$INITIATIVE_ID" "$output"; then
        echo "Error: failed to download policy initiative (name=$POLICY_SET_DEF_NAME)"
        rm -f "$output"
        return 1
    fi
    echo "Saved to: $output"
}

# ================================================
# 3. Deploy (Create/Update) Policy Definition - Idempotent
# ================================================
az_policy_definition_deploy() {
    _parse_args "${FUNCNAME[0]}" "$@"

    if [[ -z "$POLICY_NAME" ]]; then
        echo "Error: -n <name> is required"
        _show_help "${FUNCNAME[0]}"
        return 1
    fi

    if [[ -z "$DISPLAY_NAME" ]]; then
        echo "Error: -D <display_name> is required"
        _show_help "${FUNCNAME[0]}"
        return 1
    fi

    if [[ -z "$RULE_FILE" ]]; then
        echo "Error: -r <policy_rule.json> is required"
        _show_help "${FUNCNAME[0]}"
        return 1
    fi

    if [[ -z "$MANAGEMENT_GROUP" && -z "$SCOPE" ]]; then
        echo "Error: specify exactly one scope: -g <management_group> or -s <subscription>"
        _show_help "${FUNCNAME[0]}"
        return 1
    fi

    if [[ -n "$MANAGEMENT_GROUP" && -n "$SCOPE" ]]; then
        echo "Error: use only one of -g <management_group> or -s <subscription>, not both"
        _show_help "${FUNCNAME[0]}"
        return 1
    fi

    if [[ ! -f "$RULE_FILE" ]]; then
        echo "Error: Policy rule file not found: $RULE_FILE"
        return 1
    fi

    if [[ -n "$PARAMS_FILE" && ! -f "$PARAMS_FILE" ]]; then
        echo "Error: Parameters file not found: $PARAMS_FILE"
        return 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: jq is required but not installed"
        return 1
    fi

    if ! jq empty "$RULE_FILE" 2>/dev/null; then
        echo "Error: Invalid JSON in policy rule file: $RULE_FILE"
        return 1
    fi

    if [[ -n "$PARAMS_FILE" ]] && ! jq empty "$PARAMS_FILE" 2>/dev/null; then
        echo "Error: Invalid JSON in parameters file: $PARAMS_FILE"
        return 1
    fi

    local scope_args=()
    if [[ -n "$MANAGEMENT_GROUP" ]]; then
        scope_args=(--management-group "$MANAGEMENT_GROUP")
        echo "Deploying policy definition: $POLICY_NAME (management group: $MANAGEMENT_GROUP)"
    else
        scope_args=(--subscription "$SCOPE")
        echo "Deploying policy definition: $POLICY_NAME (subscription: $SCOPE)"
    fi

    local az_args=(
        --name "$POLICY_NAME"
        --display-name "$DISPLAY_NAME"
        --rules "@${RULE_FILE}"
    )
    [[ -n "$PARAMS_FILE" ]] && az_args+=(--params "@${PARAMS_FILE}")

    if az policy definition show --name "$POLICY_NAME" "${scope_args[@]}" >/dev/null 2>&1; then
        echo "Policy exists → Updating..."
        if ! az policy definition update "${scope_args[@]}" "${az_args[@]}" --output none; then
            echo "Error: failed to update policy definition '$POLICY_NAME'"
            return 1
        fi
    else
        echo "Policy does not exist → Creating..."
        if ! az policy definition create "${scope_args[@]}" "${az_args[@]}" --output none; then
            echo "Error: failed to create policy definition '$POLICY_NAME'"
            return 1
        fi
    fi

    local policy_id
    policy_id=$(az policy definition show --name "$POLICY_NAME" "${scope_args[@]}" --query id -o tsv 2>/dev/null) || true
    if [[ -z "$policy_id" ]]; then
        echo "Error: deployed but could not retrieve policy definition id"
        return 1
    fi

    echo "Policy definition id: $policy_id"
    echo "Policy definition '$POLICY_NAME' deployed successfully."
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
# 5. Prepare deployment artifacts from a policy definition JSON
# ================================================
az_policy_prepare_artifacts() {
    _parse_args "${FUNCNAME[0]}" "$@"

    if [[ -z "$FILE_PATH" ]]; then
        echo "Error: -f <policy_definition.json> is required"
        _show_help "${FUNCNAME[0]}"
        return 1
    fi

    if [[ -z "$TARGET_DIR" ]]; then
        echo "Error: -d <target_directory> is required"
        _show_help "${FUNCNAME[0]}"
        return 1
    fi

    if [[ ! -f "$FILE_PATH" ]]; then
        echo "Error: File not found: $FILE_PATH"
        return 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: jq is required but not installed"
        return 1
    fi

    if ! jq empty "$FILE_PATH" 2>/dev/null; then
        echo "Error: Invalid JSON: $FILE_PATH"
        return 1
    fi

    if ! jq -e '.policyRule // .properties.policyRule' "$FILE_PATH" >/dev/null 2>&1; then
        echo "Error: policyRule not found in $FILE_PATH (expected .policyRule or .properties.policyRule)"
        return 1
    fi

    local stem rule_dir params_dir rule_file params_file
    stem=$(basename "$FILE_PATH" .json)
    rule_dir="${TARGET_DIR}/policyrule"
    params_dir="${TARGET_DIR}/parameters"
    rule_file="${rule_dir}/${stem}-pr.json"
    params_file="${params_dir}/${stem}-parameters.json"

    mkdir -p "$rule_dir" "$params_dir"

    echo "Preparing artifacts from: $FILE_PATH"
    echo "Target directory: $TARGET_DIR"

    if ! jq '.policyRule // .properties.policyRule' "$FILE_PATH" > "$rule_file"; then
        echo "Error: failed to write policy rule file: $rule_file"
        rm -f "$rule_file"
        return 1
    fi
    echo "  Policy rule:  $rule_file"

    if jq -e '(.parameters // .properties.parameters) != null' "$FILE_PATH" >/dev/null 2>&1; then
        if ! jq '.parameters // .properties.parameters' "$FILE_PATH" > "$params_file"; then
            echo "Error: failed to write parameters file: $params_file"
            rm -f "$params_file"
            return 1
        fi
        echo "  Parameters:   $params_file"
    else
        echo "  Parameters:   (none in source — skipped)"
    fi

    echo "Artifacts prepared successfully."
}

# ================================================
# 6. Delete Policy Definition
# ================================================
az_policy_definition_delete() {
    _parse_args "${FUNCNAME[0]}" "$@"

    if [[ -z "$POLICY_ID" ]]; then
        echo "Error: -p <policy_id> is required"
        _show_help "${FUNCNAME[0]}"
        return 1
    fi

    _parse_policy_definition_id "$POLICY_ID"

    echo "Deleting policy definition: $POLICY_ID"
    local az_args=(--name "$POLICY_DEF_NAME")
    if [[ -n "$SCOPE" ]]; then
        az_args+=(--management-group "$SCOPE")
    elif [[ -n "$POLICY_DEF_MG" ]]; then
        az_args+=(--management-group "$POLICY_DEF_MG")
    elif [[ -n "$POLICY_DEF_SUB" ]]; then
        az_args+=(--subscription "$POLICY_DEF_SUB")
    fi

    az policy definition delete "${az_args[@]}" --yes || \
        echo "Warning: Delete command returned non-zero (may already be deleted)."
}

# ================================================
# 7. Delete Policy Assignment
# ================================================
az_policy_assignment_delete() {
    _parse_args "${FUNCNAME[0]}" "$@"

    if [[ -z "$ASSIGNMENT_ID" ]]; then
        echo "Error: -a <assignment_id> is required"
        _show_help "${FUNCNAME[0]}"
        return 1
    fi

    _parse_policy_assignment_id "$ASSIGNMENT_ID"

    echo "Deleting policy assignment: $ASSIGNMENT_ID"
    local az_args=(--name "$ASSIGN_NAME")
    if [[ -n "$SCOPE" ]]; then
        az_args+=(--scope "$SCOPE")
    elif [[ -n "$ASSIGN_SCOPE" ]]; then
        az_args+=(--scope "$ASSIGN_SCOPE")
    fi

    az policy assignment delete "${az_args[@]}" --yes || \
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
    echo "  az_policy_initiative_download   - Download initiative and member policies"
    echo "  az_policy_assignment_download   - Download policy assignment"
    echo "  az_policy_definition_deploy     - Create/Update policy definition"
    echo "  az_policy_assignment_deploy     - Create/Update policy assignment"
    echo "  az_policy_definition_delete     - Delete policy definition"
    echo "  az_policy_assignment_delete     - Delete policy assignment"
    echo "  az_policy_prepare_artifacts     - Split definition into policyrule/ and parameters/"
    echo "  az_policy_help                  - Show this help"
    echo ""
    echo "Use -h with any function for detailed usage."
}

# Auto show help if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    az_policy_help
fi
