#!/usr/bin/env bash
set -Eeuo pipefail

STEAMCMD_URL="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
RESTART_ON_EXIT=0
LOCK_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/valheim-installer.lock"
MIN_FREE_KB=10485760
TEMP_FILES=()

track_temp_file() {
    TEMP_FILES+=("$1")
    printf '%s' "$1"
}

make_temp_file() {
    local file
    file=$(mktemp)
    track_temp_file "$file" >/dev/null
    printf '%s' "$file"
}

cleanup() {
    local exit_code=$?
    if [[ $RESTART_ON_EXIT == 1 ]]; then
        sudo systemctl start valheim.service >/dev/null 2>&1 || true
    fi
    if (( ${#TEMP_FILES[@]} > 0 )); then
        rm -f -- "${TEMP_FILES[@]}"
    fi
    if (( exit_code != 0 )); then
        printf 'ERROR: Installation stopped. Fix the reported problem and run the installer again.\n' >&2
    fi
}
trap cleanup EXIT

log() { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

prompt_yes_no() {
    local prompt=$1 default=${2:-n} answer suffix
    if [[ $default == y ]]; then suffix="[Y/n]"; else suffix="[y/N]"; fi
    read -r -p "$prompt $suffix: " answer
    answer=${answer:-$default}
    [[ $answer == [Yy] || $answer == [Yy][Ee][Ss] ]]
}

prompt_default() {
    local prompt=$1 default=$2 answer
    read -r -p "$prompt [$default]: " answer
    printf '%s' "${answer:-$default}"
}

banner() {
    cat <<'EOF'
================================
 Valheim Server Installer
================================
EOF
}

detect_operating_system() {
    printf '%s\n' "${VALHEIM_TEST_UNAME_S:-$(uname -s)}"
}

detect_architecture() {
    printf '%s\n' "${VALHEIM_TEST_UNAME_M:-$(uname -m)}"
}

detect_distribution() {
    local os_release=${VALHEIM_TEST_OS_RELEASE:-/etc/os-release}
    [[ -r $os_release ]] || die "Cannot detect the Linux distribution: $os_release is missing or unreadable."
    # shellcheck source=/etc/os-release disable=SC1091
    source "$os_release"
    printf '%s\n' "${ID:-unknown}:${VERSION_ID:-unknown}:${PRETTY_NAME:-unknown}"
}

validate_platform() {
    local operating_system=$1 architecture=$2 distribution=$3
    local distribution_id=${distribution%%:*}
    local distribution_version=${distribution#*:}
    distribution_version=${distribution_version%%:*}
    local distribution_name=${distribution##*:}

    [[ $operating_system == Linux ]] || die "Unsupported operating system '$operating_system'; this installer only supports Linux."
    [[ $architecture == x86_64 ]] || die "Unsupported architecture '$architecture'; this installer only supports x86_64 (amd64)."
    [[ $distribution_id == ubuntu ]] || die "Unsupported Linux distribution '$distribution_name'; this installer only supports Ubuntu Server."
    case "$distribution_version" in
        22.04|24.04|26.04) ;;
        *) die "Unsupported Ubuntu version '$distribution_version'; supported LTS releases are 22.04, 24.04, and 26.04." ;;
    esac
}

check_platform() {
    local operating_system architecture distribution
    operating_system=$(detect_operating_system)
    [[ $operating_system == Linux ]] || die "Unsupported operating system '$operating_system'; this installer only supports Linux."
    architecture=$(detect_architecture)
    [[ $architecture == x86_64 ]] || die "Unsupported architecture '$architecture'; this installer only supports x86_64 (amd64)."
    distribution=$(detect_distribution)
    validate_platform "$operating_system" "$architecture" "$distribution"
    log "Detected platform: ${distribution##*:} / $architecture"
}

check_host() {
    local free_kb
    command -v sudo >/dev/null 2>&1 || die "sudo is required."
    command -v apt-get >/dev/null 2>&1 || die "apt-get is required."
    command -v systemctl >/dev/null 2>&1 || die "systemd/systemctl is required."
    command -v flock >/dev/null 2>&1 || die "flock is required; install util-linux first."
    sudo -v || die "The current account does not have sudo permission."

    free_kb=$(df -Pk /opt | awk 'NR == 2 {print $4}')
    [[ $free_kb =~ ^[0-9]+$ ]] || die "Cannot determine free disk space on /opt."
    (( free_kb >= MIN_FREE_KB )) || die "At least 10 GiB of free space is required on /opt."
}

acquire_installer_lock() {
    install -d -m 0700 "$(dirname -- "$LOCK_FILE")"
    exec 9>"$LOCK_FILE"
    flock -n 9 || die "Another Valheim installer is already running."
}

check_runtime_tools() {
    local tool
    for tool in curl tar gzip runuser base64 sha256sum realpath journalctl ss; do
        command -v "$tool" >/dev/null 2>&1 || die "Required command is missing: $tool"
    done
}

check_network() {
    log "Checking access to SteamCMD"
    curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --range 0-0 \
        -o /dev/null "$STEAMCMD_URL" || die "Cannot reach the SteamCMD download URL."
}

install_dependencies() {
    command -v sudo >/dev/null 2>&1 || die "sudo is required."
    sudo -v || die "The current account does not have sudo permission."
    log "Updating Ubuntu package metadata..."
    sudo apt-get update
    log "Installing required packages..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ca-certificates curl tar gzip coreutils findutils \
        util-linux \
        iproute2 \
        lib32gcc-s1 lib32stdc++6 libatomic1 libpulse0 libpulse-dev
}

check_port_available() {
    local local_port
    local_port=":$SERVER_PORT"
    if ss -H -lun | awk -v port="$local_port" '$5 ~ (port "$") {found=1} END {exit found ? 0 : 1}'; then
        die "UDP port $SERVER_PORT is already in use. Choose another port."
    fi
    if ss -H -lun | awk -v port=":$((SERVER_PORT + 1))" '$5 ~ (port "$") {found=1} END {exit found ? 0 : 1}'; then
        die "UDP port $((SERVER_PORT + 1)) is already in use. Choose another port."
    fi
}

install_runtime_assets() {
    [[ -f "$SCRIPT_DIR/lib/valheim-common.sh" && -f "$SCRIPT_DIR/bin/valheimctl" ]] \
        || die "Installer assets are missing from $SCRIPT_DIR; re-clone the repository."
    sudo install -d -o root -g root -m 0755 /usr/local/lib/valheim /usr/local/libexec/valheim
    sudo install -o root -g root -m 0644 "$SCRIPT_DIR/lib/valheim-common.sh" /usr/local/lib/valheim/common.sh
    sudo install -o root -g root -m 0755 "$SCRIPT_DIR/bin/valheimctl" /usr/local/sbin/valheimctl
    sudo install -o root -g root -m 0755 "$SCRIPT_DIR/libexec/start-server.sh" /usr/local/libexec/valheim/start-server
    sudo install -o root -g root -m 0755 "$SCRIPT_DIR/libexec/maintenance.sh" /usr/local/libexec/valheim/maintenance
    sudo install -o root -g root -m 0644 "$SCRIPT_DIR/systemd/valheim.service" /etc/systemd/system/valheim.service
    sudo install -o root -g root -m 0644 "$SCRIPT_DIR/systemd/valheim-maintenance.service" /etc/systemd/system/valheim-maintenance.service
    sudo install -o root -g root -m 0644 "$SCRIPT_DIR/systemd/valheim-maintenance.timer" /etc/systemd/system/valheim-maintenance.timer
    # shellcheck source=lib/valheim-common.sh
    source "$SCRIPT_DIR/lib/valheim-common.sh"
}

create_service_account() {
    local account existing_home existing_shell existing_group
    if account=$(getent passwd "$VALHEIM_USER"); then
        existing_home=$(cut -d: -f6 <<< "$account")
        existing_shell=$(cut -d: -f7 <<< "$account")
        existing_group=$(getent group "$(cut -d: -f4 <<< "$account")" | cut -d: -f1)
        [[ $existing_home == "$VALHEIM_HOME" && $existing_shell == /usr/sbin/nologin && $existing_group == "$VALHEIM_GROUP" ]] \
            || die "Existing '$VALHEIM_USER' account is incompatible; expected group valheim, home $VALHEIM_HOME, and shell /usr/sbin/nologin."
        log "Service account '$VALHEIM_USER' already has the expected settings."
    else
        sudo useradd --system --user-group --home-dir "$VALHEIM_HOME" --no-create-home \
            --shell /usr/sbin/nologin "$VALHEIM_USER"
        log "Created restricted service account '$VALHEIM_USER'."
    fi
}

create_directories() {
    sudo install -d -o root -g "$VALHEIM_GROUP" -m 0750 "$VALHEIM_ROOT"
    sudo install -d -o "$VALHEIM_USER" -g "$VALHEIM_GROUP" -m 0750 \
        "$VALHEIM_HOME" "$VALHEIM_WORLDS_DIR" "$VALHEIM_STEAMCMD_DIR" "$VALHEIM_SERVER_DIR"
    sudo install -d -o root -g "$VALHEIM_GROUP" -m 0750 "$VALHEIM_CONFIG_DIR"
    sudo install -d -o root -g root -m 0700 "$VALHEIM_BACKUP_DIR"
    for permission_file in adminlist.txt bannedlist.txt permittedlist.txt; do
        sudo touch "$VALHEIM_HOME/$permission_file"
        sudo chown "$VALHEIM_USER:$VALHEIM_GROUP" "$VALHEIM_HOME/$permission_file"
        sudo chmod 0640 "$VALHEIM_HOME/$permission_file"
    done
}

install_steamcmd() {
    local archive
    if [[ ! -x "$VALHEIM_STEAMCMD_DIR/steamcmd.sh" ]]; then
        archive=$(make_temp_file)
        log "Downloading SteamCMD..."
        curl --proto '=https' --tlsv1.2 -fsSL --retry 3 "$STEAMCMD_URL" -o "$archive"
        sudo tar -xzf "$archive" -C "$VALHEIM_STEAMCMD_DIR"
        rm -f -- "$archive"
        sudo chown -R "$VALHEIM_USER:$VALHEIM_GROUP" "$VALHEIM_STEAMCMD_DIR"
    fi

    if sudo systemctl is-active --quiet valheim.service 2>/dev/null; then
        sudo systemctl stop valheim.service
        RESTART_ON_EXIT=1
    fi
    log "Installing or updating Valheim Dedicated Server..."
    sudo -u "$VALHEIM_USER" env HOME="$VALHEIM_HOME" \
        "$VALHEIM_STEAMCMD_DIR/steamcmd.sh" \
        +force_install_dir "$VALHEIM_SERVER_DIR" \
        +login anonymous \
        +app_update "$VALHEIM_APP_ID" validate \
        +quit
}

prompt_password() {
    local first second
    while true; do
        read -r -s -p "Server password (5-64 characters): " first
        printf '\n'
        validate_password "$first" || { warn "Password must contain 5 to 64 characters and no newlines."; continue; }
        read -r -s -p "Confirm password: " second
        printf '\n'
        [[ $first == "$second" ]] || { warn "Passwords do not match."; continue; }
        SERVER_PASSWORD=$first
        return
    done
}

choose_uploaded_world() {
    local upload_dir=$1 base choice index
    local -a pairs
    while true; do
        pairs=()
        while IFS= read -r -d '' base; do pairs+=("$base"); done < <(list_world_pairs "$upload_dir")
        if ((${#pairs[@]} == 0)); then
            warn "No complete, valid .db/.fwl pair was found in $upload_dir"
            find "$upload_dir" -maxdepth 1 -type f \( -name '*.db' -o -name '*.fwl' \) -printf '  %f\n' || true
            prompt_yes_no "Retry after uploading both matching files?" y || die "World import cancelled."
            read -r -p "Press Enter after the upload is complete..." _
            continue
        fi
        if ((${#pairs[@]} == 1)); then
            printf '%s' "${pairs[0]}"
            return
        fi
        log "Complete uploaded worlds:" >&2
        for index in "${!pairs[@]}"; do printf '  %d) %s\n' "$((index + 1))" "${pairs[$index]##*/}" >&2; done
        read -r -p "Selection: " choice
        if [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#pairs[@]} )); then
            printf '%s' "${pairs[$((choice - 1))]}"
            return
        fi
        warn "Invalid selection."
    done
}

configure_world() {
    local mode upload selected admin_group
    log "World setup:"
    log "  1) Start a new randomly generated world"
    log "  2) Import an existing local world through WinSCP"
    read -r -p "Selection [1]: " mode
    mode=${mode:-1}
    case "$mode" in
        1)
            while true; do
                WORLD_NAME=$(prompt_default "World name" "$WORLD_NAME")
                validate_world_name "$WORLD_NAME" && break
                warn "Use 1-64 characters without slashes or newlines."
            done
            log "Valheim will generate '$WORLD_NAME' with a random seed on first start."
            ;;
        2)
            upload="$HOME/valheim-world-upload"
            admin_group=$(id -gn)
            sudo install -d -o "$USER" -g "$admin_group" -m 0700 "$upload"
            cat <<EOF

Existing-world upload
1. In Valheim on Windows, use Manage Saves -> Move to Local for the world.
2. Close Valheim, then open:
   %USERPROFILE%\\AppData\\LocalLow\\IronGate\\Valheim\\worlds_local
3. In WinSCP, connect with this Ubuntu account and upload both matching files:
   WORLD.db and WORLD.fwl
4. Upload them to: $upload
EOF
            read -r -p "Press Enter after the upload is complete..." _
            selected=$(choose_uploaded_world "$upload")
            WORLD_NAME=${selected##*/}
            if sudo test -e "$VALHEIM_WORLDS_DIR/$WORLD_NAME.db" || sudo test -e "$VALHEIM_WORLDS_DIR/$WORLD_NAME.fwl"; then
                prompt_yes_no "Installed files for '$WORLD_NAME' exist. Back them up and replace them?" n \
                    || die "World import cancelled."
                if sudo test -f "$VALHEIM_CONFIG"; then
                    sudo /usr/local/libexec/valheim/maintenance backup-stopped
                else
                    die "Unmanaged files already use this world name. Move them aside or choose another world name."
                fi
            fi
            sudo install -o "$VALHEIM_USER" -g "$VALHEIM_GROUP" -m 0600 "$selected.db" "$VALHEIM_WORLDS_DIR/$WORLD_NAME.db"
            sudo install -o "$VALHEIM_USER" -g "$VALHEIM_GROUP" -m 0600 "$selected.fwl" "$VALHEIM_WORLDS_DIR/$WORLD_NAME.fwl"
            log "Imported '$WORLD_NAME'. Upload originals were preserved in $upload"
            ;;
        *) die "World selection must be 1 or 2." ;;
    esac
}

write_configuration() {
    local temp
    temp=$(make_temp_file)
    render_config > "$temp"
    sudo install -o root -g "$VALHEIM_GROUP" -m 0640 "$temp" "$VALHEIM_CONFIG"
    rm -f -- "$temp"
}

load_existing_configuration() {
    local temp
    temp=$(make_temp_file)
    chmod 0600 "$temp"
    # The redirect intentionally belongs to the unprivileged installer process.
    # shellcheck disable=SC2024
    sudo cat "$VALHEIM_CONFIG" > "$temp"
    load_config "$temp"
    rm -f -- "$temp"
}

guided_configuration() {
    local backend_choice port_value
    if sudo test -f "$VALHEIM_CONFIG"; then
        load_existing_configuration
        if ! prompt_yes_no "A managed configuration exists. Change it?" n; then
            log "Keeping the existing server configuration and active world."
            return
        fi
    else
        SERVER_NAME="Valheim Server"
        WORLD_NAME="Dedicated"
        SERVER_PASSWORD=""
        SERVER_PORT="2456"
        SERVER_BACKEND="crossplay"
        SERVER_PUBLIC="0"
    fi

    while true; do
        SERVER_NAME=$(prompt_default "Server display name" "$SERVER_NAME")
        validate_display_name "$SERVER_NAME" && break
        warn "Use 1-64 characters without slashes or newlines."
    done
    prompt_password
    while true; do
        port_value=$(prompt_default "UDP base port" "$SERVER_PORT")
        validate_port "$port_value" && { SERVER_PORT=$port_value; break; }
        warn "Use a port from 1024 through 65534."
    done
    log "Connection backend: 1) Steam only  2) Crossplay"
    read -r -p "Selection [2]: " backend_choice
    case "${backend_choice:-2}" in
        1) SERVER_BACKEND=steam ;;
        2) SERVER_BACKEND=crossplay ;;
        *) die "Backend selection must be 1 or 2." ;;
    esac
    if prompt_yes_no "List the server in the public browser?" n; then SERVER_PUBLIC=1; else SERVER_PUBLIC=0; fi
    configure_world
    write_configuration
}

configure_firewall() {
    if [[ $SERVER_BACKEND == steam ]]; then
        log "Steam mode requires inbound UDP $SERVER_PORT-$((SERVER_PORT + 1)) in your VPS security group."
        if command -v ufw >/dev/null 2>&1 && sudo ufw status | head -n1 | grep -q 'Status: active'; then
            if prompt_yes_no "Allow UDP $SERVER_PORT-$((SERVER_PORT + 1)) through active UFW?" y; then
                sudo ufw allow "$SERVER_PORT:$((SERVER_PORT + 1))/udp"
            fi
        fi
    else
        log "Crossplay uses PlayFab relay and normally needs no inbound VPS port rule."
    fi
}

finish_installation() {
    local start_epoch deadline
    sudo systemctl daemon-reload
    sudo systemctl enable --now valheim-maintenance.timer
    sudo systemctl enable valheim.service
    start_epoch=$(date +%s)
    sudo systemctl restart valheim.service
    deadline=$((SECONDS + 120))
    while (( SECONDS < deadline )); do
        if ! sudo systemctl is-active --quiet valheim.service; then
            sudo journalctl -u valheim.service -n 100 --no-pager >&2 || true
            die "Valheim service exited during startup."
        fi
        if sudo journalctl -u valheim.service --since "@$start_epoch" --no-pager 2>/dev/null \
            | grep -Fq "Game server connected"; then
            break
        fi
        sleep 2
    done
    (( SECONDS < deadline )) || {
        sudo journalctl -u valheim.service -n 100 --no-pager >&2 || true
        die "Valheim service did not become ready within 120 seconds."
    }
    RESTART_ON_EXIT=0
    log ""
    log "Installation complete."
    log "Server: $SERVER_NAME"
    log "World:  $WORLD_NAME"
    log "Manage: sudo valheimctl help"
    log "Status: sudo valheimctl status"
    log "Logs:   sudo valheimctl logs --follow"
    log "Valheim is ready when the log contains: Game server connected"
}

main() {
    banner
    # The installed common library later replaces this bootstrap error helper.
    # shellcheck disable=SC2218
    [[ $EUID -ne 0 ]] || die "Run this installer as your normal sudo-capable SSH account, not as root."
    check_platform
    check_host
    acquire_installer_lock
    install_dependencies
    check_runtime_tools
    check_network
    install_runtime_assets
    create_service_account
    create_directories
    install_steamcmd
    guided_configuration
    load_existing_configuration
    check_port_available
    configure_firewall
    finish_installation
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
