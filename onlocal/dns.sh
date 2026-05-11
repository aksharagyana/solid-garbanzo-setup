dnsmasq_setup() {
    local CONFIG_FILE="$1"
    local DNSMASQ_CONF="/opt/homebrew/etc/dnsmasq.conf"
    local DNS_SERVICE="Wi-Fi"

    if [[ -z "$CONFIG_FILE" ]]; then
        echo "Usage: setup_dnsmasq <path-to-dnsmasq.conf>"
        return 1
    fi

    # Expand ~
    CONFIG_FILE="${CONFIG_FILE/#\~/$HOME}"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "ERROR: Config file not found: $CONFIG_FILE"
        return 1
    fi

    echo "=== dnsmasq setup started ==="

    # Ensure dnsmasq installed
    if ! command -v dnsmasq >/dev/null 2>&1; then
        echo "Installing dnsmasq..."
        brew install dnsmasq || return 1
    fi

    # Ensure destination directory exists
    sudo mkdir -p "$(dirname "$DNSMASQ_CONF")"

    echo "=== Copying config ==="
    sudo cp "$CONFIG_FILE" "$DNSMASQ_CONF"

    echo "=== Testing config ==="
    if ! dnsmasq --test --conf-file="$DNSMASQ_CONF"; then
        echo "ERROR: dnsmasq config validation failed"
        return 1
    fi

    echo "=== Restarting dnsmasq ==="

    # Stop existing processes if any
    sudo pkill dnsmasq 2>/dev/null || true

    brew services restart dnsmasq

    sleep 2

    echo "=== Configuring macOS DNS ==="

    # Set localhost DNS
    networksetup -setdnsservers "$DNS_SERVICE" 127.0.0.1

    echo "=== Flushing macOS DNS cache ==="

    sudo dscacheutil -flushcache
    sudo killall -HUP mDNSResponder 2>/dev/null || true

    echo "=== Verifying dnsmasq ==="

    if ! pgrep dnsmasq >/dev/null; then
        echo "ERROR: dnsmasq is not running"
        return 1
    fi

    echo "=== Port 53 status ==="
    sudo lsof -i :53

    echo "=== Test DNS query ==="
    dig google.com @127.0.0.1 +short

    echo
    echo "=== SUCCESS ==="
    echo "dnsmasq is configured and running"
    echo "Using config: $DNSMASQ_CONF"
}