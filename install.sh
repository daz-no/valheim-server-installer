#!/usr/bin/env bash

echo "================================"
echo " Valheim Installer"
echo "================================"
echo ""

detect_operating_system() {
    printf '%s\n' "${VALHEIM_TEST_UNAME_S:-$(uname -s)}"
}

detect_architecture() {
    printf '%s\n' "${VALHEIM_TEST_UNAME_M:-$(uname -m)}"
}

detect_distribution() {
    local os_release=${VALHEIM_TEST_OS_RELEASE:-/etc/os-release}
    [[ -r "$os_release" ]] || {
        echo "ERROR: Cannot detect the Linux distribution: $os_release is missing or unreadable." >&2
        return 1
    }
    # shellcheck source=/etc/os-release disable=SC1091
    source "$os_release"
    printf '%s\n' "${ID:-unknown}:${VERSION_ID:-unknown}:${PRETTY_NAME:-unknown}"
}

validate_platform() {
    local os=$1 arch=$2 distribution=$3
    local distribution_id=${distribution%%:*}
    local version=${distribution#*:}
    version=${version%%:*}
    local name=${distribution##*:}

    [[ "$os" == Linux ]] || {
        echo "ERROR: Unsupported operating system '$os'; this installer only supports Linux." >&2
        return 1
    }
    [[ "$arch" == x86_64 ]] || {
        echo "ERROR: Unsupported architecture '$arch'; this installer only supports x86_64 (amd64)." >&2
        return 1
    }
    [[ "$distribution_id" == ubuntu ]] || {
        echo "ERROR: Unsupported Linux distribution '$name'; this installer only supports Ubuntu Server." >&2
        return 1
    }
    case "$version" in
        22.04|24.04|26.04) return 0 ;;
        *)
            echo "ERROR: Unsupported Ubuntu version '$version'; supported LTS releases are 22.04, 24.04, and 26.04." >&2
            return 1
            ;;
    esac
}

check_platform() {
    local os arch distribution
    os=$(detect_operating_system)
    arch=$(detect_architecture)
    distribution=$(detect_distribution) || return 1
    validate_platform "$os" "$arch" "$distribution" || return 1
    printf 'Detected platform: %s / %s\n' "${distribution##*:}" "$arch"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
OS=$(detect_operating_system)
ARCH=$(detect_architecture)

echo "Operating system: $OS"
echo "CPU architecture: $ARCH"
echo "Current user: $(whoami)"
echo ""

check_platform || exit 1

# Check if sudo is installed
if ! command -v sudo > /dev/null 2>&1; then
    echo "ERROR: sudo is not installed."
    exit 1
fi

# Check if the current user has sudo permission
if ! sudo -v; then
    echo "ERROR: The current user does not have sudo permission."
    exit 1
fi

echo ""
echo "Updating package list..."
sudo apt update

echo ""
echo "Installing required packages..."
sudo apt install -y curl tar lib32gcc-s1 lib32stdc++6 libatomic1 libpulse-mainloop-glib0

echo ""
echo "System check passed!"
echo "This server is compatible with the installer."
fi
