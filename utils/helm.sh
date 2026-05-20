
# Local chart example:
# helm_upgrade \
#   -n dev \
#   -c ./charts/myapp \
#   -f values.yaml

# OCI chart example:
# helm_upgrade \
#   -n dev \
#   -c oci://my-registry.com/charts/myapp \
#   -f values.yaml

# OCI chart example with version:
# helm_upgrade \
#   -n dev \
#   -c oci://my-registry.com/charts/myapp --version 1.0.0 \
#   -f values.yaml

# Remote Helm repository example:
# helm_upgrade \
#   -n prod \
#   -c bitnami/nginx \
#   -f values.yaml

# It will also support other Helm flags automatically, for example:
# --wait
# --timeout 10m
# --atomic
# --create-namespace
# --set image.tag=v1
# --history-max 5

helm_upgrade_help() {
    cat <<'EOF'
Usage: helm_upgrade -n <namespace> -c <chart> [-f <values.yaml>]... [-r <release>] [helm flags...]

Required:
  -n, --namespace <ns>     Kubernetes namespace
  -c, --chart <chart>      Local path, OCI URL, or repo/chart (e.g. bitnami/nginx)

Optional:
  -f, --values <file>      Values file (repeatable)
  -r, --release <name>     Release name (default: chart basename)
  -h, --help               Show this help

Additional helm flags are passed through, for example:
  --version 1.0.0 --wait --timeout 10m --atomic --create-namespace
  --set image.tag=v1 --history-max 5

Examples:
  helm_upgrade -n dev -c ./charts/myapp -f values.yaml
  helm_upgrade -n dev -c oci://my-registry.com/charts/myapp --version 1.0.0 -f values.yaml
  helm_upgrade -n prod -c bitnami/nginx -f values.yaml --wait --atomic

See also: helm_dryrun (same args, adds --dry-run --debug)
EOF
}

helm_package_push_help() {
    cat <<'EOF'
Usage: helm_package_push -c <chart_dir> -a <acr_name> [-r <repo>] [-v <version>] [-d <dest>]

Required:
  -c, --chart <dir>        Chart directory to package
  -a, --acr <name>         Azure Container Registry name (login + push target)

Optional:
  -r, --repository <path>  OCI repository path under ACR (default: helm)
  -v, --version <ver>      Chart version (default: version from Chart.yaml)
  -d, --destination <dir>  Output directory for packaged .tgz (default: ./dist)
  -h, --help               Show this help

Example:
  helm_package_push -c ./charts/myapp -a myacr -r platform/charts -v 1.2.3
EOF
}

helm_upgrade() {
    local namespace=""
    local chart_path=""
    local release_name=""
    local values_args=()
    local extra_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                helm_upgrade_help
                return 0
                ;;
            -n|--namespace)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: -n requires a namespace" >&2
                    return 1
                fi
                namespace="$2"
                shift 2
                ;;
            -c|--chart)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: -c requires a chart path or reference" >&2
                    return 1
                fi
                chart_path="$2"
                shift 2
                ;;
            -f|--values)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: -f requires a values file path" >&2
                    return 1
                fi
                if [[ ! -f "$2" ]]; then
                    echo "Error: File not found: $2" >&2
                    return 1
                fi
                values_args+=("-f" "$2")
                shift 2
                ;;
            -r|--release)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: -r requires a release name" >&2
                    return 1
                fi
                release_name="$2"
                shift 2
                ;;
            *)
                extra_args+=("$1")
                shift
                ;;
        esac
    done

    if [[ -z "$namespace" ]]; then
        echo "Error: Namespace is required (-n)" >&2
        echo "Run 'helm_upgrade -h' for usage." >&2
        return 1
    fi

    if [[ -z "$chart_path" ]]; then
        echo "Error: Chart path/repository is required (-c)" >&2
        echo "Run 'helm_upgrade -h' for usage." >&2
        return 1
    fi

    if ! command -v helm >/dev/null 2>&1; then
        echo "Error: helm is not installed or not in PATH" >&2
        return 1
    fi

    if [[ -z "$release_name" ]]; then
        release_name="$(basename "$chart_path")"
        release_name="${release_name##*/}"
    fi

    echo "Running:"
    echo "helm upgrade --install $release_name $chart_path -n $namespace ${values_args[*]} ${extra_args[*]}"

    helm upgrade --install \
        "$release_name" \
        "$chart_path" \
        -n "$namespace" \
        "${values_args[@]}" \
        "${extra_args[@]}"
}

helm_dryrun() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        helm_upgrade_help
        echo
        echo "helm_dryrun runs helm_upgrade with --dry-run --debug."
        return 0
    fi
    helm_upgrade "$@" --dry-run --debug
}

# helm_package_push \
#   -c ./charts/myapp \
#   -a myacr \
#   -r platform/charts \
#   -v 1.2.3


helm_package_push() {
    local chart_dir=""
    local acr_name=""
    local repository="helm"
    local version=""
    local destination="./dist"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                helm_package_push_help
                return 0
                ;;
            -c|--chart)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: -c requires a chart directory" >&2
                    return 1
                fi
                chart_dir="$2"
                shift 2
                ;;
            -a|--acr)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: -a requires an ACR name" >&2
                    return 1
                fi
                acr_name="$2"
                shift 2
                ;;
            -r|--repository)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: -r requires a repository path" >&2
                    return 1
                fi
                repository="$2"
                shift 2
                ;;
            -v|--version)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: -v requires a version" >&2
                    return 1
                fi
                version="$2"
                shift 2
                ;;
            -d|--destination)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: -d requires a destination directory" >&2
                    return 1
                fi
                destination="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                echo "Run 'helm_package_push -h' for usage." >&2
                return 1
                ;;
        esac
    done

    if [[ -z "$chart_dir" ]]; then
        echo "Error: Chart directory is required (-c)" >&2
        echo "Run 'helm_package_push -h' for usage." >&2
        return 1
    fi

    if [[ ! -d "$chart_dir" ]]; then
        echo "Error: Chart directory not found: $chart_dir" >&2
        return 1
    fi

    if [[ -z "$acr_name" ]]; then
        echo "Error: ACR name is required (-a)" >&2
        echo "Run 'helm_package_push -h' for usage." >&2
        return 1
    fi

    if ! command -v helm >/dev/null 2>&1; then
        echo "Error: helm is not installed or not in PATH" >&2
        return 1
    fi

    if ! command -v az >/dev/null 2>&1; then
        echo "Error: Azure CLI (az) is not installed or not in PATH" >&2
        return 1
    fi

    mkdir -p "$destination"

    echo "Logging into ACR..."
    az acr login --name "$acr_name" || return 1

    local package_output
    local chart_package

    echo "Packaging chart..."

    if [[ -n "$version" ]]; then
        package_output=$(helm package "$chart_dir" \
            --version "$version" \
            --destination "$destination") || return 1
    else
        package_output=$(helm package "$chart_dir" \
            --destination "$destination") || return 1
    fi

    chart_package=$(echo "$package_output" | awk '{print $NF}')

    if [[ ! -f "$chart_package" ]]; then
        echo "Error: Unable to locate packaged chart" >&2
        return 1
    fi

    local acr_login_server
    acr_login_server=$(az acr show \
        --name "$acr_name" \
        --query loginServer \
        -o tsv) || return 1

    local oci_repo="oci://${acr_login_server}/${repository}"

    echo "Pushing chart:"
    echo "$chart_package -> $oci_repo"

    helm push "$chart_package" "$oci_repo"
}
