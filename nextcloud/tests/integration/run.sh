#!/usr/bin/env bash
# Integration tests: build/run the add-on image against a real MariaDB and exercise it.
# Requires Docker and internet access (installs Nextcloud Office + built-in CODE from the app store).
# Usage: tests/integration/run.sh [image]   (default: builds ncaddon:test from ./nextcloud)
# This does NOT replace testing under a real Home Assistant Supervisor (see docs/TESTING.md).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
IMG="${1:-ncaddon:test}"
P="nctest$$"
PASS_ADMIN="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)A1"
PASS_DB="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)"
PORT="${NC_TEST_PORT:-18080}"
RESULTS=(); FAILS=0
export MSYS_NO_PATHCONV=1
# host may lack jq (e.g. Git Bash): fall back to the jq inside the image
command -v jq >/dev/null 2>&1 || jq() { docker run --rm -i --entrypoint jq "$IMG" "$@"; }

ok()   { RESULTS+=("PASS  $1"); echo "PASS  $1"; }
bad()  { RESULTS+=("FAIL  $1"); echo "FAIL  $1"; FAILS=$((FAILS + 1)); }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }
dexec() { docker exec "$P-nc" "$@"; }
cleanup() {
    docker rm -f "$P-nc" "$P-nc2" "$P-db" >/dev/null 2>&1
    docker volume rm "$P-data" "$P-dbdata" "$P-bk" "$P-data2" >/dev/null 2>&1
    docker network rm "$P-net" >/dev/null 2>&1
}
trap cleanup EXIT

wait_ready() { # wait_ready <container> <timeout-seconds>
    local c="$1" t="$2" i=0
    while [ "$i" -lt "$t" ]; do
        docker exec "$c" curl -fsS http://127.0.0.1/status.php 2>/dev/null | grep '"installed":true' >/dev/null && return 0
        sleep 5; i=$((i + 5))
    done
    return 1
}
write_options() { # write_options <volume> <json>
    docker run --rm -v "$1":/data -e OPT="$2" --entrypoint sh "$IMG" -c 'printf "%s" "$OPT" > /data/options.json'
}
options_json() {
    jq -n --arg ap "$PASS_ADMIN" --arg dp "$PASS_DB" --arg db "$1" --arg dd "$2" --argjson mig "${3:-false}" '{
      public_url:"http://localhost", internal_url:"", trusted_domains:[], trusted_proxies:["172.16.0.0/12"],
      db_mode:"external", db_host:"db", db_port:3306, db_name:$db, db_user:"nc", db_password:$dp,
      admin_user:"admin", admin_password:$ap, data_path:$dd, background_jobs:"cron", php_memory_limit:"512M",
      upload_limit:"1G", default_phone_region:"DE", enable_office:true, code_diagnostics:false,
      code_start_timeout:300, backup_on_start:false, migration_mode:$mig, log_level:"info"}'
}

if [ "${1:-}" = "" ]; then docker build -t "$IMG" "$ROOT" >/dev/null 2>&1 || { echo "build failed"; exit 1; }; fi

docker network create "$P-net" >/dev/null
docker volume create "$P-data" >/dev/null; docker volume create "$P-dbdata" >/dev/null; docker volume create "$P-bk" >/dev/null
docker run -d --name "$P-db" --network "$P-net" --network-alias db -v "$P-dbdata":/var/lib/mysql \
    -e MARIADB_RANDOM_ROOT_PASSWORD=1 -e MARIADB_DATABASE=nextcloud -e MARIADB_USER=nc -e MARIADB_PASSWORD="$PASS_DB" \
    mariadb:11 --transaction-isolation=READ-COMMITTED --binlog-format=ROW >/dev/null
sleep 20
write_options "$P-data" "$(options_json nextcloud /data/nextcloud-data)"

echo "### start"
docker run -d --name "$P-nc" --network "$P-net" -p "$PORT:80" -v "$P-data":/data -v "$P-bk":/backup "$IMG" >/dev/null
if wait_ready "$P-nc" 900; then ok "first start: Nextcloud installed (status.php)"; else bad "first start"; docker logs "$P-nc" 2>&1 | tail -n 40; exit 1; fi
curl -fsS "http://127.0.0.1:$PORT/status.php" | jq -e '.installed==true and .maintenance==false and .needsDbUpgrade==false' >/dev/null 2>&1 && ok "status.php healthy JSON" || bad "status.php healthy JSON"
check "container is glibc" bash -c "docker exec $P-nc ldd --version 2>&1 | head -1 | grep -qi 'gnu\|glibc'"

echo "### built-in CODE"
for _ in $(seq 1 90); do
    dexec sh -c '. /usr/local/lib/nc-addon/common.sh; occ app:list --output=json' 2>/dev/null | jq -e '.enabled|has("richdocuments")' >/dev/null 2>&1 && break
    sleep 10
done
APP="richdocumentscode"; [ "$(dexec uname -m)" = aarch64 ] && APP="richdocumentscode_arm64"
PROXY="$(dexec sh -c ". /usr/local/lib/nc-addon/common.sh; code_proxy_path $APP")"
for _ in $(seq 1 60); do
    st="$(dexec curl -sS -H 'Host: localhost' "http://127.0.0.1$PROXY?status" 2>/dev/null)"
    [ "$(jq -r .status <<<"$st" 2>/dev/null)" = OK ] && break; sleep 5
done
[ "$(jq -r .status <<<"$st" 2>/dev/null)" = OK ] && ok "CODE status == OK (not no_glibc)" || bad "CODE status: $st"
dexec curl -sS -H 'Host: localhost' "http://127.0.0.1$PROXY?req=/hosting/capabilities" | jq -e . >/dev/null 2>&1 && ok "capabilities valid JSON" || bad "capabilities"
dexec curl -sS -H 'Host: localhost' "http://127.0.0.1$PROXY?req=/hosting/discovery" >"$HERE/.disc.xml" 2>/dev/null
grep -q '<wopi-discovery' "$HERE/.disc.xml" && ok "discovery returns WOPI XML" || bad "discovery XML"
rm -f "$HERE/.disc.xml"
check "healthcheck script" docker exec "$P-nc" nc-healthcheck
dexec nc-diag >"$HERE/.diag.txt" 2>&1; grep -qi 'password\|secret' "$HERE/.diag.txt" && bad "diag leaks secret-like text" || ok "diag report has no secrets"
grep -q 'proxy.php?status    : ok' "$HERE/.diag.txt" && ok "nc-diag reports CODE ok" || { bad "nc-diag CODE"; cat "$HERE/.diag.txt"; }
rm -f "$HERE/.diag.txt"
docker logs "$P-nc" 2>&1 | grep -F "$PASS_ADMIN" >/dev/null && bad "admin password leaked into logs" || ok "no admin password in logs"
docker logs "$P-nc" 2>&1 | grep -F "$PASS_DB" >/dev/null && bad "db password leaked into logs" || ok "no db password in logs"

echo "### persistence + restart"
dexec runuser -u www-data -- sh -c 'echo persist-test > /data/nextcloud/html/../../data/nextcloud-data/admin/files/persist.txt' 2>/dev/null
dexec runuser -u www-data -- php /data/nextcloud/html/occ files:scan admin >/dev/null 2>&1
before="$(dexec runuser -u www-data -- php /data/nextcloud/html/occ user:list --output=json | jq -r 'keys|join(",")')"
STOP_START=$(date +%s)
docker stop -t 90 "$P-nc" >/dev/null; STOP_T=$(( $(date +%s) - STOP_START ))
[ "$STOP_T" -lt 60 ] && ok "graceful stop (${STOP_T}s)" || bad "slow stop ${STOP_T}s"
[ "$(docker inspect -f '{{.State.ExitCode}}' "$P-nc")" = 0 ] && ok "exit code 0 on SIGTERM" || bad "exit code $(docker inspect -f '{{.State.ExitCode}}' "$P-nc")"
docker start "$P-nc" >/dev/null
wait_ready "$P-nc" 300 && ok "restart recovery" || bad "restart recovery"
after="$(dexec runuser -u www-data -- php /data/nextcloud/html/occ user:list --output=json | jq -r 'keys|join(",")')"
[ "$before" = "$after" ] && ok "users survive restart" || bad "users changed"
dexec test -f /data/nextcloud-data/admin/files/persist.txt && ok "file survives restart" || bad "file lost"
dexec test -f /data/nextcloud/html/config/config.php && ok "config lives on persistent /data" || bad "config not on /data"

echo "### backup / restore"
BK="$(dexec nc-backup create --label itest | tail -n1)"
[ -n "$BK" ] && check "backup verifies" dexec nc-backup verify "$BK" || bad "backup create"
dexec rm -f /data/nextcloud-data/admin/files/persist.txt
dexec runuser -u www-data -- php /data/nextcloud/html/occ user:add --password-from-env --display-name=Temp temp1 >/dev/null 2>&1 <<<"" || true
dexec nc-backup restore "$BK" --yes-restore >/dev/null 2>&1 && ok "restore ran" || bad "restore"
dexec test -f /data/nextcloud-data/admin/files/persist.txt && ok "restore brought back deleted file" || bad "restore data"
wait_ready "$P-nc" 120 && ok "healthy after restore" || bad "unhealthy after restore"

echo "### safety: refuses to install over existing DB / data"
docker run --rm --network "$P-net" -v "$P-data":/x --entrypoint sh "$IMG" -c 'true'
docker volume create "$P-data2" >/dev/null
write_options "$P-data2" "$(options_json nextcloud /data/nextcloud-data)"
docker run -d --name "$P-nc2" --network "$P-net" -v "$P-data2":/data "$IMG" >/dev/null
sleep 25
docker logs "$P-nc2" 2>&1 | grep 'Refusing to install over it' >/dev/null && ok "refuses to install over existing database" || bad "did not refuse existing DB"
docker rm -f "$P-nc2" >/dev/null

echo "### rollback guard (downgrade refused)"
dexec sed -i "s/'version' => '[0-9.]*'/'version' => '99.0.0.0'/" /data/nextcloud/html/config/config.php
dexec sh -c "sed -i 's/\\\$OC_Version = array([0-9]*/\\\$OC_Version = array(99/' /data/nextcloud/html/version.php"
docker restart "$P-nc" >/dev/null; sleep 20
docker logs "$P-nc" 2>&1 | tail -n 5 | grep 'newer than the image' >/dev/null && ok "downgrade refused" || bad "downgrade not refused"

echo
printf '%s\n' "${RESULTS[@]}"
echo "failures: $FAILS"
[ "$FAILS" = 0 ]
