#!/usr/bin/env bash
# Configuration variables are consumed indirectly by render_config.
# shellcheck disable=SC2034
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
mkdir -p "$temp/server" "$temp/home"

cat > "$temp/server/valheim_server.x86_64" <<'EOF'
#!/usr/bin/env bash
printf '%s\0' "$@" > "$CAPTURE_ARGS"
printf '%s\n' "$HOME" "$SteamAppId" "$LD_LIBRARY_PATH" > "$CAPTURE_ENV"
EOF
chmod +x "$temp/server/valheim_server.x86_64"

export VALHEIM_HOME="$temp/home"
export VALHEIM_SERVER_DIR="$temp/server"
export VALHEIM_CONFIG_DIR="$temp/config"
export VALHEIM_CONFIG="$temp/config/server.conf"
export VALHEIM_COMMON_PATH="$ROOT/lib/valheim-common.sh"
export CAPTURE_ARGS="$temp/args"
export CAPTURE_ENV="$temp/environment"
mkdir -p "$VALHEIM_CONFIG_DIR"

# shellcheck source=../lib/valheim-common.sh
# shellcheck disable=SC1091
source "$ROOT/lib/valheim-common.sh"
SERVER_NAME='Server With Spaces'
WORLD_NAME='World With Spaces'
SERVER_PASSWORD='safe $ password'
SERVER_PORT=2456
SERVER_BACKEND=crossplay
SERVER_PUBLIC=0
render_config > "$VALHEIM_CONFIG"

bash "$ROOT/libexec/start-server.sh"
mapfile -d '' arguments < "$CAPTURE_ARGS"

contains_argument() {
    local expected=$1 value
    for value in "${arguments[@]}"; do [[ $value == "$expected" ]] && return 0; done
    return 1
}

contains_sequence() {
    local first=$1 second=$2 index
    for index in "${!arguments[@]}"; do
        if [[ ${arguments[$index]} == "$first" && ${arguments[$((index + 1))]:-} == "$second" ]]; then return 0; fi
    done
    return 1
}

contains_sequence -name 'Server With Spaces'
contains_sequence -world 'World With Spaces'
contains_sequence -password 'safe $ password'
contains_sequence -savedir "$temp/home"
contains_sequence -port 2456
contains_sequence -public 0
contains_argument -crossplay
grep -Fxq "$temp/home" "$CAPTURE_ENV"
grep -Fxq '892970' "$CAPTURE_ENV"

SERVER_BACKEND=steam
render_config > "$VALHEIM_CONFIG"
bash "$ROOT/libexec/start-server.sh"
mapfile -d '' arguments < "$CAPTURE_ARGS"
if contains_argument -crossplay; then
    echo "Steam mode unexpectedly included -crossplay" >&2
    exit 1
fi

echo "launcher arguments: passed"
