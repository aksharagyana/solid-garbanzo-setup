# acr_retag_multiarch_image \
#   myacr \
#   myapp:1.0.0 \
#   myapp:latest
  
acr_retag_multiarch_image() {

    local ACR_NAME="$1"
    local SRC_IMAGE="$2"
    local DEST_IMAGE="$3"

    if [[ -z "$ACR_NAME" || -z "$SRC_IMAGE" || -z "$DEST_IMAGE" ]]; then
        echo "Usage:"
        echo "retag_acr_multiarch_image <acr-name> <source-image> <dest-image>"
        echo
        echo "Example:"
        echo "retag_acr_multiarch_image myacr myapp:1.0.0 myapp:latest"
        return 1
    fi

    echo "=== Retagging multi-arch image ==="

    echo "ACR         : $ACR_NAME"
    echo "Source      : $SRC_IMAGE"
    echo "Destination : $DEST_IMAGE"
    az acr login -n "$ACR_NAME"
    az acr import \
        --name "$ACR_NAME" \
        --source "${ACR_NAME}.azurecr.io/${SRC_IMAGE}" \
        --image "$DEST_IMAGE"

    echo
    echo "=== VERIFYING IMAGE ==="

    docker buildx imagetools inspect \
        "${ACR_NAME}.azurecr.io/${DEST_IMAGE}"

    echo
    echo "=== RETAG COMPLETE ==="
}
