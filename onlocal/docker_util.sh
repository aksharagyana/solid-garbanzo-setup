gchr_login(){
    echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin
}

# onlocal/setup.sh is often sourced from zsh; use 0-based arrays like bash.
_dev_docker_zsh_setup() {
    [[ -n "${ZSH_VERSION:-}" ]] && setopt KSH_ARRAYS 2>/dev/null
}
_dev_docker_zsh_setup

_dev_docker_read() {
    local prompt="$1"
    local varname="$2"
    printf '%s' "${prompt}" >&2
    read -r "${varname}"
}

_dev_docker_mapping_host() {
    local mapping="$1"
    _dev_docker_host_port "$(_dev_docker_normalize_port "$mapping")"
}

_dev_docker_port_in_use() {
    local port="$1"
    local docker_ports

    if lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; then
        return 0
    fi

    docker_ports=$(docker ps --format '{{.Ports}}' 2>/dev/null) || return 1
    grep -qE ":${port}->" <<< "${docker_ports}"
}

_dev_docker_port_taken() {
    local port="$1"
    shift
    local reserved="$1"

    if grep -qx "${port}" <<< "${reserved}"; then
        return 0
    fi

    _dev_docker_port_in_use "${port}"
}

_dev_docker_find_free_port() {
    local reserved="${1:-}"

    local port
    for port in $(seq 1000 9999); do
        if ! _dev_docker_port_taken "${port}" "${reserved}"; then
            echo "${port}"
            return 0
        fi
    done
    return 1
}

_dev_docker_host_port() {
    local mapping="$1"
    if [[ "$mapping" == *:* ]]; then
        echo "${mapping%%:*}"
    else
        echo "$mapping"
    fi
}

_dev_docker_normalize_port() {
    local mapping="$1"
    if [[ "$mapping" == *:* ]]; then
        echo "$mapping"
    else
        echo "${mapping}:${mapping}"
    fi
}

_dev_docker_replace_host_port() {
    local mapping="$1"
    local new_host="$2"

    if [[ "$mapping" == *:* ]]; then
        echo "${new_host}:${mapping#*:}"
    else
        echo "${new_host}:${new_host}"
    fi
}

_dev_docker_resolve_port() {
    _dev_docker_zsh_setup

    local mapping="$1"
    local reserved="$2"
    local label="${3:-}"

    local normalized host_port container_port alt_port choice resolved

    normalized=$(_dev_docker_normalize_port "$mapping")
    host_port=$(_dev_docker_host_port "$normalized")
    container_port="${normalized#*:}"

    if ! _dev_docker_port_taken "${host_port}" "${reserved}"; then
        echo "${normalized}"
        return 0
    fi

    alt_port=$(_dev_docker_find_free_port "${reserved}") || {
        echo "ERROR: Could not find a free 4-digit host port." >&2
        return 1
    }

    if [[ -n "${label}" ]]; then
        echo "${label}: host port ${host_port} is in use (container ${container_port})." >&2
    else
        echo "Host port ${host_port} is in use for mapping ${normalized}." >&2
    fi
    _dev_docker_read "Use ${alt_port} on the host instead? [Enter to accept, or type a port]: " choice

    if [[ -z "${choice}" ]]; then
        choice="${alt_port}"
    fi

    if ! [[ "${choice}" =~ ^[0-9]+$ ]] || (( choice < 1000 || choice > 9999 )); then
        echo "ERROR: Port must be a 4-digit number (1000-9999)." >&2
        return 1
    fi

    while _dev_docker_port_taken "${choice}" "${reserved}"; do
        alt_port=$(_dev_docker_find_free_port "${reserved}") || {
            echo "ERROR: Could not find a free 4-digit host port." >&2
            return 1
        }
        _dev_docker_read "Port ${choice} is also in use. Use ${alt_port}? [Enter to accept, or type a port]: " choice
        [[ -z "${choice}" ]] && choice="${alt_port}"
        if ! [[ "${choice}" =~ ^[0-9]+$ ]] || (( choice < 1000 || choice > 9999 )); then
            echo "ERROR: Port must be a 4-digit number (1000-9999)." >&2
            return 1
        fi
    done

    resolved=$(_dev_docker_replace_host_port "${normalized}" "${choice}")
    echo "${resolved}"
}

_dev_docker_resolve_all_ports() {
    _dev_docker_zsh_setup

    local profile="$1"
    shift

    local -a mappings=("$@")
    local -a resolved=()
    local reserved=""
    local mapping normalized host_port container_port alt_port
    local -a busy_labels=()
    local -a busy_mappings=()
    local -a busy_suggestions=()
    local planning_reserved="${reserved}"
    local j label choice resolved_mapping i count

    if [[ ${#mappings[@]} -eq 0 ]]; then
        RESOLVED_DEV_DOCKER_PORTS=()
        return 0
    fi

    for mapping in "${mappings[@]}"; do
        normalized=$(_dev_docker_normalize_port "$mapping")
        host_port=$(_dev_docker_host_port "$normalized")
        container_port="${normalized#*:}"

        if _dev_docker_port_taken "${host_port}" "${planning_reserved}"; then
            alt_port=$(_dev_docker_find_free_port "${planning_reserved}") || {
                echo "ERROR: Could not find a free 4-digit host port." >&2
                return 1
            }
            if [[ "${profile}" == "node" && "${host_port}" == "${container_port}" ]]; then
                label="container ${container_port}"
            else
                label="${normalized}"
            fi
            busy_labels+=("${label}")
            busy_mappings+=("${normalized}")
            busy_suggestions+=("${alt_port}")
            planning_reserved="${planning_reserved}"$'\n'"${alt_port}"
        fi
    done

    if [[ ${#busy_mappings[@]} -gt 0 ]]; then
        if [[ "${profile}" == "node" && ${#busy_mappings[@]} -gt 1 ]]; then
            echo "Some default node ports are already in use on the host:"
        else
            echo "Some requested ports are already in use on the host:"
        fi
        count=${#busy_mappings[@]}
        i=0
        while [[ $i -lt $count ]]; do
            echo "  ${busy_labels[$i]}  requested host $(_dev_docker_mapping_host "${busy_mappings[$i]}")  ->  suggested host ${busy_suggestions[$i]}"
            i=$((i + 1))
        done
        _dev_docker_read "Use suggested host ports? [Enter to accept]: " choice
        if [[ -n "${choice}" ]]; then
            echo "Press Enter without typing anything to accept the suggested ports." >&2
            return 1
        fi
    fi

    for mapping in "${mappings[@]}"; do
        resolved_mapping=""
        normalized=$(_dev_docker_normalize_port "$mapping")
        host_port=$(_dev_docker_host_port "$normalized")
        container_port="${normalized#*:}"

        if ! _dev_docker_port_taken "${host_port}" "${reserved}"; then
            resolved_mapping="${normalized}"
        elif [[ ${#busy_mappings[@]} -gt 0 ]]; then
            count=${#busy_mappings[@]}
            j=0
            while [[ $j -lt $count ]]; do
                if [[ "${busy_mappings[$j]}" == "${normalized}" ]]; then
                    choice="${busy_suggestions[$j]}"
                    while _dev_docker_port_taken "${choice}" "${reserved}"; do
                        choice=$(_dev_docker_find_free_port "${reserved}") || {
                            echo "ERROR: Could not find a free 4-digit host port." >&2
                            return 1
                        }
                    done
                    resolved_mapping=$(_dev_docker_replace_host_port "${normalized}" "${choice}")
                    break
                fi
                j=$((j + 1))
            done
            if [[ -z "${resolved_mapping}" ]]; then
                label=""
                [[ "${profile}" == "node" && "${host_port}" == "${container_port}" ]] && label="container ${container_port}"
                resolved_mapping=$(_dev_docker_resolve_port "${mapping}" "${reserved}" "${label}") || return 1
            fi
        else
            label=""
            [[ "${profile}" == "node" && "${host_port}" == "${container_port}" ]] && label="container ${container_port}"
            resolved_mapping=$(_dev_docker_resolve_port "${mapping}" "${reserved}" "${label}") || return 1
        fi

        resolved+=("${resolved_mapping}")
        reserved="${reserved}"$'\n'"$(_dev_docker_host_port "${resolved_mapping}")"
    done

    RESOLVED_DEV_DOCKER_PORTS=("${resolved[@]}")
}

_dev_docker_run_help() {
    local cmd="$1"
    cat <<EOF
Usage: ${cmd} [-p HOST[:CONTAINER]]... [-v SRC:DEST]...

Start a dev container with default code/utils mounts.

Options:
  -p    Publish a port (repeatable). Container port defaults to host port when omitted.
  -v    Mount a volume (repeatable)
  -h    Show this help
EOF
    if [[ "${cmd}" == "dev_node" ]]; then
        cat <<EOF

Node:
  You will be asked whether to publish default ports (3000, 7007, 5173).
  Use -p for any additional ports either way.
EOF
    fi
    cat <<EOF

Examples:
  ${cmd}
  ${cmd} -p 8080:8080
  ${cmd} -p 9000 -v ~/data:/data
EOF
}

_dev_docker_print_run_plan() {
    local container_name="$1"
    shift
    local -a ports=()
    local -a volumes=()

    while [[ $# -gt 0 && "$1" != "--" ]]; do
        ports+=("$1")
        shift
    done
    [[ $# -gt 0 ]] && shift
    volumes=("$@")

    echo
    echo "=== Dev container ==="
    echo "Container name: ${container_name}"
    echo "Port mappings:"
    if [[ ${#ports[@]} -eq 0 ]]; then
        echo "  (none)"
    else
        local mapping host_port container_port
        for mapping in "${ports[@]}"; do
            host_port="${mapping%%:*}"
            container_port="${mapping#*:}"
            echo "  host localhost:${host_port}  ->  container ${container_port}"
        done
        echo
        echo "  Host access requires binding your app to 0.0.0.0 inside the container."
        echo "  localhost:${container_port} works inside; 127.0.0.1 alone will break host curl."
        echo "  Examples:"
        echo "    mlflow ui --host 0.0.0.0 --port ${container_port}"
        echo "    uvicorn app:app --host 0.0.0.0 --port ${container_port}"
        echo "    flask run --host 0.0.0.0 --port ${container_port}"
    fi
    echo "Volume mounts:"
    for mapping in "${volumes[@]}"; do
        echo "  ${mapping%%:*} -> ${mapping#*:}"
    done
    echo "Exit bash to stop and remove the container."
    echo "====================="
    echo
}

_dev_docker_run() {
    _dev_docker_zsh_setup

    local cmd_name="$1"
    local image="$2"
    local profile="$3"
    shift 3

    local -a extra_ports=()
    local -a extra_volumes=()
    local -a default_ports=()
    local -a all_ports=()
    local -a all_volumes=()
    local -a resolved_ports=()
    local -a docker_args=()

    local OPTIND
    OPTIND=1
    while getopts ":p:v:h" opt; do
        case "${opt}" in
            p)
                extra_ports+=("$OPTARG")
                ;;
            v)
                extra_volumes+=("$OPTARG")
                ;;
            h)
                _dev_docker_run_help "${cmd_name}"
                return 0
                ;;
            \?)
                echo "ERROR: Invalid option -$OPTARG" >&2
                _dev_docker_run_help "${cmd_name}"
                return 1
                ;;
            :)
                echo "ERROR: Option -$OPTARG requires an argument" >&2
                _dev_docker_run_help "${cmd_name}"
                return 1
                ;;
        esac
    done

    all_volumes=(
        "${CODE_ON_MAC}:${CODE_ON_CONT}"
        "${UTILS_ON_MAC}:${UTILS_ON_CONT}"
    )

    case "${profile}" in
        node)
            all_volumes+=("/var/run/docker.sock:/var/run/docker.sock")
            local use_default_ports=""
            echo "Default node ports: 3000 (app), 7007 (Backstage), 5173 (Vite)"
            _dev_docker_read "Publish default node ports? [y/N]: " use_default_ports
            if [[ "${use_default_ports}" =~ ^[Yy]$ ]]; then
                default_ports=(3000:3000 7007:7007 5173:5173)
            else
                echo "Skipping default node ports. Use -p to publish ports if needed."
            fi
            ;;
    esac

    all_ports=("${default_ports[@]}" "${extra_ports[@]}")
    all_volumes+=("${extra_volumes[@]}")

    gchr_login

    if [[ ${#all_ports[@]} -gt 0 ]]; then
        _dev_docker_resolve_all_ports "${profile}" "${all_ports[@]}" || return 1
        resolved_ports=("${RESOLVED_DEV_DOCKER_PORTS[@]}")
    fi

    local container_name
    container_name="dev-${profile}-$(date +%Y%m%d%H%M%S)-${RANDOM}"

    docker_args=(
        run -it --rm --pull=always
        --env-file "${DOCKER_ENV_FILE}"
        --name "${container_name}"
    )

    for mapping in "${resolved_ports[@]}"; do
        docker_args+=(-p "${mapping}")
    done

    if [[ ${#resolved_ports[@]} -gt 0 ]]; then
        docker_args+=(
            -e HOST=0.0.0.0
            -e FLASK_RUN_HOST=0.0.0.0
        )
    fi

    for mapping in "${all_volumes[@]}"; do
        docker_args+=(-v "${mapping}")
    done

    docker_args+=("${image}" bash)

    _dev_docker_print_run_plan "${container_name}" "${resolved_ports[@]}" -- "${all_volumes[@]}"

    docker "${docker_args[@]}"
    local rc=$?

    echo "Container ${container_name} stopped and removed."
    return $rc
}

dev_go(){
    _dev_docker_run dev_go "${GO_IMAGE}" go "$@"
}

dev_python(){
    _dev_docker_run dev_python "${PYTHON_IMAGE}" python "$@"
}

dev_node(){
    _dev_docker_run dev_node "${NODE_IMAGE}" node "$@"
}

dev_debian(){
    _dev_docker_run dev_debian "${DEBIAN_IMAGE}" debian "$@"
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
docker_build_multiarch_image() {

    local INPUT_PATH="${1:-.}"
    local IMAGE_NAME="${2:-}"

    shift 2

    local BUILD_CONTEXT="."
    local DOCKERFILE_PATH=""
    local BUILD_ARGS=()

    if [[ -z "$IMAGE_NAME" ]]; then
        echo "Usage:"
        echo "docker_build_multiarch_image <dockerfile-or-context> <image:tag> [KEY=VALUE ...]"
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
