gchr_login(){
    echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin
}

dev_go(){
    docker run -it --pull=always --env-file "${DOCKER_ENV_FILE}" -v "${CODE_ON_MAC}":"${CODE_ON_CONT}" -v "${UTILS_ON_MAC}":"${UTILS_ON_CONT}" "${GO_IMAGE}" bash
}

dev_python(){
    docker run -it --pull=always --env-file "${DOCKER_ENV_FILE}" -v "${CODE_ON_MAC}":"${CODE_ON_CONT}" -v "${UTILS_ON_MAC}":"${UTILS_ON_CONT}" "${PYTHON_IMAGE}" bash
}

dev_node(){
    docker run -it --pull=always --env-file "${DOCKER_ENV_FILE}" -p 3000:3000 -p 7007:7007 -p 5173:5173  -v /var/run/docker.sock:/var/run/docker.sock -v "${CODE_ON_MAC}":"${CODE_ON_CONT}" -v "${UTILS_ON_MAC}":"${UTILS_ON_CONT}" "${DEBIAN_IMAGE}" bash
}

dev_debian(){
    docker run -it --pull=always --env-file "${DOCKER_ENV_FILE}" -v "${CODE_ON_MAC}":"${CODE_ON_CONT}" -v "${UTILS_ON_MAC}":"${UTILS_ON_CONT}" "${DEBIAN_IMAGE}" bash
}

docker_cleanup(){
    echo -e "\nStopping all running containers..."
    docker stop $(docker ps -q) 2>/dev/null || true

    echo "Removing all containers (including stopped ones)..."
    docker rm -f $(docker ps -a -q) 2>/dev/null || true

    echo "Removing all images..."
    docker rmi -f $(docker images -q) 2>/dev/null || true

    echo "Removing all volumes..."
    docker volume rm -f $(docker volume ls -q) 2>/dev/null || true

    echo "Removing all custom networks..."
    docker network rm $(docker network ls --filter "type=custom" -q) 2>/dev/null || true

    echo "Clearing build cache and remaining system resources..."
    docker builder prune -a -f
    docker system prune -a --volumes -f

    echo -e "\n=== DOCKER NUCLEAR CLEANUP COMPLETED at $(date) ==="

    echo "Final disk usage:"
    docker system df -v || echo "Docker info not available (everything cleaned)."

    echo -e "\nAll Docker resources have been aggressively deleted."
}

###############################################################################
# build_multiarch_image
#
# Build and push multi-architecture Docker image.
#
# Arguments:
#   $1 = Docker context path
#   $2 = Full image name with tag
#
# Examples:
#   build_multiarch_image . myacr.azurecr.io/api:1.0.0
#
#   build_multiarch_image ./src \
#       ghcr.io/company/app:latest
#
# build_multiarch_image \
# ado-agent-ubuntu-j8.dockerfile \
# usz17/java8-ado:1.0.0 \
# baseImageTag=eclipse-temurin:8-jdk \
# MAVEN_VERSION=3.9.6 \
# NODE_VERSION=20
#
# Behaviour:
# - If path is "." -> uses ./Dockerfile
# - Automatically ensures buildx exists/running
# - Builds amd64 + arm64
# - Pushes manifest/image
###############################################################################
build_multiarch_image() {

    local INPUT_PATH="${1:-.}"
    local IMAGE_NAME="${2:-}"

    shift 2

    local BUILD_CONTEXT="."
    local DOCKERFILE_PATH=""
    local BUILD_ARGS=()

    if [[ -z "$IMAGE_NAME" ]]; then
        echo "Usage:"
        echo "build_multiarch_image <dockerfile-or-context> <image:tag> [KEY=VALUE ...]"
        return 1
    fi

    echo "=== Ensuring buildx ready ==="

    install_and_start_buildx

    echo "=== Resolving Dockerfile ==="

    # Current directory
    if [[ "$INPUT_PATH" == "." ]]; then

        BUILD_CONTEXT="."
        DOCKERFILE_PATH="./Dockerfile"

    # Direct Dockerfile
    elif [[ -f "$INPUT_PATH" ]]; then

        DOCKERFILE_PATH="$INPUT_PATH"
        BUILD_CONTEXT="$(dirname "$INPUT_PATH")"

        [[ "$BUILD_CONTEXT" == "." ]] && BUILD_CONTEXT="."

    # Directory
    elif [[ -d "$INPUT_PATH" ]]; then

        BUILD_CONTEXT="$INPUT_PATH"
        DOCKERFILE_PATH="${INPUT_PATH}/Dockerfile"

    else
        echo "ERROR: Invalid path: $INPUT_PATH"
        return 1
    fi

    if [[ ! -f "$DOCKERFILE_PATH" ]]; then
        echo "ERROR: Dockerfile not found: $DOCKERFILE_PATH"
        return 1
    fi

    echo "=== Processing build args ==="

    while [[ $# -gt 0 ]]; do

        if [[ "$1" == *=* ]]; then
            BUILD_ARGS+=(--build-arg "$1")
        else
            echo "WARNING: Ignoring invalid build arg: $1"
        fi

        shift
    done

    echo "=== Building multi-arch image ==="

    echo "Build Context : $BUILD_CONTEXT"
    echo "Dockerfile    : $DOCKERFILE_PATH"
    echo "Image         : $IMAGE_NAME"
    echo "Platforms     : linux/amd64,linux/arm64"

    if [[ ${#BUILD_ARGS[@]} -gt 0 ]]; then
        echo "Build Args:"
        printf '  %s\n' "${BUILD_ARGS[@]}"
    fi

    docker buildx build \
        --platform linux/amd64,linux/arm64 \
        --file "$DOCKERFILE_PATH" \
        --tag "$IMAGE_NAME" \
        "${BUILD_ARGS[@]}" \
        --push \
        "$BUILD_CONTEXT"

    echo
    echo "=== BUILD COMPLETE ==="
    echo "$IMAGE_NAME"
}
