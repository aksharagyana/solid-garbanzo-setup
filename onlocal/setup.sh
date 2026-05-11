setup_path="/Users/$(whoami)/code/solid-garbanzo-setup/onlocal"

source_all_sh() {

    local DIR="${1:-.}"

    # expand ~
    DIR="${DIR/#\~/$HOME}"

    if [[ ! -d "$DIR" ]]; then
        echo "ERROR: Directory not found: $DIR"
        return 1
    fi

    # zsh-safe + bash-safe sourced tracking
    typeset -gA __SOURCED_SH_FILES 2>/dev/null || true

    local found=0

    for file in "$DIR"/*.sh(N); do

        found=1

        # absolute path
        local abs_file
        abs_file="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"

        # skip already sourced
        if [[ -n "${__SOURCED_SH_FILES[$abs_file]}" ]]; then
            echo "Skipping already sourced: $abs_file"
            continue
        fi

        echo "Sourcing: $abs_file"

        source "$abs_file"

        __SOURCED_SH_FILES[$abs_file]=1
    done

    if [[ $found -eq 0 ]]; then
        echo "No .sh files found in: $DIR"
    fi
}

source "/Users/$(whoami)/code/env.sh"
source "${setup_path}/docker_env.sh"
source "${setup_path}/docker_util.sh"
source "${setup_path}/ai.sh"
source "${setup_path}/dns.sh"
source "${setup_path}/tools.sh"
source "${setup_path}/acr.sh"

# source_all_sh "${COMMON_PROJECT_HELPER}"
