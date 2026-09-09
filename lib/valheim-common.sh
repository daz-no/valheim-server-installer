#!/usr/bin/env bash

VALHEIM_USER="${VALHEIM_USER:-valheim}"
VALHEIM_GROUP="${VALHEIM_GROUP:-valheim}"
VALHEIM_HOME="${VALHEIM_HOME:-/var/lib/valheim}"
VALHEIM_WORLDS_DIR="${VALHEIM_WORLDS_DIR:-$VALHEIM_HOME/worlds_local}"
VALHEIM_CONFIG_DIR="${VALHEIM_CONFIG_DIR:-/etc/valheim}"
VALHEIM_CONFIG="${VALHEIM_CONFIG:-$VALHEIM_CONFIG_DIR/server.conf}"
VALHEIM_BACKUP_DIR="${VALHEIM_BACKUP_DIR:-/var/backups/valheim}"
VALHEIM_ROOT="${VALHEIM_ROOT:-/opt/valheim}"
VALHEIM_STEAMCMD_DIR="${VALHEIM_STEAMCMD_DIR:-$VALHEIM_ROOT/steamcmd}"
VALHEIM_SERVER_DIR="${VALHEIM_SERVER_DIR:-$VALHEIM_ROOT/server}"
VALHEIM_APP_ID="${VALHEIM_APP_ID:-896660}"
VALHEIM_SERVICE="${VALHEIM_SERVICE:-valheim.service}"

log() {
    printf '%s\n' "$*"
}

warn() {
    printf 'WARNING: %s\n' "$*" >&2
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_root() {
    [[ $EUID -eq 0 ]] || die "Run this command with sudo."
}

validate_display_name() {
    local value=$1
    [[ ${#value} -ge 1 && ${#value} -le 64 ]] || return 1
    [[ $value != *$'\n'* && $value != *$'\r'* && $value != */* ]] || return 1
}

validate_world_name() {
    local value=$1
    validate_display_name "$value" || return 1
    [[ $value != "." && $value != ".." ]] || return 1
    [[ $value != *_backup_* && $value != *.old && $value != *_old ]] || return 1
}

validate_password() {
    local value=$1
    [[ ${#value} -ge 5 && ${#value} -le 64 ]] || return 1
    [[ $value != *$'\n'* && $value != *$'\r'* ]] || return 1
}

validate_port() {
    local value=$1
    [[ $value =~ ^[0-9]+$ ]] || return 1
    (( value >= 1024 && value <= 65534 ))
}

validate_backend() {
    [[ $1 == "steam" || $1 == "crossplay" ]]
}

validate_public() {
    [[ $1 == "0" || $1 == "1" ]]
}

encode_value() {
    printf '%s' "$1" | base64 | tr -d '\n'
}

decode_value() {
    local value=$1
    [[ $value =~ ^[A-Za-z0-9+/]*={0,2}$ ]] || return 1
    printf '%s' "$value" | base64 --decode 2>/dev/null
}

render_config() {
    validate_display_name "$SERVER_NAME" || die "Invalid server name."
    validate_world_name "$WORLD_NAME" || die "Invalid world name."
    validate_password "$SERVER_PASSWORD" || die "Password must contain 5 to 64 characters and no newlines."
    validate_port "$SERVER_PORT" || die "Port must be between 1024 and 65534."
    validate_backend "$SERVER_BACKEND" || die "Backend must be steam or crossplay."
    validate_public "$SERVER_PUBLIC" || die "Visibility must be 0 or 1."

    printf 'CONFIG_VERSION=1\n'
    printf 'SERVER_NAME_B64=%s\n' "$(encode_value "$SERVER_NAME")"
    printf 'WORLD_NAME_B64=%s\n' "$(encode_value "$WORLD_NAME")"
    printf 'SERVER_PASSWORD_B64=%s\n' "$(encode_value "$SERVER_PASSWORD")"
    printf 'SERVER_PORT=%s\n' "$SERVER_PORT"
    printf 'SERVER_BACKEND=%s\n' "$SERVER_BACKEND"
    printf 'SERVER_PUBLIC=%s\n' "$SERVER_PUBLIC"
}

load_config() {
    local path=${1:-$VALHEIM_CONFIG}
    local line key value
    local config_version="" server_name_b64="" world_name_b64="" password_b64=""

    [[ -r $path ]] || die "Cannot read configuration: $path"

    while IFS= read -r line || [[ -n $line ]]; do
        key=${line%%=*}
        value=${line#*=}
        [[ -z $key || $key == \#* ]] && continue
        case "$key" in
            CONFIG_VERSION) config_version=$value ;;
            SERVER_NAME_B64) server_name_b64=$value ;;
            WORLD_NAME_B64) world_name_b64=$value ;;
            SERVER_PASSWORD_B64) password_b64=$value ;;
            SERVER_PORT) SERVER_PORT=$value ;;
            SERVER_BACKEND) SERVER_BACKEND=$value ;;
            SERVER_PUBLIC) SERVER_PUBLIC=$value ;;
            *) die "Unknown configuration key: $key" ;;
        esac
    done < "$path"

    [[ $config_version == "1" ]] || die "Unsupported or missing configuration version."
    SERVER_NAME=$(decode_value "$server_name_b64") || die "Invalid encoded server name."
    WORLD_NAME=$(decode_value "$world_name_b64") || die "Invalid encoded world name."
    SERVER_PASSWORD=$(decode_value "$password_b64") || die "Invalid encoded password."

    validate_display_name "$SERVER_NAME" || die "Invalid server name in configuration."
    validate_world_name "$WORLD_NAME" || die "Invalid world name in configuration."
    validate_password "$SERVER_PASSWORD" || die "Invalid password in configuration."
    validate_port "$SERVER_PORT" || die "Invalid port in configuration."
    validate_backend "$SERVER_BACKEND" || die "Invalid backend in configuration."
    validate_public "$SERVER_PUBLIC" || die "Invalid visibility in configuration."
}

save_config() {
    require_root
    local temp
    temp=$(mktemp)
    render_config > "$temp"
    install -d -o root -g "$VALHEIM_GROUP" -m 0750 "$VALHEIM_CONFIG_DIR"
    install -o root -g "$VALHEIM_GROUP" -m 0640 "$temp" "$VALHEIM_CONFIG"
    rm -f -- "$temp"
}

service_was_active() {
    systemctl is-active --quiet "$VALHEIM_SERVICE"
}

restart_if_active() {
    local was_active=$1
    if [[ $was_active == "1" ]]; then
        systemctl restart "$VALHEIM_SERVICE"
    fi
}

list_world_pairs() {
    local directory=$1 file base
    [[ -d $directory ]] || return 0
    while IFS= read -r -d '' file; do
        base=${file%.db}
        [[ -f "$base.fwl" ]] || continue
        validate_world_name "${base##*/}" || continue
        printf '%s\0' "$base"
    done < <(find "$directory" -maxdepth 1 -type f -name '*.db' -print0 | sort -z)
}

write_managed_file() {
    local owner=$1 group=$2 mode=$3 destination=$4
    local temp
    temp=$(mktemp)
    cat > "$temp"
    install -o "$owner" -g "$group" -m "$mode" "$temp" "$destination"
    rm -f -- "$temp"
}
