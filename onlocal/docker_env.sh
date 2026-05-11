#!/usr/bin/env zsh

# =============================================
# Generate .env file from specific environment variables
# (ZSH compatible)
# =============================================

# Output file (fallback to .env if not set)
OUTPUT_FILE="${DOCKER_ENV_FILE:-.env}"

# Mapping: OUTPUT_KEY -> ENV_VARIABLE_NAME
typeset -A MAPPING=(
    TENV_GITHUB_TOKEN GITHUB_TOKEN
    NPM_TOKEN         NPM_TOKEN
    GITLAB_TOKEN      GITLAB_TOKEN
    PROJECT_ENV       PROJECT_ENV
)

echo "=== Generating ${OUTPUT_FILE} from selected environment variables ==="

# Remove existing file
rm -f "$OUTPUT_FILE"

{
    echo "# Docker ${OUTPUT_FILE} file - Generated on $(date)"
    echo ""

    for output_key in ${(k)MAPPING}; do
        env_var_name="${MAPPING[$output_key]}"

        # ZSH indirect expansion
        value="${(P)env_var_name}"

        if [[ -z "$value" ]]; then
            echo "⚠ Warning: $env_var_name is not set" >&2
        fi

        echo "${output_key}=${value}"
        count="${count}+1"
    done | sort

} > "$OUTPUT_FILE"

echo "✓ Successfully created ${OUTPUT_FILE} with variables."
# echo ""
# echo "Preview:"
# cat "$OUTPUT_FILE"