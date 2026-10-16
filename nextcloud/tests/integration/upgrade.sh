#!/usr/bin/env bash
# Upgrade test: install with an OLD add-on image, then start a NEW image on the same volumes.
# Verifies: automatic verified pre-upgrade backup, Nextcloud upgrade, users and files kept, healthy afterwards.
# Usage: tests/integration/upgrade.sh <old-image> <new-image>
# Requires Docker and internet access. MariaDB only (the upgrade logic is engine-independent).
set -uo pipefail
OLD="${1:?old image}"; NEW="${2:?new image}"
P="ncup$$"
PASS_ADMIN="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)A1"
PASS_DB="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)"
FAILS=0
export MSYS_NO_PATHCONV=1
command -v jq >/dev/null 2>&1 || jq() { docker run --rm -i --entrypoint jq "$NEW" "$@"; }

ok()  { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; FAILS=$((FAILS + 1)); }
cleanup() {
    docker rm -f "$P-nc" "$P-db" >/dev/null 2>&1
    docker volume rm "$P-data" "$P-dbdata" "$P-bk" >/dev/null 2>&1
    docker network rm "$P-net" >/dev/null 2>&1
}
trap cleanup EXIT

ready() { local i=0; while [ "$i" -lt "$1" ]; do
    docker exec "$P-nc" curl -fsS http://127.0.0.1/status.php 2>/dev/null | grep '"installed":true' >/dev/null && return 0
    sleep 5; i=$((i + 5)); done; return 1; }
ver() { docker exec "$P-nc" curl -fsS http://127.0.0.1/status.php | jq -r .versionstring; }
occ() { docker exec "$P-nc" runuser -u www-data -- php /data/nextcloud/html/occ "$@"; }

docker network create "$P-net" >/dev/null
for v in data dbdata bk; do docker volume create "$P-$v" >/dev/null; done
docker run -d --name "$P-db" --network "$P-net" --network-alias db -v "$P-dbdata":/var/lib/mysql \
    -e MARIADB_RANDOM_ROOT_PASSWORD=1 -e MARIADB_DATABASE=nextcloud -e MARIADB_USER=nc -e MARIADB_PASSWORD="$PASS_DB" \
    mariadb:11 --transaction-isolation=READ-COMMITTED --binlog-format=ROW >/dev/null
sleep 20
OPT="$(jq -n --arg ap "$PASS_ADMIN" --arg dp "$PASS_DB" '{
  public_url:"http://localhost", internal_url:"", trusted_domains:[], trusted_proxies:["172.16.0.0/12"],
  db_type:"mariadb", db_mode:"external", db_host:"db", db_port:0, db_name:"nextcloud", db_user:"nc", db_password:$dp,
  admin_user:"admin", admin_password:$ap, data_path:"/data/nextcloud-data", background_jobs:"cron", php_memory_limit:"512M",
  upload_limit:"1G", default_phone_region:"DE", enable_office:false, code_diagnostics:false, code_start_timeout:120,
  backup_on_start:false, migration_mode:false, log_level:"info"}')"
docker run --rm -v "$P-data":/data -e OPT="$OPT" --entrypoint sh "$OLD" -c 'printf "%s" "$OPT" > /data/options.json'

echo "### install with OLD image"
docker run -d --name "$P-nc" --network "$P-net" -v "$P-data":/data -v "$P-bk":/backup "$OLD" >/dev/null
if ready 600; then ok "old image installed"; else bad "old install"; exit 1; fi
OLDV="$(ver)"; echo "old version: $OLDV"
docker exec "$P-nc" runuser -u www-data -- sh -c 'echo upgrade-test > /data/nextcloud-data/admin/files/keep.txt'
occ files:scan admin >/dev/null 2>&1
BEFORE="$(occ user:list --output=json | jq -r 'keys|join(",")')"
docker stop -t 60 "$P-nc" >/dev/null; docker rm "$P-nc" >/dev/null

echo "### start NEW image on the same volumes"
docker run -d --name "$P-nc" --network "$P-net" -v "$P-data":/data -v "$P-bk":/backup "$NEW" >/dev/null
if ready 900; then ok "new image up"; else bad "new image did not come up"; docker logs "$P-nc" 2>&1 | tail -n 30; fi
NEWV="$(ver)"; echo "new version: $NEWV"
[ "$NEWV" != "$OLDV" ] && ok "version changed $OLDV -> $NEWV" || bad "version unchanged ($NEWV)"
docker logs "$P-nc" 2>&1 | grep 'Upgrade pending' >/dev/null && ok "upgrade detected and logged" || bad "upgrade not logged"
BK="$(docker exec "$P-nc" ls /backup/nextcloud_official | grep pre-upgrade | grep -v FAILED | head -n1)"
[ -n "$BK" ] && ok "pre-upgrade backup exists: $BK" || bad "no pre-upgrade backup"
docker exec "$P-nc" test -f "/backup/nextcloud_official/$BK/.verified" && ok "pre-upgrade backup verified" || bad "backup not verified"
docker exec "$P-nc" nc-backup verify "/backup/nextcloud_official/$BK" >/dev/null 2>&1 && ok "backup verifies again" || bad "backup verify"
AFTER="$(occ user:list --output=json | jq -r 'keys|join(",")')"
[ "$BEFORE" = "$AFTER" ] && ok "users preserved" || bad "users changed"
docker exec "$P-nc" test -f /data/nextcloud-data/admin/files/keep.txt && ok "file preserved" || bad "file lost"
docker exec "$P-nc" curl -fsS http://127.0.0.1/status.php | jq -e '.maintenance==false and .needsDbUpgrade==false' >/dev/null 2>&1 && ok "no pending upgrade, not in maintenance" || bad "upgrade pending/maintenance"

echo "failures: $FAILS"
[ "$FAILS" = 0 ]
