#!/bin/bash
# Azure Database for PostgreSQL utilities (Azure CLI / logged-in user).

_az_pg_require_az() {
    if ! command -v az >/dev/null 2>&1; then
        echo "Error: Azure CLI (az) is not installed or not in PATH" >&2
        return 1
    fi
    if ! az account show >/dev/null 2>&1; then
        echo "Error: not logged into Azure. Run 'az login' first." >&2
        return 1
    fi
}

_az_pg_flag_value() {
    if [[ -z "${2:-}" || "$2" == -* ]]; then
        echo "Error: $1 requires a value" >&2
        return 1
    fi
}

_az_pg_set_subscription() {
    local subscription="${1:-}"

    _az_pg_require_az || return 1

    if [[ -n "$subscription" ]]; then
        if ! az account set --subscription "$subscription" >/dev/null 2>&1; then
            echo "Error: failed to set subscription '$subscription'" >&2
            return 1
        fi
    fi

    az account show --query "{Name:name, ID:id}" -o table
}

# Run an az list command; print nothing on failure (variant unavailable or none found).
_az_pg_safe_list() {
    "$@" 2>/dev/null || true
}

# Print: variant<TAB>name<TAB>state<TAB>extra
_az_pg_collect_flexible_servers() {
    local rg="$1"
    local line name state ha

    while IFS=$'\t' read -r name state ha; do
        [[ -z "$name" ]] && continue
        ha="${ha:-n/a}"
        printf 'flexible-server\t%s\t%s\t%s\n' "$name" "$state" "$ha"
    done < <(_az_pg_safe_list az postgres flexible-server list -g "$rg" \
        --query "[].{name:name, state:state, ha:highAvailability.state}" -o tsv)
}

_az_pg_collect_single_servers() {
    local rg="$1"
    local name state

    while IFS=$'\t' read -r name state; do
        [[ -z "$name" ]] && continue
        printf 'single-server\t%s\t%s\t%s\n' "$name" "$state" "n/a"
    done < <(_az_pg_safe_list az postgres server list -g "$rg" \
        --query "[].{name:name, state:userVisibleState}" -o tsv)
}

_az_pg_collect_cosmos_clusters() {
    local rg="$1"
    local name state prov

    while IFS=$'\t' read -r name state prov; do
        [[ -z "$name" ]] && continue
        [[ -z "$state" || "$state" == "None" ]] && state="$prov"
        printf 'cosmos-postgresql\t%s\t%s\t%s\n' "$name" "$state" "n/a"
    done < <(_az_pg_safe_list az cosmosdb postgres cluster list -g "$rg" \
        --query "[].{name:name, state:state, prov:provisioningState}" -o tsv)
}

# Older Citus / server group resources (no dedicated list state — report provisioningState only).
_az_pg_collect_server_groups() {
    local rg="$1"
    local name prov

    while IFS=$'\t' read -r name prov; do
        [[ -z "$name" ]] && continue
        printf 'server-group-v1\t%s\t%s\t%s\n' "$name" "$prov" "n/a"
    done < <(_az_pg_safe_list az resource list -g "$rg" \
        --resource-type Microsoft.DBforPostgreSQL/serverGroups \
        --query "[].{name:name, prov:provisioningState}" -o tsv)
}

_az_pg_is_ready() {
    [[ "$1" == "Ready" ]]
}

az_postgresql_check_servers_help() {
    cat <<'EOF'
Usage: az_postgresql_check_servers -g <resource_group> [-s <subscription_id>]

Check that all Azure PostgreSQL servers in a resource group are Ready (running).

Uses the current 'az login' identity. Subscription is optional; when omitted,
the active subscription from 'az account show' is used.

Required:
  -g, --resource-group    Resource group to inspect

Optional:
  -s, --subscription      Subscription ID or name (default: current subscription)
  -h, --help              Show this help

Variants checked (missing variants are skipped silently):
  - PostgreSQL Flexible Server      (az postgres flexible-server list)
  - PostgreSQL Single Server        (az postgres server list, legacy)
  - Cosmos DB for PostgreSQL        (az cosmosdb postgres cluster list)
  - PostgreSQL server groups v1     (az resource list, legacy Citus)

Exit code:
  0  Always (status is informational; check READY column in output)

Examples:
  az_postgresql_check_servers -g my-rg
  az_postgresql_check_servers -g my-rg -s 00000000-0000-0000-0000-000000000000
EOF
}

az_postgresql_check_servers() {
    local resource_group="" subscription=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                az_postgresql_check_servers_help
                return 0
                ;;
            -g|--resource-group)
                _az_pg_flag_value "$1" "${2:-}" || return 1
                resource_group="$2"
                shift 2
                ;;
            -s|--subscription)
                _az_pg_flag_value "$1" "${2:-}" || return 1
                subscription="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                az_postgresql_check_servers_help >&2
                return 1
                ;;
        esac
    done

    if [[ -z "$resource_group" ]]; then
        echo "Error: -g <resource_group> is required" >&2
        echo "Run 'az_postgresql_check_servers -h' for usage." >&2
        return 1
    fi

    echo "Azure subscription:"
    _az_pg_set_subscription "$subscription" || return 1
    echo

    local -a rows=()
    local row variant name state extra

    while IFS= read -r row; do
        [[ -z "$row" ]] && continue
        rows+=("$row")
    done < <(
        _az_pg_collect_flexible_servers "$resource_group"
        _az_pg_collect_single_servers "$resource_group"
        _az_pg_collect_cosmos_clusters "$resource_group"
        _az_pg_collect_server_groups "$resource_group"
    )

    if [[ ${#rows[@]} -eq 0 ]]; then
        echo "No PostgreSQL servers found in resource group '$resource_group'."
        return 0
    fi

    echo "PostgreSQL servers in resource group '$resource_group':"
    printf "%-20s %-35s %-15s %-8s %s\n" "VARIANT" "NAME" "STATE" "READY" "NOTES"
    printf "%-20s %-35s %-15s %-8s %s\n" "-------" "----" "-----" "-----" "-----"

    local not_ready=0
    local notes ready_flag

    for row in "${rows[@]}"; do
        IFS=$'\t' read -r variant name state extra <<< "$row"
        notes=""
        if _az_pg_is_ready "$state"; then
            ready_flag="yes"
            if [[ "$variant" == "flexible-server" && -n "$extra" && "$extra" != "n/a" && "$extra" != "None" && "$extra" != "Healthy" ]]; then
                notes="HA: $extra"
            fi
        else
            ready_flag="no"
            not_ready=$((not_ready + 1))
            if [[ "$variant" == "flexible-server" && -n "$extra" && "$extra" != "n/a" && "$extra" != "None" ]]; then
                notes="HA: $extra"
            fi
        fi
        printf "%-20s %-35s %-15s %-8s %s\n" "$variant" "$name" "$state" "$ready_flag" "$notes"
    done

    echo
    if [[ $not_ready -gt 0 ]]; then
        echo "Result: $not_ready server(s) not Ready."
    else
        echo "Result: all ${#rows[@]} server(s) are Ready."
    fi
    return 0
}
