#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=/usr/local/lib/valheim/common.sh
# shellcheck disable=SC1090,SC1091
source "${VALHEIM_COMMON_PATH:-/usr/local/lib/valheim/common.sh}"
load_config

[[ -x "$VALHEIM_SERVER_DIR/valheim_server.x86_64" ]] || die "Valheim server binary is missing. Run: sudo valheimctl update"

export HOME="$VALHEIM_HOME"
export SteamAppId="892970"
export LD_LIBRARY_PATH="$VALHEIM_SERVER_DIR/linux64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

arguments=(
    -nographics
    -batchmode
    -name "$SERVER_NAME"
    -port "$SERVER_PORT"
    -world "$WORLD_NAME"
    -password "$SERVER_PASSWORD"
    -savedir "$VALHEIM_HOME"
    -public "$SERVER_PUBLIC"
    -saveinterval 1800
    -backups 4
    -backupshort 7200
    -backuplong 43200
)

if [[ $SERVER_BACKEND == "crossplay" ]]; then
    arguments+=(-crossplay)
fi

cd "$VALHEIM_SERVER_DIR"
exec "$VALHEIM_SERVER_DIR/valheim_server.x86_64" "${arguments[@]}"
