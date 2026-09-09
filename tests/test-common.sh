#!/usr/bin/env bash
# shellcheck disable=SC2016
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../lib/valheim-common.sh
# shellcheck disable=SC1091
source "$ROOT/lib/valheim-common.sh"

failures=0
tests=0

check() {
    local description=$1
    shift
    tests=$((tests + 1))
    if "$@"; then
        printf 'ok %d - %s\n' "$tests" "$description"
    else
        printf 'not ok %d - %s\n' "$tests" "$description"
        failures=$((failures + 1))
    fi
}

reject_display_slash() { ! validate_display_name "bad/name"; }
reject_display_newline() { ! validate_display_name $'bad\nname'; }
reject_backup_world() { ! validate_world_name "World_backup_1"; }
reject_world_parent() { ! validate_world_name ".."; }
reject_port_overflow() { ! validate_port 65535; }
reject_short_password() { ! validate_password "abcd"; }
reject_password_newline() { ! validate_password $'safe\npass'; }

check "valid display name" validate_display_name "My Server"
check "display name rejects slash" reject_display_slash
check "display name rejects newline" reject_display_newline
check "valid world with spaces" validate_world_name "My Old World"
check "world rejects backup filename" reject_backup_world
check "world rejects parent path" reject_world_parent
check "valid minimum port" validate_port 1024
check "valid maximum base port" validate_port 65534
check "port rejects next-port overflow" reject_port_overflow
check "password minimum length" validate_password "abcde"
check "password rejects four characters" reject_short_password
check "password rejects newline" reject_password_newline

SERVER_NAME='Viking $Server "One"'
WORLD_NAME='Old World'
SERVER_PASSWORD='p@$$ word!'
SERVER_PORT=2456
SERVER_BACKEND=crossplay
SERVER_PUBLIC=0
config=$(mktemp)
render_config > "$config"
SERVER_NAME='' WORLD_NAME='' SERVER_PASSWORD='' SERVER_PORT='' SERVER_BACKEND='' SERVER_PUBLIC=''
load_config "$config"
check "config round-trips server name" test "$SERVER_NAME" = 'Viking $Server "One"'
check "config round-trips world name" test "$WORLD_NAME" = 'Old World'
check "config round-trips password" test "$SERVER_PASSWORD" = 'p@$$ word!'
check "config round-trips numeric fields" test "$SERVER_PORT:$SERVER_BACKEND:$SERVER_PUBLIC" = '2456:crossplay:0'
rm -f -- "$config"

bad_config=$(mktemp)
cat > "$bad_config" <<'EOF'
CONFIG_VERSION=1
UNEXPECTED_COMMAND=touch /tmp/should-not-run
EOF
if (load_config "$bad_config" >/dev/null 2>&1); then
    echo "unknown configuration keys must be rejected" >&2
    exit 1
fi
rm -f -- "$bad_config"
tests=$((tests + 1))
printf 'ok %d - unknown configuration keys are rejected\n' "$tests"

worlds=$(mktemp -d)
touch "$worlds/Complete World.db" "$worlds/Complete World.fwl"
touch "$worlds/Incomplete.db"
touch "$worlds/Ignored_backup_1.db" "$worlds/Ignored_backup_1.fwl"
mapfile -d '' pairs < <(list_world_pairs "$worlds")
check "world discovery returns only complete valid pairs" test "${#pairs[@]}" -eq 1
check "world discovery preserves spaces" test "${pairs[0]##*/}" = "Complete World"
rm -rf -- "$worlds"

printf '1..%d\n' "$tests"
(( failures == 0 ))
