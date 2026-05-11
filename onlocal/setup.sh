setup_path="/Users/$(whoami)/code/solid-garbanzo-setup/onlocal"

source_all_sh() {
    local DIR="${1:-.}"

    # expand ~
    DIR="${DIR/#\~/$HOME}"

    if [[ ! -d "$DIR" ]]; then
        echo "ERROR: Directory not found: $DIR"
        return 1
    fi

    # track sourced files (global associative array)
    if [[ -z "${__SOURCED_SH_FILES_INIT:-}" ]]; then
        declare -gA __SOURCED_SH_FILES
        __SOURCED_SH_FILES_INIT=1
    fi

    local file
    shopt -s nullglob

    for file in "$DIR"/*.sh; do
        # normalize path
        local abs_file
        abs_file="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"

        # skip already sourced files
        if [[ -n "${__SOURCED_SH_FILES[$abs_file]:-}" ]]; then
            echo "Skipping already sourced: $abs_file"
            continue
        fi

        echo "Sourcing: $abs_file"
        # shellcheck source=/dev/null
        source "$abs_file"

        __SOURCED_SH_FILES["$abs_file"]=1
    done

    shopt -u nullglob
}

source "/Users/$(whoami)/code/env.sh"
source "${setup_path}/docker_env.sh"
source "${setup_path}/docker_util.sh"
source "${setup_path}/ai.sh"
source "${setup_path}/dns.sh"

source_all_sh "${COMMON_PROJECT_HELPER}"