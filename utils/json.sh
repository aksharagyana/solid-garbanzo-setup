#!/bin/bash
# ================================================
# JSON Utilities - Bash wrapper for json_align.py
# ================================================

if [[ -n "${ZSH_VERSION:-}" ]]; then
    _JSON_SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
else
    _JSON_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
_JSON_PY="${_JSON_SCRIPT_DIR}/json_align.py"

function _json_show_help() {
    local func="$1"
    case $func in
        json_align)
            echo "Usage: json_align <file.json> [-o <output.json>] [--output-dir <dir>] [-q]"
            echo "  Create a consistently ordered JSON file for visual diffing."
            echo ""
            echo "  Rules:"
            echo "    - Object keys are sorted alphabetically at every level"
            echo "    - Primitive arrays are sorted by value"
            echo "    - Object arrays are sorted by each object's first key value"
            echo ""
            echo "  Default output: <stem>_aligned.json beside the input file"
            echo ""
            echo "  -o            Explicit output file path"
            echo "  --output-dir  Write default-named output into this directory"
            echo "  -q            Suppress progress messages"
            ;;
        *)
            echo "Unknown function"
            ;;
    esac
}

function _json_require_python() {
    if [[ ! -f "$_JSON_PY" ]]; then
        echo "Error: Python helper not found: $_JSON_PY" >&2
        return 1
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        echo "Error: python3 is required but not installed" >&2
        return 1
    fi
}

# ================================================
# Align a JSON file for visual diffing
# ================================================
json_align() {
    if ! _json_require_python; then
        return 1
    fi

    if [[ $# -lt 1 ]]; then
        echo "Error: json_align requires a JSON file path" >&2
        _json_show_help "json_align"
        return 1
    fi

    local input="$1"
    shift

    local -a py_args=("$input")

    OPTIND=1
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o)
                py_args+=(-o "$2")
                shift 2
                ;;
            --output-dir)
                py_args+=(--output-dir "$2")
                shift 2
                ;;
            -q)
                py_args+=(-q)
                shift
                ;;
            -h)
                _json_show_help "json_align"
                return 0
                ;;
            *)
                echo "Invalid option: $1" >&2
                _json_show_help "json_align"
                return 1
                ;;
        esac
    done

    (cd "$_JSON_SCRIPT_DIR" && python3 "$_JSON_PY" "${py_args[@]}")
}

# ================================================
# Help Command
# ================================================
json_help() {
    echo "JSON Utility Helper Functions"
    echo ""
    echo "Available functions:"
    echo "  json_align   - Create a consistently ordered JSON file"
    echo "  json_help    - Show this help"
    echo ""
    echo "Use -h with any function for detailed usage."
    echo ""
    echo "Example:"
    echo "  source utils/json.sh"
    echo "  json_align utils/json/builtin.json"
    echo "  json_align utils/json/custom.json"
    echo "  # Compare builtin_aligned.json vs custom_aligned.json in Beyond Compare"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    json_help
fi
