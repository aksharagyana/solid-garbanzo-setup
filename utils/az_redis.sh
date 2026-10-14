# Azure Managed Redis utilities (az redisenterprise).

_az_redis_require_az() {
    if ! command -v az >/dev/null 2>&1; then
        echo "Error: Azure CLI (az) is not installed or not in PATH" >&2
        return 1
    fi
    if ! az account show >/dev/null 2>&1; then
        echo "Error: not logged into Azure. Run 'az login' first." >&2
        return 1
    fi
}

_az_redis_ensure_extension() {
    if az extension show --name redisenterprise -o none 2>/dev/null; then
        return 0
    fi

    echo "Installing Azure CLI redisenterprise extension (first run only; can take a minute)..."
    if ! az extension add --name redisenterprise -y; then
        echo "Error: failed to install redisenterprise extension." >&2
        return 1
    fi
}

_az_redis_managed_database_ids() {
    local resource_group="$1"
    local cluster_name="$2"
    local subscription database

    subscription=$(az account show --query id -o tsv) || return 1

    while IFS= read -r database; do
        [[ -z "$database" ]] && continue
        printf '/subscriptions/%s/resourceGroups/%s/providers/Microsoft.Cache/redisEnterprise/%s/databases/%s\n' \
            "$subscription" "$resource_group" "$cluster_name" "$database"
    done < <(az redisenterprise database list \
        --resource-group "$resource_group" \
        --cluster-name "$cluster_name" \
        --query "[].name" -o tsv)
}

az_redis_flush_help() {
cat <<EOF
Flush all keys from an Azure Managed Redis cluster.

Usage:
  az_redis_flush -g <resource-group> -n <cluster-name> [-y]

Options:
  -g    Azure Resource Group name
  -n    Azure Managed Redis cluster name
  -y    Skip confirmation prompt
  -h    Show this help message

Examples:
  az_redis_flush -g rg-prod -n redis-prod
  az_redis_flush -g my-rg -n my-redis -y

Requirements:
  - Azure CLI installed and authenticated (az login)
  - redisenterprise extension (installed automatically on first use)
  - Permissions to flush the cache

WARNING:
  This operation permanently deletes ALL data in every database on the cluster.
  Azure completes the flush asynchronously; memory metrics may lag behind.
EOF
}

az_redis_flush() {
    local resource_group=""
    local cluster_name=""
    local assume_yes=0

    local OPTIND
    OPTIND=1
    while getopts ":g:n:yh" opt; do
        case ${opt} in
            g)
                resource_group="$OPTARG"
                ;;
            n)
                cluster_name="$OPTARG"
                ;;
            y)
                assume_yes=1
                ;;
            h)
                az_redis_flush_help
                return 0
                ;;
            \?)
                echo "Error: Invalid option -$OPTARG"
                az_redis_flush_help
                return 1
                ;;
            :)
                echo "Error: Option -$OPTARG requires an argument"
                az_redis_flush_help
                return 1
                ;;
        esac
    done

    if [[ -z "$resource_group" || -z "$cluster_name" ]]; then
        echo "Error: Both -g and -n are required."
        echo
        az_redis_flush_help
        return 1
    fi

    _az_redis_require_az || return 1
    _az_redis_ensure_extension || return 1

    echo "Subscription: $(az account show --query name -o tsv)"
    echo "Looking up cluster '$cluster_name' in '$resource_group'..."

    local host
    if ! host=$(az redisenterprise show \
        --resource-group "$resource_group" \
        --name "$cluster_name" \
        --query hostName \
        -o tsv); then
        echo "Error: Azure Managed Redis cluster '$cluster_name' not found in '$resource_group'." >&2
        echo "Check the name, resource group, and active subscription (az account set)." >&2
        return 1
    fi

    if [[ -z "$host" ]]; then
        echo "Failed to retrieve Azure Managed Redis hostname."
        return 1
    fi

    echo "Listing databases..."
    local database_ids=()
    while IFS= read -r id; do
        [[ -z "$id" ]] && continue
        database_ids+=("$id")
    done < <(_az_redis_managed_database_ids "$resource_group" "$cluster_name")

    if [[ ${#database_ids[@]} -eq 0 ]]; then
        echo "Error: no databases found on cluster '$cluster_name'." >&2
        return 1
    fi

    echo "Target: Azure Managed Redis ($cluster_name)"
    echo "Host: $host"
    echo "Databases: ${#database_ids[@]}"
    echo

    if [[ $assume_yes -ne 1 ]]; then
        read -p "Flush ALL Redis data? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            echo "Operation cancelled."
            return 0
        fi
    fi

    local id rc=0
    for id in "${database_ids[@]}"; do
        echo "Flushing ${id##*/databases/} (waiting for Azure to finish; can take several minutes)..."
        if ! az redisenterprise database flush --ids "$id"; then
            echo "Redis flush failed for ${id##*/databases/}."
            rc=1
        fi
    done

    if [[ $rc -eq 0 ]]; then
        echo "Redis flush completed successfully."
    fi

    return $rc
}
