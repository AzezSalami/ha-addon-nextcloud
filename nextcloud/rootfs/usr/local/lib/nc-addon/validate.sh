#!/usr/bin/env bash
# validate_options <options.json>: prints one message per line, returns non-zero on any error.
# Complements the Supervisor schema with semantic checks.

_re_host='^[A-Za-z0-9*]([A-Za-z0-9*.-]*[A-Za-z0-9])?(:[0-9]{1,5})?$'
_re_url='^https?://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?$'
_re_ipcidr='^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$|^[0-9A-Fa-f:]+(/[0-9]{1,3})?$'

validate_options() {
    local f="$1" rc=0 v k
    jq -e . "$f" >/dev/null 2>&1 || { echo "CONFIG ERROR: options file is not valid JSON"; return 1; }
    _get() { jq -r --arg k "$1" '.[$k] // "" | tostring' "$f"; }
    _err() { echo "CONFIG ERROR: $*"; rc=1; }

    v="$(_get public_url)"
    if [ -n "$v" ]; then
        [[ "$v" =~ $_re_url ]] || _err "public_url must look like https://cloud.example.com (no path, no trailing slash): '$v'"
        case "$v" in
            http://localhost*|http://127.*) ;;
            http://*) echo "CONFIG WARNING: public_url uses http://; use https:// behind Cloudflare Tunnel" ;;
        esac
    fi
    v="$(_get internal_url)"
    if [ -n "$v" ] && ! [[ "$v" =~ $_re_url ]]; then _err "internal_url must look like http://host[:port]: '$v'"; fi

    while IFS= read -r v; do
        [ -z "$v" ] && continue
        [[ "$v" =~ $_re_host ]] || _err "trusted_domains entry invalid: '$v'"
    done < <(jq -r '.trusted_domains // [] | .[]' "$f")

    while IFS= read -r v; do
        [ -z "$v" ] && continue
        [[ "$v" =~ $_re_ipcidr ]] || _err "trusted_proxies entry must be an IP or CIDR: '$v'"
    done < <(jq -r '.trusted_proxies // [] | .[]' "$f")

    for k in certfile keyfile; do
        v="$(_get "$k")"
        if [ -n "$v" ] && ! [[ "$v" =~ ^[A-Za-z0-9._-]+$ ]]; then
            _err "$k must be a plain file name inside Home Assistant's /ssl folder (no directories): '$v'"
        fi
    done
    # With ssl=true, certfile and keyfile either both name files in /ssl, or both stay empty
    # (the add-on then generates a self-signed certificate for the addresses in trusted_domains).
    if [ "$(_get ssl)" = true ]; then
        if [ -n "$(_get certfile)" ] && [ -z "$(_get keyfile)" ]; then _err "certfile is set but keyfile is empty (set both, or clear both for a self-signed certificate)"; fi
        if [ -z "$(_get certfile)" ] && [ -n "$(_get keyfile)" ]; then _err "keyfile is set but certfile is empty (set both, or clear both for a self-signed certificate)"; fi
    fi

    case "$(_get db_type)" in
        ""|mariadb) ;;
        postgresql)
            [ "$(_get db_mode)" = external ] || _err "db_type=postgresql requires db_mode=external (Home Assistant has no PostgreSQL service discovery)" ;;
        *) _err "db_type must be 'mariadb' or 'postgresql'" ;;
    esac
    v="$(_get db_port)"
    if [ -n "$v" ] && { ! [[ "$v" =~ ^[0-9]+$ ]] || [ "$v" -gt 65535 ]; }; then _err "db_port must be 0 (engine default) or 1-65535"; fi
    case "$(_get db_mode)" in
        supervisor) ;;
        external)
            for k in db_host db_user db_password; do
                [ -n "$(_get "$k")" ] || _err "db_mode=external requires $k"
            done ;;
        *) _err "db_mode must be 'supervisor' or 'external'" ;;
    esac
    v="$(_get db_name)"
    [[ "$v" =~ ^[A-Za-z0-9_]{1,64}$ ]] || _err "db_name may only contain letters, digits and underscore"

    v="$(_get admin_user)"
    if [ -n "$v" ] && ! [[ "$v" =~ ^[A-Za-z0-9._@-]{1,64}$ ]]; then _err "admin_user contains unsupported characters"; fi
    v="$(_get admin_password)"
    if [ -n "$v" ] && [ "${#v}" -lt 10 ]; then _err "admin_password must be at least 10 characters"; fi

    v="$(_get data_path)"
    case "$v" in
        /data/*|/share/*|/media/*) ;;
        *) _err "data_path must be below /data, /share or /media: '$v'" ;;
    esac
    case "$v" in *..*|*//*|*' '*) _err "data_path must be a clean absolute path (no '..', '//' or spaces)" ;; esac

    case "$(_get background_jobs)" in cron|ajax|webcron) ;; *) _err "background_jobs must be cron, ajax or webcron" ;; esac
    [[ "$(_get php_memory_limit)" =~ ^[0-9]+[MG]$ ]] || _err "php_memory_limit must look like 1024M"
    [[ "$(_get upload_limit)" =~ ^[0-9]+[MG]$ ]] || _err "upload_limit must look like 16G"
    [[ "$(_get default_phone_region)" =~ ^([A-Z]{2})?$ ]] || _err "default_phone_region must be an ISO 3166-1 code like DE"
    return $rc
}

# validate_first_install <options.json>: before the first install admin credentials are required.
validate_first_install() {
    local f="$1"
    if [ -z "$(jq -r '.admin_user // ""' "$f")" ] || [ -z "$(jq -r '.admin_password // ""' "$f")" ]; then
        echo "CONFIG ERROR: first start requires admin_user and admin_password (the web installer is never exposed)"
        return 1
    fi
}
