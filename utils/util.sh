#!/bin/bash


dos2_unix(){

# Base directory (default to current if not specified)
BASE_DIR="$(pwd)"

# Find all regular files (excluding binary ones is optional)
find "$BASE_DIR" -type f -print0 | while IFS= read -r -d '' file; do
  echo "Processing: $file"
  dos2unix "$file" 2>/dev/null || echo "Skipped (maybe already Unix or binary): $file"
done

}
 

generate_ssh_keypair_rfc4716() {

# ------------------------------------------------------------------------------
# Function: generate_ssh_keypair_rfc4716
# Creates an SSH key pair and exports the public key in RFC4716 format.
# ------------------------------------------------------------------------------
# Usage:
#   generate_ssh_keypair_rfc4716 [-t rsa|ed25519] [-b bits] [-f keyfile] [-c comment] [-p passphrase]
# Example:
#   generate_ssh_keypair_rfc4716 -t ed25519 -f ~/.ssh/id_ed25519_test -c "user@example.com"
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------
# Example usage:
# generate_ssh_keypair_rfc4716 -t rsa -b 4096 -f ~/.ssh/my_rsa_key -c "me@example.com"
# ------------------------------------------------------------------


  local key_type="ed25519"
  local rsa_bits=4096
  local keyfile="$HOME/.ssh/id_ed25519"
  local comment=""
  local passphrase=""

  # --- Parse arguments ---
  while getopts ":t:b:f:c:p:h" opt; do
    case "${opt}" in
      t) key_type="${OPTARG}" ;;
      b) rsa_bits="${OPTARG}" ;;
      f) keyfile="${OPTARG}" ;;
      c) comment="${OPTARG}" ;;
      p) passphrase="${OPTARG}" ;;
      h)
        echo "Usage: generate_ssh_keypair_rfc4716 [-t rsa|ed25519] [-b bits] [-f keyfile] [-c comment] [-p passphrase]"
        return 0
        ;;
      \?) echo "Invalid option: -$OPTARG" >&2; return 1 ;;
      :) echo "Option -$OPTARG requires an argument." >&2; return 1 ;;
    esac
  done

  # --- Prerequisites ---
  if ! command -v ssh-keygen >/dev/null 2>&1; then
    echo "Error: ssh-keygen not found. Please install OpenSSH client tools." >&2
    return 2
  fi

  mkdir -p "$(dirname "${keyfile}")"

  if [[ -e "${keyfile}" || -e "${keyfile}.pub" ]]; then
    echo "Error: Key file already exists (${keyfile}). Move or delete it first." >&2
    return 3
  fi

  echo "Generating ${key_type} SSH keypair..."

  # --- Generate the key ---
  if [[ "${key_type}" == "rsa" ]]; then
    if [[ -z "${passphrase}" ]]; then
      ssh-keygen -t rsa -b "${rsa_bits}" -f "${keyfile}" -N "" -C "${comment}" -q
    else
      ssh-keygen -t rsa -b "${rsa_bits}" -f "${keyfile}" -N "${passphrase}" -C "${comment}" -q
    fi
  elif [[ "${key_type}" == "ed25519" ]]; then
    if [[ -z "${passphrase}" ]]; then
      ssh-keygen -t ed25519 -f "${keyfile}" -N "" -C "${comment}" -q
    else
      ssh-keygen -t ed25519 -f "${keyfile}" -N "${passphrase}" -C "${comment}" -q
    fi
  else
    echo "Error: Unsupported key type '${key_type}'. Use rsa or ed25519." >&2
    return 4
  fi

  local pubfile="${keyfile}.pub"
  local rfcfile="${keyfile}-rfc4716.pub"

  echo "Exporting RFC4716 public key -> ${rfcfile}"
  if ! ssh-keygen -e -f "${pubfile}" -m RFC4716 > "${rfcfile}"; then
    echo "Error: Failed to create RFC4716 public key." >&2
    return 5
  fi

  chmod 600 "${keyfile}"
  chmod 644 "${pubfile}" "${rfcfile}"

  echo "✅ Key generation complete."
  echo "Private key: ${keyfile}"
  echo "OpenSSH public key: ${pubfile}"
  echo "RFC4716 public key: ${rfcfile}"
}

# Reusable function to generate public key from a private key file
# Usage examples:
#   public_key_from_private -p ~/.ssh/id_rsa
#   public_key_from_private -p ./mykey.pem -f pem
#   public_key_from_private -p ./encrypted_key -f ssh --passphrase
#   public_key_from_private -h

public_key_from_private() {
    local private_key_file=""
    local output_format="ssh"    # default: OpenSSH format
    local show_help=false
    local use_passphrase=false
    # Reset OPTIND so getopts parses from $1 when function is called from a sourced script
    OPTIND=1
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--private-key)
                private_key_file="$2"
                shift 2
                ;;
            -f|--format)
                output_format="$2"
                shift 2
                ;;
            --passphrase)
                use_passphrase=true
                shift
                ;;
            -h|--help)
                show_help=true
                shift
                ;;
            *)
                echo "Unknown option: $1" >&2
                show_help=true
                break
                ;;
        esac
    done

    if [[ "$show_help" = true || -z "$private_key_file" ]]; then
        cat >&2 <<'EOF'
Usage: public_key_from_private -p <private-key-file> [options]

Options:
  -p, --private-key FILE     Path to the private key file (required)
  -f, --format FORMAT        Output format: ssh (default) or pem
  --passphrase               Prompt for passphrase if key is encrypted
  -h, --help                 Show this help message

Examples:
  public_key_from_private -p ~/.ssh/id_rsa
  public_key_from_private -p ./azure-key.pem -f pem
  public_key_from_private -p ./prod-key -f ssh --passphrase
EOF
        return 1
    fi

    if [[ ! -f "$private_key_file" ]]; then
        echo "Error: Private key file not found: $private_key_file" >&2
        return 1
    fi

    local passphrase_opt=""
    if [[ "$use_passphrase" = true ]]; then
        passphrase_opt="-P"
    else
        passphrase_opt="-P ''"   # assume no passphrase
    fi

    case "${output_format,,}" in
        pem)
            echo "# Public key in PEM format" >&2
            if ! openssl pkey -in "$private_key_file" -pubout -outform PEM 2>/dev/null; then
                echo "Error: Failed to extract public key in PEM format." >&2
                echo "   → File may not be a valid private key, wrong format, or requires passphrase." >&2
                echo "   → Try again with --passphrase option" >&2
                return 1
            fi
            ;;

        ssh|openssh)
            echo "# Public key in OpenSSH format" >&2
            if ssh-keygen -y $passphrase_opt -f "$private_key_file" 2>/dev/null; then
                : # success
            else
                echo "Warning: ssh-keygen failed (possibly encrypted key?)" >&2
                echo "Trying openssl → OpenSSH conversion fallback..." >&2
                local tmp_pub=$(mktemp)
                if openssl pkey -in "$private_key_file" -pubout 2>/dev/null | \
                   ssh-keygen -f /dev/stdin -e -m RFC4716 > "$tmp_pub" 2>/dev/null; then
                    cat "$tmp_pub"
                    rm -f "$tmp_pub"
                else
                    echo "Error: Could not generate OpenSSH public key." >&2
                    rm -f "$tmp_pub" 2>/dev/null
                    return 1
                fi
            fi
            ;;

        *)
            echo "Error: Unsupported format '$output_format'" >&2
            echo "Supported: ssh (default), pem" >&2
            return 1
            ;;
    esac

    return 0
}

# pfx_extract - Reusable function to extract private key and full certificate chain from a .pfx file
pfx_extract() {
    # Safer bash settings
    set -Euo pipefail

    if [ $# -eq 0 ]; then
        echo "Usage: pfx_extract <path-to-file.pfx>" >&2
        echo "Example: pfx_extract /path/to/mycert.pfx" >&2
        return 1
    fi

    local PFX_FILE="$1"
    local PASSWORD=""

    # Check if file exists
    if [ ! -f "$PFX_FILE" ]; then
        echo "Error: File not found: $PFX_FILE" >&2
        return 1
    fi

    # Ask for password (silently)
    echo "Enter the password for the PFX file (press Enter if no password):" >&2
    read -r -s PASSWORD
    echo >&2

    # Temporary files
    local KEY_TMP
    local CHAIN_TMP
    KEY_TMP=$(mktemp)
    CHAIN_TMP=$(mktemp)

    # Trap to ensure cleanup even if script fails
    trap 'rm -f "$KEY_TMP" "$CHAIN_TMP"' EXIT

    echo "Extracting private key and certificate chain from: $PFX_FILE" >&2

    # Extract unencrypted private key
    if [ -z "$PASSWORD" ]; then
        openssl pkcs12 -in "$PFX_FILE" -nocerts -nodes -out "$KEY_TMP" 2>/dev/null
    else
        openssl pkcs12 -in "$PFX_FILE" -nocerts -nodes -passin "pass:$PASSWORD" -out "$KEY_TMP" 2>/dev/null
    fi

    # Extract full certificate chain (leaf + intermediates + root)
    if [ -z "$PASSWORD" ]; then
        openssl pkcs12 -in "$PFX_FILE" -clcerts -nokeys -nodes -out "$CHAIN_TMP" 2>/dev/null
        openssl pkcs12 -in "$PFX_FILE" -cacerts -nokeys -chain -nodes -out "$CHAIN_TMP" -append 2>/dev/null || true
    else
        openssl pkcs12 -in "$PFX_FILE" -clcerts -nokeys -nodes -passin "pass:$PASSWORD" -out "$CHAIN_TMP" 2>/dev/null
        openssl pkcs12 -in "$PFX_FILE" -cacerts -nokeys -chain -nodes -passin "pass:$PASSWORD" -out "$CHAIN_TMP" -append 2>/dev/null || true
    fi

    # Output results
    echo "=================================================================="
    echo "PRIVATE KEY"
    echo "=================================================================="
    cat "$KEY_TMP"
    echo

    echo "=================================================================="
    echo "FULL CERTIFICATE CHAIN (leaf + intermediates + root)"
    echo "=================================================================="
    cat "$CHAIN_TMP"
    echo

    echo "Extraction completed successfully." >&2
}
