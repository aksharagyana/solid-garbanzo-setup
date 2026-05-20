#!/bin/bash
# Shared helpers for *.sh discovery (bash + zsh).
# Usage:
#   source_all_sh <dir> [exclude_basename ...]
#   register_all_sh <bashrc_file> <dir> [exclude_basename ...]

_sh_normalize_dir() {
    local dir="${1/#\~/$HOME}"
    if [[ ! -d "$dir" ]]; then
        echo "ERROR: Directory not found: $dir" >&2
        return 1
    fi
    printf '%s' "$dir"
}

_sh_is_excluded() {
    local base="$1"
    shift
    local exc
    for exc in "$@"; do
        [[ "$base" == "$exc" ]] && return 0
    done
    return 1
}

_sh_init_source_tracking() {
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        typeset -gA __SOURCED_SH_FILES 2>/dev/null || true
    elif [[ -z "${__SOURCED_SH_FILES_INIT:-}" ]]; then
        declare -gA __SOURCED_SH_FILES
        __SOURCED_SH_FILES_INIT=1
    fi
}

_sh_foreach() {
    local dir="$1"
    local callback="$2"
    shift 2
    local excludes=("$@")
    local file base found=0

    _sh_visit() {
        local file="$1"
        base="$(basename "$file")"
        _sh_is_excluded "$base" "${excludes[@]}" && return 0
        found=1
        "$callback" "$file" "$base"
    }

    if [[ -n "${ZSH_VERSION:-}" ]]; then
        setopt local_options null_glob
        for file in "$dir"/*.sh; do
            _sh_visit "$file"
        done
    else
        shopt -s nullglob
        for file in "$dir"/*.sh; do
            _sh_visit "$file"
        done
        shopt -u nullglob
    fi

    if [[ $found -eq 0 ]]; then
        echo "No .sh files found in: $dir"
    fi
}

_sh_source_file() {
    local file="$1"
    local base="$2"
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

_sh_register_file() {
    local file="$1"
    local base="$2"
    local source_line

    echo "⚙️  Processing $base..."

    chmod u+x "$file"

    source_line="source $file"
    if ! grep -Fxq "$source_line" "$_REGISTER_BASHRC"; then
        echo "$source_line" >> "$_REGISTER_BASHRC"
        echo "✅ Added source line for $base"
    else
        echo "ℹ️  Source line for $base already exists in $_REGISTER_BASHRC"
    fi
}

source_all_sh() {
    local dir
    dir="$(_sh_normalize_dir "${1:-.}")" || return 1
    shift

    _sh_init_source_tracking
    _sh_foreach "$dir" _sh_source_file "$@"
}

register_all_sh() {
    local bashrc_file="$1"
    local dir
    dir="$(_sh_normalize_dir "${2:-.}")" || return 1
    shift 2

    _REGISTER_BASHRC="$bashrc_file"
    _sh_foreach "$dir" _sh_register_file "$@"
}
