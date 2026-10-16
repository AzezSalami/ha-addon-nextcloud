#!/usr/bin/env bash
# Web interface test: plain HTTP vs HTTPS (ssl option), LAN access vs public_url, bad certificates.
# Usage: tests/integration/ssl.sh [image]     Requires Docker. Uses a throw-away self-signed certificate.
set -uo pipefail
IMG="${1:-ncaddon:test}"
P="ncssl$$"
PASS_ADMIN="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)A1"
PASS_DB="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)"
FAILS=0
export MSYS_NO_PATHCONV=1
command -v jq >/dev/null 2>&1 || jq() { docker run --rm -i --entrypoint jq "$IMG" "$@"; }

ok()  { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; FAILS=$((FAILS + 1)); }
cleanup() {
    docker rm -f "$P-nc" "$P-db" >/dev/null 2>&1
    docker volume rm "$P-data" "$P-ssl" "$P-db" >/dev/null 2>&1
    docker network rm "$P-net" >/dev/null 2>&1
}
trap cleanup EXIT
dx() { docker exec "$P-nc" "$@"; }
ready() { local i=0; while [ "$i" -lt "$1" ]; do
    dx curl -fsS http://127.0.0.1/status.php 2>/dev/null | grep '"installed":true' >/dev/null && return 0
    sleep 3; i=$((i + 3)); done; return 1; }
opts() { # opts <ssl true|false> <force_public_url true|false>
    jq -n --arg ap "$PASS_ADMIN" --arg dp "$PASS_DB" --argjson ssl "$1" --argjson force "$2" '{
      public_url:"https://gg.example.test", internal_url:"", trusted_domains:["192.168.1.50:8099","localhost"],
      trusted_proxies:["172.16.0.0/12"], force_public_url:$force, ssl:$ssl, certfile:"fullchain.pem", keyfile:"privkey.pem",
      db_type:"mariadb", db_mode:"external", db_host:"db", db_port:0, db_name:"nextcloud", db_user:"nc", db_password:$dp,
      admin_user:"admin", admin_password:$ap, data_path:"/data/nextcloud-data", background_jobs:"cron", php_memory_limit:"512M",
      upload_limit:"1G", default_phone_region:"", enable_office:false, code_diagnostics:false, code_start_timeout:120,
      backup_on_start:false, migration_mode:false, log_level:"info"}'
}
setopts() { docker run --rm -v "$P-data":/data -e OPT="$(opts "$1" "$2")" --entrypoint sh "$IMG" -c 'printf "%s" "$OPT" > /data/options.json'; }
location() { dx curl -s -o /dev/null -D - "$@" | grep -i '^location' | tr -d '\r'; }

docker network create "$P-net" >/dev/null
for v in data ssl db; do docker volume create "$P-$v" >/dev/null; done
docker run -d --name "$P-db" --network "$P-net" --network-alias db -v "$P-db":/var/lib/mysql \
    -e MARIADB_RANDOM_ROOT_PASSWORD=1 -e MARIADB_DATABASE=nextcloud -e MARIADB_USER=nc -e MARIADB_PASSWORD="$PASS_DB" mariadb:11 >/dev/null
docker run --rm -v "$P-ssl":/ssl --entrypoint sh "$IMG" -c \
    'openssl req -x509 -newkey rsa:2048 -nodes -keyout /ssl/privkey.pem -out /ssl/fullchain.pem -days 30 -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" 2>/dev/null; openssl req -x509 -newkey rsa:2048 -nodes -keyout /ssl/other.key -out /ssl/other.pem -days 30 -subj "/CN=other" 2>/dev/null'
sleep 15

echo "### ssl=false (plain HTTP on the web interface port)"
setopts false false
docker run -d --name "$P-nc" --network "$P-net" --network-alias ncx -v "$P-data":/data -v "$P-ssl":/ssl:ro "$IMG" >/dev/null
if ready 600; then ok "installed"; else bad "install"; docker logs "$P-nc" 2>&1 | tail -n 20; exit 1; fi
dx curl -fsS -H 'Host: localhost' http://127.0.0.1:443/status.php | grep '"installed":true' >/dev/null && ok "plain HTTP answers on container port 443" || bad "443 plain"
dx curl -fsS http://127.0.0.1:80/status.php | grep '"installed":true' >/dev/null && ok "plain HTTP answers on container port 80" || bad "port 80"
dx curl -sk -m 5 -o /dev/null https://127.0.0.1:443/status.php && bad "HTTPS unexpectedly works with ssl=false" || ok "HTTPS not offered with ssl=false"
L="$(location -H 'Host: 192.168.1.50:8099' http://127.0.0.1:443/)"; echo "  LAN visitor -> $L"
echo "$L" | grep -F 'http://192.168.1.50:8099/' >/dev/null && ok "LAN access keeps its own address (no redirect to public_url)" || bad "LAN access redirected: $L"
L="$(docker run --rm --network "$P-net" curlimages/curl -s -o /dev/null -D - -H 'Host: gg.example.test' -H 'X-Forwarded-Proto: https' http://ncx:80/ | grep -i '^location' | tr -d '')"; echo "  tunnel visitor -> $L"
echo "$L" | grep -F 'https://gg.example.test/' >/dev/null && ok "tunnel visitor (from a trusted proxy address) gets the https public address" || bad "tunnel visitor: $L"

echo "### force_public_url=true"
setopts false true; docker restart -t 30 "$P-nc" >/dev/null; ready 300 || bad "restart"
L="$(location -H 'Host: 192.168.1.50:8099' http://127.0.0.1:443/)"; echo "  LAN visitor -> $L"
echo "$L" | grep -F 'https://gg.example.test/' >/dev/null && ok "force_public_url pins links to public_url" || bad "force_public_url: $L"

echo "### ssl=true"
setopts true false; docker restart -t 30 "$P-nc" >/dev/null; ready 300 || { bad "restart with ssl"; docker logs "$P-nc" 2>&1 | tail -n 15; }
dx curl -fsS --cacert /ssl/fullchain.pem https://localhost:443/status.php | grep '"installed":true' >/dev/null && ok "HTTPS works and the certificate verifies (no -k)" || bad "HTTPS verify"
[ "$(dx curl -s -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:443/status.php)" != 200 ] && ok "plain HTTP is not served on the TLS port" || bad "plain HTTP still answers on the TLS port"
dx curl -fsS http://127.0.0.1:80/status.php | grep '"installed":true' >/dev/null && ok "port 80 still plain HTTP for a tunnel" || bad "port 80 after ssl"
L="$(location -k -H 'Host: 192.168.1.50:8099' https://127.0.0.1:443/)"; echo "  LAN visitor -> $L"
echo "$L" | grep -F 'https://192.168.1.50:8099/' >/dev/null && ok "HTTPS LAN access stays on its own address" || bad "https LAN: $L"
docker logs "$P-nc" 2>&1 | grep -F "HTTPS enabled on the web interface port" >/dev/null && ok "log says HTTPS enabled" || bad "log line"

echo "### bad certificates are refused with a clear message"
docker run --rm -v "$P-data":/data -e OPT="$(opts true false | jq '.keyfile="other.key"')" --entrypoint sh "$IMG" -c 'printf "%s" "$OPT" > /data/options.json'
docker restart -t 30 "$P-nc" >/dev/null; sleep 12
docker logs "$P-nc" 2>&1 | tail -n 6 | grep 'does not belong to the certificate' >/dev/null && ok "mismatched key refused" || bad "mismatched key not reported"
docker run --rm -v "$P-data":/data -e OPT="$(opts true false | jq '.certfile="missing.pem"')" --entrypoint sh "$IMG" -c 'printf "%s" "$OPT" > /data/options.json'
docker restart -t 30 "$P-nc" >/dev/null; sleep 12
docker logs "$P-nc" 2>&1 | tail -n 6 | grep 'not found or not readable' >/dev/null && ok "missing certificate refused" || bad "missing cert not reported"
[ "$(docker inspect -f '{{.State.Running}}' "$P-nc")" = false ] && ok "add-on stopped instead of starting without TLS" || bad "add-on kept running"

echo "failures: $FAILS"
[ "$FAILS" = 0 ]
