#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=/usr/local/lib/valheim/common.sh
# shellcheck disable=SC1090,SC1091
source "${VALHEIM_COMMON_PATH:-/usr/local/lib/valheim/common.sh}"

require_root

action=${1:-daily}
case "$action" in
    daily|backup|update|backup-stopped) ;;
    *) die "Usage: maintenance.sh {daily|backup|update|backup-stopped}" ;;
esac

server_was_active=0
service_stopped=0

restart_server() {
    if [[ $server_was_active == "1" && $service_stopped == "1" ]]; then
        service_stopped=0
        if ! systemctl start "$VALHEIM_SERVICE"; then
            warn "The server could not be restarted. Check: sudo valheimctl logs"
            return 1
        fi
    fi
}

trap restart_server EXIT

stop_server_if_needed() {
    if service_was_active; then
        server_was_active=1
        systemctl stop "$VALHEIM_SERVICE"
        service_stopped=1
    fi
}

prune_backups() {
    local archive count=0
    while IFS= read -r archive; do
        count=$((count + 1))
        if (( count > 14 )); then
            rm -f -- "$archive" "$archive.sha256"
        fi
    done < <(find "$VALHEIM_BACKUP_DIR" -maxdepth 1 -type f -name 'valheim-*.tar.gz' -printf '%T@ %p\n' \
        | sort -rn | cut -d' ' -f2-)
}

create_backup() {
    local label=${1:-manual} timestamp archive temporary
    local -a paths
    timestamp=$(date '+%Y%m%d-%H%M%S')
    archive="$VALHEIM_BACKUP_DIR/valheim-$timestamp-$label.tar.gz"
    temporary="$archive.partial"

    install -d -o root -g root -m 0700 "$VALHEIM_BACKUP_DIR"
    paths=(etc/valheim/server.conf var/lib/valheim/worlds_local)
    for permission_file in adminlist.txt bannedlist.txt permittedlist.txt; do
        if [[ -f "$VALHEIM_HOME/$permission_file" ]]; then
            paths+=("var/lib/valheim/$permission_file")
        fi
    done

    if ! tar -C / -czf "$temporary" "${paths[@]}"; then
        rm -f -- "$temporary"
        die "Could not create the backup archive."
    fi
    chmod 0600 "$temporary"
    mv -- "$temporary" "$archive"
    sha256sum "$archive" > "$archive.sha256"
    chmod 0600 "$archive.sha256"
    prune_backups
    log "Backup created: $archive"
}

update_server() {
    [[ -x "$VALHEIM_STEAMCMD_DIR/steamcmd.sh" ]] || die "SteamCMD is not installed."
    install -d -o "$VALHEIM_USER" -g "$VALHEIM_GROUP" -m 0750 "$VALHEIM_SERVER_DIR"
    runuser -u "$VALHEIM_USER" -- env HOME="$VALHEIM_HOME" \
        "$VALHEIM_STEAMCMD_DIR/steamcmd.sh" \
        +force_install_dir "$VALHEIM_SERVER_DIR" \
        +login anonymous \
        +app_update "$VALHEIM_APP_ID" validate \
        +quit
}

if [[ $action != "backup-stopped" ]]; then
    stop_server_if_needed
fi

case "$action" in
    daily)
        create_backup daily
        update_server
        ;;
    backup|backup-stopped)
        create_backup manual
        ;;
    update)
        create_backup pre-update
        update_server
        ;;
esac

restart_server
trap - EXIT
