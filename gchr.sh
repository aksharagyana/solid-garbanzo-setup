copy_multiarch_to_ghcr() {
    local image="$1"         # e.g. panretr:latest
    local ghcr_user="${GHCR_USER}"     # GitHub username/org
    local docker_user="${DOCKER_HUB_USER}"   # Docker Hub username
    local docker_pass="${DOCKER_HUB_PASS}"   # Docker Hub token/pass
    local ghcr_token="${GHCR_TOKEN}"    # GitHub PAT (write:packages)

    if [[ -z "$image" || -z "$ghcr_user" || -z "$docker_user" ||
          -z "$docker_pass" || -z "$ghcr_token" ]]; then
        echo "Usage: copy_multiarch_to_ghcr <image:tag> <ghcr-user> <docker-user> <docker-pass> <ghcr-token>"
        return 1
    fi

    # Login to Docker Hub
    echo "$docker_pass" | skopeo login docker.io -u "$docker_user" --password-stdin \
        || { echo "Docker Hub login failed"; return 1; }

    # Login to GHCR
    echo "$ghcr_token" | skopeo login ghcr.io -u "$ghcr_user" --password-stdin \
        || { echo "GHCR login failed"; return 1; }

    # Copy all architectures
    skopeo copy --all \
        "docker://docker.io/${image}" \
        "docker://ghcr.io/${ghcr_user}/${image}"
}
