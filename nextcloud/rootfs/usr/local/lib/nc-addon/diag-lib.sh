#!/usr/bin/env bash
# Pure classification helpers used by nc-diag (unit-tested in tests/unit).

# classify_code_status <json> -> ok | starting | restarting | <error id> | unparseable
classify_code_status() {
    local s e
    s="$(printf '%s' "$1" | jq -r '.status // empty' 2>/dev/null)" || s=""
    [ -n "$s" ] || { echo unparseable; return; }
    case "$s" in
        OK) echo ok ;;
        starting|restarting) echo "$s" ;;
        error) e="$(printf '%s' "$1" | jq -r '.error // "unknown"')"; echo "$e" ;;
        *) echo unparseable ;;
    esac
}

# code_error_hint <id> -> actionable text
code_error_hint() {
    case "$1" in
        no_glibc) echo "The AppImage cannot be executed by the dynamic loader (LD_TRACE_LOADED_OBJECTS failed). Typical cause: musl-based image (Alpine/LinuxServer). This add-on uses the Debian glibc official image; if you see this here the base image was replaced." ;;
        no_fontconfig) echo "fontconfig is missing from the container. The add-on image ships it; rebuild the image." ;;
        not_x86_64) echo "The 'richdocumentscode' app only runs on x86_64. On aarch64 install 'richdocumentscode_arm64' instead." ;;
        not_linux) echo "Built-in CODE only runs on Linux." ;;
        appimage_missing) echo "collabora/Collabora_Online.AppImage is missing: reinstall the CODE app (occ app:remove, then app:install)." ;;
        appimage_not_executable) echo "AppImage is not executable and chmod failed: check ownership of the apps directory (must be www-data)." ;;
        exec_disabled) echo "PHP exec/proc_open are disabled in disable_functions; built-in CODE needs them." ;;
        starting|restarting) echo "CODE is still starting; the first start can take a minute or more." ;;
        *) echo "Unknown CODE error '$1'. Check the add-on log." ;;
    esac
}

# classify_curl_exit <exit code> -> ok | dns | refused | timeout | tls | other
classify_curl_exit() {
    case "$1" in
        0) echo ok ;;
        6) echo dns ;;
        7) echo refused ;;
        28) echo timeout ;;
        35|51|58|59|60|77|82|83|90|91) echo tls ;;
        *) echo other ;;
    esac
}

# classify_http <http_code> <headers_file> <body_file>
#   -> ok | cloudflare_access | cloudflare_block | proxy_redirect | bad_gateway | http_<code>
classify_http() {
    local code="$1" h="$2" b="$3"
    if grep -qiE '^(location:.*cloudflareaccess\.com|cf-access-)' "$h" 2>/dev/null \
       || grep -qiE 'cloudflareaccess\.com|Cloudflare Access' "$b" 2>/dev/null; then
        echo cloudflare_access; return
    fi
    if [ "$code" = 403 ] && grep -qiE '^(cf-mitigated|server: cloudflare)' "$h" 2>/dev/null; then
        echo cloudflare_block; return
    fi
    case "$code" in
        200) echo ok ;;
        301|302|307|308) echo proxy_redirect ;;
        502|503|504|521|522|523|524|530) echo bad_gateway ;;
        *) echo "http_$code" ;;
    esac
}

# classify_occ_error <text> -> incompatible_office | tls | dns | cloudflare_access | timeout | wopi | other
classify_occ_error() {
    local t="$1"
    case "$t" in
        *"not compatible"*|*"requires Nextcloud"*|*"No compatible version"*|*"incompatible"*) echo incompatible_office ;;
        *"SSL certificate"*|*"cURL error 60"*|*"cURL error 35"*|*"certificate verify"*) echo tls ;;
        *"Could not resolve host"*|*"cURL error 6"*) echo dns ;;
        *cloudflareaccess*|*"Cloudflare Access"*) echo cloudflare_access ;;
        *"timed out"*|*"cURL error 28"*) echo timeout ;;
        *WOPI*|*wopi*|*"not allowed"*) echo wopi ;;
        *) echo other ;;
    esac
}

# xml_valid <file>: well-formed XML? (php is always present in the image)
xml_valid() { php -r '$d = new DOMDocument(); libxml_use_internal_errors(true); exit($d->load($argv[1]) ? 0 : 1);' "$1" 2>/dev/null; }

# mem_assessment <MemAvailable kB> -> ok | low | critical
mem_assessment() {
    if [ "$1" -lt 1048576 ]; then echo critical; elif [ "$1" -lt 2097152 ]; then echo low; else echo ok; fi
}
