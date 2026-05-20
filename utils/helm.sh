
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
      -c|--chart)
        chart_dir="$2"
        shift 2
        ;;

      -a|--acr)
        acr_name="$2"
        shift 2
        ;;

      -r|--repository)
        repository="$2"
        shift 2
        ;;

      -v|--version)
        version="$2"
        shift 2
        ;;

      -d|--destination)
        destination="$2"
        shift 2
        ;;

      *)
        echo "Unknown argument: $1"
        return 1
        ;;
    esac
  done

  if [[ -z "$chart_dir" ]]; then
    echo "Error: Chart directory is required"
    return 1
  fi

  if [[ -z "$acr_name" ]]; then
    echo "Error: ACR name is required"
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
    echo "Error: Unable to locate packaged chart"
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
