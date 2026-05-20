#!/bin/bash
# Shared helper: source every *.sh in a directory (bash + zsh).
# Usage: source_all_sh <dir> [exclude_basename ...]

source_all_sh() {
    local DIR="${1:-.}"
    shift

    local EXCLUDES=("$@")
    local exclude skip base file found=0

    DIR="${DIR/#\~/$HOME}"

    if [[ ! -d "$DIR" ]]; then
        echo "ERROR: Directory not found: $DIR"
        return 1
    fi

    if [[ -n "${ZSH_VERSION:-}" ]]; then
        typeset -gA __SOURCED_SH_FILES 2>/dev/null || true
    elif [[ -z "${__SOURCED_SH_FILES_INIT:-}" ]]; then
        declare -gA __SOURCED_SH_FILES
        __SOURCED_SH_FILES_INIT=1
    fi

    _source_all_sh_file() {
        local file="$1"
        found=1

        base="$(basename "$file")"
        for exclude in "${EXCLUDES[@]}"; do
            if [[ "$base" == "$exclude" ]]; then
                return 0
            fi
        done

        local abs_file
        abs_file="$(cd "$(dirname "$file")" && pwd)/$base"

        if [[ -n "${__SOURCED_SH_FILES[$abs_file]:-}" ]]; then
            echo "Skipping already sourced: $abs_file"
            return 0
        fi

        echo "Sourcing: $abs_file"
        # shellcheck source=/dev/null
        source "$abs_file"
        __SOURCED_SH_FILES[$abs_file]=1
    }

    if [[ -n "${ZSH_VERSION:-}" ]]; then
        setopt local_options null_glob
        for file in "$DIR"/*.sh; do
            _source_all_sh_file "$file"
        done
    else
        shopt -s nullglob
        for file in "$DIR"/*.sh; do
            _source_all_sh_file "$file"
        done
        shopt -u nullglob
    fi

    if [[ $found -eq 0 ]]; then
        echo "No .sh files found in: $DIR"
    fi
}
