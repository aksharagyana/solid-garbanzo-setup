
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

helm_upgrade() {
  local namespace=""
  local chart_path=""
  local values_args=()
  local extra_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--namespace)
        namespace="$2"
        shift 2
        ;;

      -c|--chart)
        chart_path="$2"
        shift 2
        ;;

      -f|--values)
        if [[ ! -f "$2" ]]; then
          echo "Error: File not found: $2"
          return 1
        fi

        values_args+=("-f" "$2")
        shift 2
        ;;

      *)
        extra_args+=("$1")
        shift
        ;;
    esac
  done

  if [[ -z "$namespace" ]]; then
    echo "Error: Namespace is required"
    return 1
  fi

  if [[ -z "$chart_path" ]]; then
    echo "Error: Chart path/repository is required"
    return 1
  fi

  local release_name
  release_name="$(basename "$chart_path")"

  # Remove possible repo prefix from release name
  release_name="${release_name##*/}"

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
  helm_upgrade "$@" --dry-run --debug
}
