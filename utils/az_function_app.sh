get_function_app_setting() {
    local resource_group=""
    local function_app=""
    local namespace=""
    local setting_name=""

    OPTIND=1

    while getopts ":n:f:l:s:" opt; do
        case "$opt" in
            n) resource_group="$OPTARG" ;;
            f) function_app="$OPTARG" ;;
            l) namespace="$OPTARG" ;;
            s) setting_name="$OPTARG" ;;
            :)
                echo "ERROR: Option -$OPTARG requires a value." >&2
                return 1
                ;;
            \?)
                echo "ERROR: Invalid option: -$OPTARG" >&2
                return 1
                ;;
        esac
    done

    # -s is mandatory
    if [[ -z "$setting_name" ]]; then
        echo "ERROR: -s <app-setting-name> is mandatory." >&2
        echo
        echo "Usage:"
        echo "  get_function_app_setting -n <resource-group> -f <function-app> -s <setting>"
        echo "  get_function_app_setting -l <namespace> -s <setting>"
        return 1
    fi

    # Either explicit Function App or namespace search
    if [[ -n "$namespace" ]]; then

        if [[ -n "$resource_group" || -n "$function_app" ]]; then
            echo "ERROR: -l cannot be combined with -n or -f." >&2
            return 1
        fi

    elif [[ -n "$resource_group" || -n "$function_app" ]]; then

        if [[ -z "$resource_group" || -z "$function_app" ]]; then
            echo "ERROR: -n and -f must be supplied together." >&2
            return 1
        fi

    else
        echo "ERROR: Specify either:" >&2
        echo "  -n <resource-group> -f <function-app>" >&2
        echo "or:" >&2
        echo "  -l <namespace>" >&2
        return 1
    fi

    printf "%-45s %-55s %s\n" \
        "RESOURCE_GROUP" \
        "FUNCTION_APP" \
        "$setting_name"

    printf "%-45s %-55s %s\n" \
        "---------------------------------------------" \
        "-------------------------------------------------------" \
        "------------------------------"

    #
    # Single Function App
    #
    if [[ -n "$function_app" ]]; then

        local value

        value=$(az functionapp config appsettings list \
            --resource-group "$resource_group" \
            --name "$function_app" \
            --query "[?name=='$setting_name'].value | [0]" \
            --output tsv 2>/dev/null)

        [[ -z "$value" ]] && value="<NOT_SET>"

        printf "%-45s %-55s %s\n" \
            "$resource_group" \
            "$function_app" \
            "$value"

        return
    fi

    #
    # Namespace search across current subscription
    #
    az functionapp list \
        --query "[?contains(name, '$namespace')].[resourceGroup,name]" \
        --output tsv |
    while IFS=$'\t' read -r rg app; do

        [[ -z "$rg" || -z "$app" ]] && continue

        local value

        value=$(az functionapp config appsettings list \
            --resource-group "$rg" \
            --name "$app" \
            --query "[?name=='$setting_name'].value | [0]" \
            --output tsv 2>/dev/null)

        [[ -z "$value" ]] && value="<NOT_SET>"

        printf "%-45s %-55s %s\n" \
            "$rg" \
            "$app" \
            "$value"
    done
}
