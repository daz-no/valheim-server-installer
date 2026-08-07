#!/usr/bin/env bash

echo "================================"
echo " Valheim Installer"
echo "================================"
echo ""

# Get basic system information
OS=$(uname -s)
ARCH=$(uname -m)

echo "Operating system: $OS"
echo "CPU architecture: $ARCH"
echo "Current user: $(whoami)"
echo ""

# Check if the system is Linux
if [[ "$OS" != "Linux" ]]; then
    echo "ERROR: This installer only supports Linux."
    exit 1
fi

# Check if /etc/os-release exists
if [[ ! -f /etc/os-release ]]; then
    echo "ERROR: Cannot detect the Linux distribution."
    exit 1
fi

# Read Linux distribution information
source /etc/os-release

echo "Linux distribution: $PRETTY_NAME"

# Check if the distribution is Ubuntu
if [[ "$ID" != "ubuntu" ]]; then
    echo "ERROR: This installer currently supports Ubuntu only."
    exit 1
fi

# Check CPU architecture
if [[ "$ARCH" != "x86_64" ]]; then
    echo "ERROR: This installer currently supports x86_64 only."
    exit 1
fi

echo ""
echo "System check passed!"
echo "This server is compatible with the installer."
