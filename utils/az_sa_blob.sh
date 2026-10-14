#!/usr/bin/env bash
# =============================================================================
# Azure Blob Storage
# Uses Azure CLI / Entra ID authentication (az login must be active)
# =============================================================================

# ----------------------------- USAGE FUNCTION -----------------------------
usage_az_sa_blob_copy_within_container() {
    cat <<EOF
Usage: $0 -s STORAGE_ACCOUNT_NAME -c CONTAINER_NAME

Required flags:
  -s    Azure Storage Account name (e.g. mystorageacct)
  -c    Blob Container name (e.g. terraform-registry)

Prerequisites:
  • You must be logged in via 'az login'
  • Your identity needs 'Storage Blob Data Contributor' role (or equivalent)
    on the storage account

Example:
  $0 -s mystorageacct -c mycontainer
  $0 -c mycontainer -s mystorageacct   # order doesn't matter

EOF
    return 1
}

az_sa_blob_copy_within_container(){

    # Default values (can be overridden via flags)
    local STORAGE_ACCOUNT=""
    local CONTAINER_NAME=""

    # Reset OPTIND so getopts parses from $1 when function is called from a sourced script
    OPTIND=1

    # ----------------------------- PARSE ARGUMENTS -----------------------------
    while getopts "a:c:s:d:h" opt; do
        case $opt in
            a) STORAGE_ACCOUNT="$OPTARG" ;;
            c) CONTAINER_NAME="$OPTARG"  ;;
            s) SOURCE_PREFIX="$OPTARG" ;;
            d) DEST_PREFIX="$OPTARG"  ;;
            h) usage_az_sa_blob_copy_within_container ;;
            \?) echo "Invalid option: -$OPTARG" >&2; usage_az_sa_blob_copy_within_container ;;
        esac
    done

    # Check required arguments
    if [[ -z "$STORAGE_ACCOUNT" || -z "$CONTAINER_NAME" || -z "$SOURCE_PREFIX" || -z "$DEST_PREFIX" ]]; then
        echo "Error: Both -a and -c are required."
        usage_az_sa_blob_copy_within_container
    fi

    # ----------------------------- ENABLE AZCOPY → USE AZ CLI TOKEN -----------------------------
    export AZCOPY_AUTO_LOGIN_TYPE=AZCLI
    export AZCOPY_TENANT_ID=$(az account show --query tenantId -o tsv 2>/dev/null)

    if [[ -z "${AZCOPY_TENANT_ID:-}" ]]; then
        echo "ERROR: Could not retrieve tenant ID from Azure CLI."
        echo "       Please run 'az login' first and ensure it's successful."
        exit 1
    fi

    echo "Authenticated via Azure CLI / Entra ID (tenant: $AZCOPY_TENANT_ID)"

    # ----------------------------- BUILD URLS -----------------------------
    SOURCE_PREFIX="registry.terraform.io"
    DEST_PREFIX="registry.opentofu.org"

    SOURCE_URL="https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER_NAME}/${SOURCE_PREFIX}"
    DEST_URL="https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER_NAME}/${DEST_PREFIX}/"

    # ----------------------------- COPY COMMAND -----------------------------
    echo "=================================================================="
    echo "Starting recursive copy using AzCopy + Entra ID auth"
    echo "  From : ${SOURCE_PREFIX}/"
    echo "  To   : ${DEST_PREFIX}/"
    echo "  Account  : ${STORAGE_ACCOUNT}"
    echo "  Container: ${CONTAINER_NAME}"
    echo "=================================================================="

    azcopy copy "${SOURCE_URL}/*" "${DEST_URL}" \
        --recursive \
        --overwrite=ifSourceNewer \
        --log-level=INFO \
        --put-md5=true

    echo "=================================================================="
    echo "Copy finished successfully!"
    echo "All blobs under 'registry.terraform.io/' are now also under 'registry.opentofu.org/'"
    echo "Virtual directory structure preserved."
    echo "=================================================================="
}
