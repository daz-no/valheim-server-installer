#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/install.sh" >/dev/null

temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT

make_release() {
    printf 'ID=%s\nVERSION_ID="%s"\nPRETTY_NAME="Test Linux %s"\n' "$1" "$2" "$2" > "$temp/os-release"
}

for version in 22.04 24.04 26.04; do
    make_release ubuntu "$version"
    VALHEIM_TEST_UNAME_S=Linux VALHEIM_TEST_UNAME_M=x86_64 VALHEIM_TEST_OS_RELEASE="$temp/os-release" check_platform >/dev/null
done

make_release ubuntu 24.04
if VALHEIM_TEST_UNAME_S=Darwin VALHEIM_TEST_UNAME_M=x86_64 VALHEIM_TEST_OS_RELEASE="$temp/os-release" check_platform >/dev/null 2>&1; then exit 1; fi
if VALHEIM_TEST_UNAME_S=Linux VALHEIM_TEST_UNAME_M=aarch64 VALHEIM_TEST_OS_RELEASE="$temp/os-release" check_platform >/dev/null 2>&1; then exit 1; fi

make_release debian 13
if VALHEIM_TEST_UNAME_S=Linux VALHEIM_TEST_UNAME_M=x86_64 VALHEIM_TEST_OS_RELEASE="$temp/os-release" check_platform >/dev/null 2>&1; then exit 1; fi

echo 'platform validation tests passed'
