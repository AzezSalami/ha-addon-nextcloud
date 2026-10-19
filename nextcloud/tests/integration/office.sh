#!/usr/bin/env bash
# Nextcloud Office with public_url EMPTY (local-only setup): the add-on must configure the built-in server from the first
# trusted domain, so a normal (non-admin) user can open documents without an admin visiting Files first.
# Also checks that with a self-signed certificate Nextcloud trusts it (TLS verification stays on).
# Usage: tests/integration/office.sh [image]     Requires Docker and internet (installs Office from the app store).
set -uo pipefail
IMG="${1:-ncaddon:test}"
P="ncoff$$"
PASS_ADMIN="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)A1"
PASS_USER="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)B2"
PASS_DB="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)"
FAILS=0
export MSYS_NO_PATHCONV=1
command -v jq >/dev/null 2>&1 || jq() { docker run --rm -i --entrypoint jq "$IMG" "$@"; }

ok()  { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; FAILS=$((FAILS + 1)); }
cleanup() {
    docker rm -f "$P-nc" "$P-db" >/dev/null 2>&1
    docker volume rm "$P-data" "$P-db" >/dev/null 2>&1
    docker network rm "$P-net" >/dev/null 2>&1
}
trap cleanup EXIT
dx() { docker exec "$P-nc" "$@"; }
occ() { dx runuser -u www-data -- php /data/nextcloud/html/occ "$@"; }
logs_have() { docker logs "$P-nc" 2>&1 | grep -F "$1" >/dev/null; }
wait_log() { local i=0; while [ "$i" -lt "$2" ]; do logs_have "$1" && return 0; sleep 5; i=$((i + 5)); done; return 1; }
opts() { # opts <ssl true|false>
    jq -n --arg ap "$PASS_ADMIN" --arg dp "$PASS_DB" --argjson ssl "$1" '{
      public_url:"", internal_url:"", trusted_domains:["ncoffice:443"], trusted_proxies:["172.16.0.0/12"], force_public_url:false,
      ssl:$ssl, certfile:"", keyfile:"", ssl_allow_expired:false,
      db_type:"mariadb", db_mode:"external", db_host:"db", db_port:0, db_name:"nextcloud", db_user:"nc", db_password:$dp,
      admin_user:"admin", admin_password:$ap, data_path:"/data/nextcloud-data", background_jobs:"cron", php_memory_limit:"512M",
      upload_limit:"1G", default_phone_region:"", enable_office:true, code_diagnostics:true, code_start_timeout:300,
      backup_on_start:false, migration_mode:false, log_level:"info"}'
}
setopts() { docker run --rm -v "$P-data":/data -e OPT="$(opts "$1")" --entrypoint sh "$IMG" -c 'printf "%s" "$OPT" > /data/options.json'; }
caps_as() { # caps_as <user> <password> -> richdocuments capabilities JSON for that user
    dx curl -s -u "$1:$2" -H 'Host: ncoffice:443' -H 'OCS-APIRequest: true' 'http://127.0.0.1/ocs/v2.php/cloud/capabilities?format=json' \
        | jq -c '.ocs.data.capabilities.richdocuments // {}'
}

docker network create "$P-net" >/dev/null
docker volume create "$P-data" >/dev/null; docker volume create "$P-db" >/dev/null
docker run -d --name "$P-db" --network "$P-net" --network-alias db -v "$P-db":/var/lib/mysql \
    -e MARIADB_RANDOM_ROOT_PASSWORD=1 -e MARIADB_DATABASE=nextcloud -e MARIADB_USER=nc -e MARIADB_PASSWORD="$PASS_DB" mariadb:11 >/dev/null
sleep 15

echo "### public_url empty, ssl=false: first trusted domain (ncoffice:443, a name that resolves inside the test network) is used"
setopts false
docker run -d --name "$P-nc" --network "$P-net" --network-alias ncoffice -v "$P-data":/data "$IMG" >/dev/null
wait_log 'file-type list refreshed' 600 && ok "Office configured and refreshed at start" || { bad "Office setup did not finish"; docker logs "$P-nc" 2>&1 | tail -n 25; exit 1; }
APP="richdocumentscode"; [ "$(dx uname -m)" = aarch64 ] && APP="richdocumentscode_arm64"   # the CODE app depends on the CPU
EXPECT="http://ncoffice:443/custom_apps/$APP/proxy.php?req="
[ "$(occ config:app:get richdocuments wopi_url)" = "$EXPECT" ] && ok "wopi_url derived from trusted_domains" || bad "wopi_url is '$(occ config:app:get richdocuments wopi_url)'"
logs_have 'public_url is empty' && bad "old 'admin must open Files' hint still shown" || ok "no 'admin must open Files first' hint"
dx bash -c 'printf "%s" "'"$PASS_USER"'" > /tmp/pw && OC_PASS="$(cat /tmp/pw)" runuser -u www-data -- php /data/nextcloud/html/occ user:add --password-from-env --display-name=Normal normaluser' >/dev/null 2>&1
dx bash -c 'rm -f /tmp/pw'
C="$(caps_as normaluser "$PASS_USER")"
echo "$C" | jq -e '.config.wopi_url != "" and (.mimetypes|length) > 30' >/dev/null 2>&1 && ok "a NON-admin user gets Office with a configured server and 30+ file types" || bad "non-admin capabilities: $(echo "$C" | cut -c1-200)"
echo "$C" | jq -e '.mimetypes | map(select(contains("wordprocessingml.document") or contains("spreadsheetml.sheet") or contains("presentationml.presentation"))) | length == 3' >/dev/null 2>&1 && ok "docx, xlsx and pptx offered to the non-admin user" || bad "docx/xlsx/pptx missing for non-admin"
dx nc-diag 2>&1 | grep -F 'activate-config      : OK' >/dev/null && ok "nc-diag: activate-config OK" || bad "nc-diag activate-config"

echo "### public_url empty, ssl=true (self-signed): Nextcloud trusts the certificate, verification stays on"
setopts true; docker restart -t 30 "$P-nc" >/dev/null
sleep 20; wait_log 'self-signed certificate is trusted by Nextcloud' 300 && ok "self-signed certificate imported into Nextcloud's trust store" || { bad "certificate not imported"; docker logs "$P-nc" 2>&1 | tail -n 15; }
EXPECT="https://ncoffice:443/custom_apps/$APP/proxy.php?req="
for _ in $(seq 1 30); do [ "$(occ config:app:get richdocuments wopi_url)" = "$EXPECT" ] && break; sleep 5; done
[ "$(occ config:app:get richdocuments wopi_url)" = "$EXPECT" ] && ok "wopi_url switched to https with the same address" || bad "wopi_url is '$(occ config:app:get richdocuments wopi_url)'"
occ security:certificates | grep nextcloud-addon-selfsigned >/dev/null && ok "certificate listed in occ security:certificates" || bad "certificate not listed"
[ "$(occ config:app:get richdocuments disable_certificate_verification 2>/dev/null)" != yes ] && ok "TLS verification for Office is still on" || bad "TLS verification was disabled"
for _ in $(seq 1 30); do dx nc-diag 2>&1 | grep -F 'activate-config      : OK' >/dev/null && { GOOD=1; break; }; sleep 5; done
[ "${GOOD:-0}" = 1 ] && ok "activate-config OK over HTTPS with the self-signed certificate (verified, not bypassed)" || { bad "activate-config over HTTPS"; dx nc-diag 2>&1 | grep -A3 'activate-config'; }

echo "failures: $FAILS"
[ "$FAILS" = 0 ]
