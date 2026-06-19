#!/bin/bash
# ================================================
# AKS Management - Bash wrapper for aks_list_clusters.py
# ================================================

_AKS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_AKS_PY="${_AKS_SCRIPT_DIR}/aks_list_clusters.py"

function _aks_show_help() {
    local func="$1"
    case $func in
        aks_list_clusters)
            echo "Usage: aks_list_clusters [-f table|json|tsv] [-g <management_group>] [-o <output_file>] [-lq]"
            echo "  List all AKS clusters accessible in the current tenant."
            echo ""
            echo "  -f  Output format (default: table)"
            echo "  -g  Filter by management group id or display name"
            echo "  -o  Write output to file instead of stdout"
            echo "  -l  Refresh subscription/management group cache (--latest)"
            echo "  -q  Suppress progress messages"
            echo ""
            echo "Columns: aksName, subscriptionName, resourceGroup, managementGroupName, status"
            echo "managementGroupName shows the full hierarchy: child -> parent -> ... -> root"
            echo "Uses the currently logged-in Azure CLI user and tenant (az account show)."
            echo "Queries are tenant-wide across all subscriptions that user can access."
            echo "The default subscription is CLI context only; listing is not limited to it."
            echo "Subscription map cache: ~/.cache/aks-subscription-mg-map.json"
            ;;
        aks_refresh_cache)
            echo "Usage: aks_refresh_cache [-q]"
            echo "  Rebuild and persist the subscription → management group cache."
            ;;
        *)
            echo "Unknown function"
            ;;
    esac
}

function _aks_require_python() {
    if [[ ! -f "$_AKS_PY" ]]; then
        echo "Error: Python helper not found: $_AKS_PY" >&2
        return 1
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        echo "Error: python3 is required but not installed" >&2
        return 1
    fi
}

# ================================================
# List all AKS clusters in the tenant
# ================================================
aks_list_clusters() {
    if ! _aks_require_python; then
        return 1
    fi

    local -a py_args=(list-clusters)

    OPTIND=1
    while getopts "f:g:o:lqh" opt; do
        case $opt in
            f) py_args+=(-f "$OPTARG") ;;
            g) py_args+=(-g "$OPTARG") ;;
            o) py_args+=(-o "$OPTARG") ;;
            l) py_args+=(--latest) ;;
            q) py_args+=(-q) ;;
            h) _aks_show_help "aks_list_clusters"; return 0 ;;
            *) echo "Invalid option"; _aks_show_help "aks_list_clusters"; return 1 ;;
        esac
    done

    python3 "$_AKS_PY" "${py_args[@]}"
}

# ================================================
# Refresh subscription → management group cache
# ================================================
aks_refresh_cache() {
    if ! _aks_require_python; then
        return 1
    fi

    local quiet="false"
    OPTIND=1
    while getopts "qh" opt; do
        case $opt in
            q) quiet="true" ;;
            h) _aks_show_help "aks_refresh_cache"; return 0 ;;
            *) echo "Invalid option"; _aks_show_help "aks_refresh_cache"; return 1 ;;
        esac
    done

    local -a py_args=(refresh-cache)
    [[ "$quiet" == "true" ]] && py_args+=(-q)

    python3 "$_AKS_PY" "${py_args[@]}"
}

# ================================================
# Help Command
# ================================================
aks_help() {
    echo "AKS Management Helper Functions"
    echo ""
    echo "Available functions:"
    echo "  aks_list_clusters   - List all AKS clusters in the tenant"
    echo "  aks_refresh_cache   - Rebuild subscription/management group cache"
    echo "  aks_help            - Show this help"
    echo ""
    echo "Use -h with any function for detailed usage."
    echo ""
    echo "Example:"
    echo "  source utils/aks.sh"
    echo "  aks_list_clusters"
    echo "  aks_list_clusters -l -f json"
    echo "  aks_list_clusters -f json -g essity-landingzones"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    aks_help
fi
