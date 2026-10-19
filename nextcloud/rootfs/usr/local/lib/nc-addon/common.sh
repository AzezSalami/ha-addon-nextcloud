#!/usr/bin/env bash
# Shared helpers for the add-on scripts. Source, do not execute.

# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/db.sh"

NC_OPTIONS_FILE="${NC_OPTIONS_FILE:-/data/options.json}"
NC_LOG_LEVEL="${NC_LOG_LEVEL:-info}"
NC_WEBROOT="${NC_WEBROOT:-/data/nextcloud/html}"
NC_STATE_DIR="${NC_STATE_DIR:-/data/nextcloud}"

# Values that must never appear in logs. Callers add to this array.
NC_SECRET_VALUES=()

_log_rank() {
    case "$1" in debug) echo 0 ;; info) echo 1 ;; warning) echo 2 ;; error) echo 3 ;; *) echo 1 ;; esac
}

# redact: stdin -> stdout with every registered secret replaced.
redact() {
    local line s
    while IFS= read -r line || [ -n "$line" ]; do
        for s in "${NC_SECRET_VALUES[@]}"; do
            [ -n "$s" ] && line="${line//"$s"/***}"
        done
        printf '%s\n' "$line"
    done
}

log() {
    local level="$1"; shift
    [ "$(_log_rank "$level")" -ge "$(_log_rank "$NC_LOG_LEVEL")" ] || return 0
    printf '[%s] %-7s %s\n' "$(date -u +%H:%M:%S)" "$level" "$*" | redact
}

die() { log error "$*"; exit 1; }

opt() { jq -r --arg k "$1" '.[$k] // empty | if type=="array" then join(" ") else tostring end' "$NC_OPTIONS_FILE"; }
opt_list() { jq -r --arg k "$1" '.[$k] // [] | .[]' "$NC_OPTIONS_FILE"; }

# detect_arch -> prints x86_64 or aarch64 (returns 1 and prints the raw value otherwise).
# NC_UNAME_M overrides uname for tests.
detect_arch() {
    local m="${NC_UNAME_M:-$(uname -m)}"
    case "$m" in
        x86_64|amd64) echo x86_64 ;;
        aarch64|arm64) echo aarch64 ;;
        *) echo "$m"; return 1 ;;
    esac
}

# code_app_id <arch> -> Nextcloud app id providing the built-in CODE for that architecture.
code_app_id() {
    case "$1" in
        x86_64) echo richdocumentscode ;;
        aarch64) echo richdocumentscode_arm64 ;;
        *) return 1 ;;
    esac
}

# detect_libc -> glibc | musl | unknown. NC_LIBC_OVERRIDE for tests.
detect_libc() {
    if [ -n "${NC_LIBC_OVERRIDE:-}" ]; then echo "$NC_LIBC_OVERRIDE"; return; fi
    local out
    out="$(ldd --version 2>&1 | head -n1 || true)"
    case "$out" in
        *[Mm]usl*) echo musl ;;
        *GNU*|*GLIBC*|*glibc*) echo glibc ;;
        *) echo unknown ;;
    esac
}

glibc_version() { ldd --version 2>&1 | head -n1 | grep -oE '[0-9]+\.[0-9]+$' || true; }

# ver_ge A B: true if version A >= B
ver_ge() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]; }

# url_host <url> -> host[:port]
url_host() { printf '%s' "$1" | sed -E 's#^[a-zA-Z]+://([^/]+).*#\1#'; }
url_scheme() { printf '%s' "$1" | sed -E 's#^([a-zA-Z]+)://.*#\1#'; }

occ() { runuser -u www-data -- php -d memory_limit=-1 "$NC_WEBROOT/occ" "$@"; }

nc_installed() { grep -qE "'installed'[[:space:]]*=>[[:space:]]*true" "$NC_WEBROOT/config/config.php" 2>/dev/null; }

# cfg_get <config.php> <key>: scalar value from a Nextcloud config.php (empty if unset). Never use for secrets in logs.
cfg_get() {
    php -r 'include $argv[1]; $v = $CONFIG[$argv[2]] ?? ""; echo is_scalar($v) ? (string)$v : json_encode($v);' "$1" "$2" 2>/dev/null
}

# db_connect_from_config <config.php>: sets DBTYPE DBH DBP DBN DBU and exports the DB password
# variables (do not log). Engine helpers live in db.sh.
# shellcheck disable=SC2034  # these are consumed by the scripts that source this file
db_connect_from_config() {
    local c="$1" host pw
    host="$(cfg_get "$c" dbhost)"
    DBTYPE="$(db_kind_to_type "$(cfg_get "$c" dbtype)")"
    DBH="${host%%:*}"; DBP="$(db_default_port "$DBTYPE")"
    case "$host" in *:*) DBP="${host##*:}" ;; esac
    DBN="$(cfg_get "$c" dbname)"; DBU="$(cfg_get "$c" dbuser)"
    pw="$(cfg_get "$c" dbpassword)"
    db_set_password "$pw"
    NC_SECRET_VALUES+=("$pw")
}

# Code version from a version.php: prints e.g. 35.0.1
nc_code_version() {
    local f="${1:-$NC_WEBROOT/version.php}"
    php -r 'include $argv[1]; echo implode(".", array_slice($OC_Version,0,3));' "$f" 2>/dev/null
}

# code_proxy_path <app id> -> web path of the CODE app proxy. Apps installed from the app store live in
# custom_apps and are served under /custom_apps/, bundled apps under /apps/.
code_proxy_path() {
    if [ -d "$NC_WEBROOT/apps/$1" ]; then echo "/apps/$1/proxy.php"
    elif [ -d "$NC_WEBROOT/custom_apps/$1" ]; then echo "/custom_apps/$1/proxy.php"
    else echo "/apps/$1/proxy.php"; fi
}

# office_refresh: refresh Nextcloud Office's cached discovery/capabilities (richdocuments:activate-config).
# That command also resets the callback URL, so a configured one (the internal_url option) is put back.
# Output of the command is left in OFFICE_REFRESH_OUT; the return code is the command's.
# shellcheck disable=SC2034  # OFFICE_REFRESH_OUT is read by the scripts that call this
office_refresh() {
    local cb rc
    cb="$(occ config:app:get richdocuments wopi_callback_url 2>/dev/null || true)"
    OFFICE_REFRESH_OUT="$(occ richdocuments:activate-config 2>&1)"; rc=$?
    [ -z "$cb" ] || occ config:app:set richdocuments wopi_callback_url --value="$cb" >/dev/null 2>&1 || true
    return $rc
}

# office_base_url: the address Nextcloud Office (the built-in server) is bound to; prints nothing if there is none.
# Browsers may only start the built-in server through the address Nextcloud itself is opened on (Nextcloud's
# Content-Security-Policy), so this is the one address on which documents open: public_url, else the first
# LAN address in trusted_domains (https when ssl is on). "localhost" is not an address other devices can use.
office_base_url() {
    local pu first
    pu="$(opt public_url)"
    if [ -n "$pu" ]; then printf '%s' "$pu"; return 0; fi
    first="$(head -n1 "${NC_TRUSTED_FILE:-/run/nc-addon/trusted_domains}" 2>/dev/null || true)"
    case "$first" in ""|localhost|localhost:*) return 0 ;; esac
    if [ "$(opt ssl)" = true ]; then printf 'https://%s' "$first"; else printf 'http://%s' "$first"; fi
}
