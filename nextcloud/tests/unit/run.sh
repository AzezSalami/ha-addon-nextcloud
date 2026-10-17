#!/usr/bin/env bash
# Unit tests (no Nextcloud, no network). Requires bash, jq, php-cli.
# Run inside the image:  docker run --rm -v "$PWD":/src --entrypoint bash <image> /src/tests/unit/run.sh
# or on any Linux with jq + php: tests/unit/run.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${NC_LIB_DIR:-$HERE/../../rootfs/usr/local/lib/nc-addon}"
# shellcheck source=/dev/null
. "$LIB/common.sh"; . "$LIB/validate.sh"; . "$LIB/diag-lib.sh"; . "$LIB/web.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
eq() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $1: expected '$3' got '$2'"; fi; }
rc() { local n="$1" want="$2"; shift 2; "$@" >/dev/null 2>&1; eq "$n" "$?" "$want"; }

good='{"public_url":"https://cloud.example.com","internal_url":"","trusted_domains":["nc.local"],"trusted_proxies":["172.30.32.0/23"],"db_mode":"external","db_host":"db","db_user":"u","db_password":"p","db_name":"nextcloud","admin_user":"admin","admin_password":"correct-horse-battery","data_path":"/data/nextcloud-data","background_jobs":"cron","php_memory_limit":"1024M","upload_limit":"16G","default_phone_region":"DE"}'
mk() { jq -c "$1" <<<"$good" >"$T/o.json"; }

echo "-- config validation"
printf '%s' "$good" >"$T/o.json";                     rc "valid config passes" 0 validate_options "$T/o.json"
mk '.public_url="https://cloud.example.com/"';       rc "trailing slash rejected" 1 validate_options "$T/o.json"
mk '.public_url="cloud.example.com"';                rc "scheme required" 1 validate_options "$T/o.json"
mk '.public_url="https://a.b/path"';                 rc "path rejected" 1 validate_options "$T/o.json"
mk '.public_url=""';                                 rc "empty public_url allowed" 0 validate_options "$T/o.json"
mk '.data_path="/etc/nextcloud"';                    rc "data_path outside allowed roots" 1 validate_options "$T/o.json"
mk '.data_path="/data/../etc"';                      rc "data_path traversal" 1 validate_options "$T/o.json"
mk '.data_path="/share/nc"';                         rc "data_path under /share ok" 0 validate_options "$T/o.json"
mk '.db_mode="external"|.db_host=""';                rc "external db needs host" 1 validate_options "$T/o.json"
mk '.db_mode="supervisor"|.db_host=""|.db_user=""|.db_password=""'; rc "supervisor db needs no creds" 0 validate_options "$T/o.json"
mk '.db_mode="bogus"';                               rc "bad db_mode" 1 validate_options "$T/o.json"
mk '.admin_password="short"';                        rc "short admin password" 1 validate_options "$T/o.json"
mk '.trusted_proxies=["not-an-ip"]';                 rc "bad trusted proxy" 1 validate_options "$T/o.json"
mk '.trusted_proxies=["10.0.0.0/8","fd00::/8"]';     rc "ipv4+ipv6 proxies ok" 0 validate_options "$T/o.json"
mk '.trusted_domains=["bad host"]';                  rc "bad trusted domain" 1 validate_options "$T/o.json"
mk '.php_memory_limit="lots"';                       rc "bad memory limit" 1 validate_options "$T/o.json"
mk '.background_jobs="never"';                       rc "bad background_jobs" 1 validate_options "$T/o.json"
mk '.db_name="a;drop"';                              rc "db_name injection" 1 validate_options "$T/o.json"
echo '{not json' >"$T/o.json";                       rc "invalid JSON" 1 validate_options "$T/o.json"
mk '.admin_user=""|.admin_password=""';              rc "first install needs admin" 1 validate_first_install "$T/o.json"
printf '%s' "$good" >"$T/o.json";                    rc "first install ok with admin" 0 validate_first_install "$T/o.json"
msg="$(mk '.admin_password="short"'; validate_options "$T/o.json")"
case "$msg" in *short*) eq "error message does not echo password value" leaked ok ;; *) eq "error message does not echo password value" ok ok ;; esac

echo "-- database engine selection"
mk '.db_type="postgresql"|.db_mode="external"';      rc "postgresql + external ok" 0 validate_options "$T/o.json"
mk '.db_type="postgresql"|.db_mode="supervisor"';    rc "postgresql needs external mode" 1 validate_options "$T/o.json"
mk '.db_type="mariadb"';                             rc "mariadb explicit ok" 0 validate_options "$T/o.json"
mk '.db_type="oracle"';                              rc "unknown db_type rejected" 1 validate_options "$T/o.json"
mk '.db_port=0';                                     rc "db_port 0 = engine default" 0 validate_options "$T/o.json"
mk '.db_port=70000';                                 rc "db_port out of range" 1 validate_options "$T/o.json"
mk '.ssl=true|.certfile="fullchain.pem"|.keyfile="privkey.pem"'; rc "ssl with default file names ok" 0 validate_options "$T/o.json"
mk '.ssl=true|.certfile=""|.keyfile=""';             rc "ssl with both files empty = self-signed ok" 0 validate_options "$T/o.json"
mk '.ssl=true|.certfile="a.pem"|.keyfile=""';        rc "certfile without keyfile rejected" 1 validate_options "$T/o.json"
mk '.ssl=true|.certfile=""|.keyfile="k.pem"';        rc "keyfile without certfile rejected" 1 validate_options "$T/o.json"
mk '.ssl=true|.certfile="c.pem"|.keyfile="k.pem"|.ssl_allow_expired=true'; rc "ssl_allow_expired accepted" 0 validate_options "$T/o.json"
mk '.ssl=true|.certfile="c.pem"|.keyfile="k.pem"|.ssl_allow_expired=true'
out="$(validate_options "$T/o.json")"
case "$out" in *"ssl_allow_expired is true"*) eq "ssl_allow_expired warns" ok ok ;; *) eq "ssl_allow_expired warns" bad ok ;; esac
mk '.certfile="../etc/passwd"';                      rc "certfile path traversal rejected" 1 validate_options "$T/o.json"
mk '.keyfile="sub/key.pem"';                         rc "keyfile with directory rejected" 1 validate_options "$T/o.json"
mk '.ssl=false|.certfile="whatever.pem"';            rc "ssl off ignores file existence" 0 validate_options "$T/o.json"
eq "kind mariadb" "$(db_kind_to_type mariadb)" mysql
eq "kind postgresql" "$(db_kind_to_type postgresql)" pgsql
eq "kind empty defaults to mysql" "$(db_kind_to_type '')" mysql
eq "default port mysql" "$(db_default_port mysql)" 3306
eq "default port pgsql" "$(db_default_port pgsql)" 5432
printf -- '-- Dump completed on 2026-01-01\n' | db_dump_complete; eq "mysql dump marker" "$?" 0
printf -- '--\n-- PostgreSQL database dump complete\n--\n' | db_dump_complete; eq "pgsql dump marker" "$?" 0
printf -- 'INSERT INTO x VALUES (1);\n' | db_dump_complete; eq "truncated dump rejected" "$?" 1
cat >"$T/pg.php" <<'PHP'
<?php
$CONFIG = array('dbtype' => 'pgsql', 'dbhost' => 'pg.local', 'dbname' => 'nc', 'dbuser' => 'u', 'dbpassword' => 'p');
PHP
db_connect_from_config "$T/pg.php"
eq "config.php pgsql type" "$DBTYPE" pgsql
eq "config.php pgsql default port" "$DBP" 5432
eq "config.php pgsql host" "$DBH" pg.local
sed -i "s/'pg.local'/'pg.local:6543'/" "$T/pg.php"; db_connect_from_config "$T/pg.php"
eq "config.php explicit port" "$DBP" 6543
NC_SECRET_VALUES=()


echo "-- ssl certificate checks"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$T/k.pem" -out "$T/c.pem" -days 90 -subj "/CN=test.local" >/dev/null 2>&1
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$T/k2.pem" -out "$T/c2.pem" -days 90 -subj "/CN=other.local" >/dev/null 2>&1
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$T/k3.pem" -out "$T/c3.pem" -days 5 -subj "/CN=soon.local" >/dev/null 2>&1
openssl req -x509 -newkey rsa:2048 -keyout "$T/kenc.pem" -passout pass:secret -out "$T/cenc.pem" -days 90 -subj "/CN=enc.local" >/dev/null 2>&1
ssl_check_pair "$T/c.pem" "$T/k.pem" >/dev/null;               eq "matching pair accepted" "$?" 0
ssl_check_pair "$T/c.pem" "$T/k2.pem" >/dev/null;              eq "mismatched key rejected" "$?" 1
ssl_check_pair "$T/nope.pem" "$T/k.pem" >/dev/null;            eq "missing certificate rejected" "$?" 1
ssl_check_pair "$T/c.pem" "$T/nope.pem" >/dev/null;            eq "missing key rejected" "$?" 1
echo "not a cert" >"$T/bad.pem"; ssl_check_pair "$T/bad.pem" "$T/k.pem" >/dev/null; eq "garbage certificate rejected" "$?" 1
ssl_check_pair "$T/cenc.pem" "$T/kenc.pem" >/dev/null;         eq "encrypted key rejected (no prompt)" "$?" 1
out="$(ssl_check_pair "$T/c3.pem" "$T/k3.pem")"; rcx=$?
eq "expiring-soon cert still accepted" "$rcx" 0
case "$out" in *"expires within 14 days"*) eq "expiry warning printed" ok ok ;; *) eq "expiry warning printed" bad ok ;; esac
# an already expired certificate (openssl cannot sign one with -days, so sign it through `openssl ca` with explicit dates)
mkdir -p "$T/ca"; : >"$T/ca/index.txt"; echo 01 >"$T/ca/serial"
cat >"$T/ca.cnf" <<EOF
[ca]
default_ca = CA_default
[CA_default]
dir = $T/ca
database = $T/ca/index.txt
serial = $T/ca/serial
new_certs_dir = $T/ca
default_md = sha256
policy = policy_any
email_in_dn = no
rand_serial = no
unique_subject = no
[policy_any]
commonName = supplied
EOF
openssl req -newkey rsa:2048 -nodes -keyout "$T/k4.pem" -out "$T/c4.csr" -subj "/CN=expired.local" >/dev/null 2>&1
openssl ca -config "$T/ca.cnf" -batch -selfsign -keyfile "$T/k4.pem" -in "$T/c4.csr" -out "$T/c4.pem" -notext \
    -startdate 20200101000000Z -enddate 20200201000000Z >/dev/null 2>&1
r=0; openssl x509 -in "$T/c4.pem" -noout -checkend 0 >/dev/null 2>&1 || r=1; eq "test fixture really is expired" "$r" 1
out="$(ssl_check_pair "$T/c4.pem" "$T/k4.pem")"; rcx=$?
eq "expired certificate rejected by default" "$rcx" 1
case "$out" in *"SSL ERROR: the certificate has expired"*) eq "expiry error printed" ok ok ;; *) eq "expiry error printed" bad ok ;; esac
out="$(ssl_check_pair "$T/c4.pem" "$T/k4.pem" true)"; rcx=$?
eq "expired certificate accepted with allow_expired" "$rcx" 0
case "$out" in *"SSL WARNING: the certificate expired on"*) eq "expiry downgraded to a warning" ok ok ;; *) eq "expiry downgraded to a warning" bad ok ;; esac
ssl_check_pair "$T/c.pem" "$T/k2.pem" true >/dev/null; eq "allow_expired does not excuse a mismatched key" "$?" 1
ssl_check_pair "$T/bad.pem" "$T/k.pem" true >/dev/null; eq "allow_expired does not excuse a broken certificate" "$?" 1
export NC_APACHE_UI_CONF="$T/ui.conf" NC_WEBROOT=/data/nextcloud/html
web_write_ui_conf false /x/c.pem /x/k.pem
eq "SAN: ip, port stripped" "$(ssl_san_string 192.168.1.73:8099)" "DNS:localhost,IP:127.0.0.1,IP:192.168.1.73"
eq "SAN: names and ips mixed" "$(ssl_san_string homeassistant.local:8099 192.168.1.73 cloud.example.com)" "DNS:localhost,IP:127.0.0.1,DNS:homeassistant.local,IP:192.168.1.73,DNS:cloud.example.com"
eq "SAN: duplicates removed" "$(ssl_san_string 192.168.1.73:8099 192.168.1.73 localhost 127.0.0.1)" "DNS:localhost,IP:127.0.0.1,IP:192.168.1.73"
eq "SAN: empty list still covers localhost" "$(ssl_san_string)" "DNS:localhost,IP:127.0.0.1"
SAN="$(ssl_san_string 192.168.1.73:8099 homeassistant.local:8099)"
ssl_selfsigned_ensure "$T/ss/cert.pem" "$T/ss/key.pem" "$SAN"; eq "self-signed generated" "$?" 0
ssl_check_pair "$T/ss/cert.pem" "$T/ss/key.pem" >/dev/null; eq "generated pair passes the same checks" "$?" 0
txt="$(openssl x509 -in "$T/ss/cert.pem" -noout -text)"
case "$txt" in *"IP Address:192.168.1.73"*) eq "cert covers the LAN IP" ok ok ;; *) eq "cert covers the LAN IP" bad ok ;; esac
case "$txt" in *"DNS:homeassistant.local"*) eq "cert covers the host name" ok ok ;; *) eq "cert covers the host name" bad ok ;; esac
case "$txt" in *"TLS Web Server Authentication"*) eq "cert is marked for server auth" ok ok ;; *) eq "cert is marked for server auth" bad ok ;; esac
r=0; [ "$(stat -c %a "$T/ss/key.pem")" = 600 ] || r=1; eq "private key mode 600" "$r" 0
before="$(sha256sum "$T/ss/cert.pem")"; ssl_selfsigned_ensure "$T/ss/cert.pem" "$T/ss/key.pem" "$SAN"
r=0; [ "$before" = "$(sha256sum "$T/ss/cert.pem")" ] || r=1; eq "unchanged addresses keep the same certificate" "$r" 0
ssl_selfsigned_ensure "$T/ss/cert.pem" "$T/ss/key.pem" "$(ssl_san_string 192.168.1.99)"
r=0; [ "$before" != "$(sha256sum "$T/ss/cert.pem")" ] || r=1; eq "changed addresses regenerate the certificate" "$r" 0
grep -q '^Listen 443$' "$T/ui.conf" && ! grep -q SSLEngine "$T/ui.conf"; eq "ssl off: plain listener on 443" "$?" 0
echo "-- architecture / runtime detection"
eq "x86_64" "$(NC_UNAME_M=x86_64 detect_arch)" x86_64
eq "amd64 alias" "$(NC_UNAME_M=amd64 detect_arch)" x86_64
eq "aarch64" "$(NC_UNAME_M=aarch64 detect_arch)" aarch64
eq "arm64 alias" "$(NC_UNAME_M=arm64 detect_arch)" aarch64
NC_UNAME_M=armv7l detect_arch >/dev/null; eq "armv7 rejected" "$?" 1
NC_UNAME_M=i686 detect_arch >/dev/null;   eq "i686 rejected" "$?" 1
eq "code app x86_64" "$(code_app_id x86_64)" richdocumentscode
eq "code app aarch64" "$(code_app_id aarch64)" richdocumentscode_arm64
code_app_id armv7l >/dev/null 2>&1; eq "no code app for armv7" "$?" 1
eq "libc override musl" "$(NC_LIBC_OVERRIDE=musl detect_libc)" musl
ver_ge 35.0.1 35.0.0; eq "ver_ge equal/greater" "$?" 0
ver_ge 34.0.9 35.0.0; eq "ver_ge lower" "$?" 1
ver_ge 35.0.10 35.0.9; eq "ver_ge numeric sort" "$?" 0
eq "url_host" "$(url_host https://cloud.example.com:8443)" cloud.example.com:8443
eq "url_scheme" "$(url_scheme https://x.y)" https

echo "-- CODE status classification (upstream proxy.php values)"
eq "OK" "$(classify_code_status '{"status":"OK"}')" ok
eq "no_glibc" "$(classify_code_status '{"status":"error","error":"no_glibc"}')" no_glibc
eq "no_fontconfig" "$(classify_code_status '{"status":"error","error":"no_fontconfig"}')" no_fontconfig
eq "not_x86_64" "$(classify_code_status '{"status":"error","error":"not_x86_64"}')" not_x86_64
eq "starting" "$(classify_code_status '{"status":"starting"}')" starting
eq "html is unparseable" "$(classify_code_status '<html>502</html>')" unparseable
eq "empty is unparseable" "$(classify_code_status '')" unparseable
case "$(code_error_hint no_glibc)" in *musl*) eq "no_glibc hint mentions musl" ok ok ;; *) eq "no_glibc hint mentions musl" bad ok ;; esac
eq "http 200 alone is not 'ok' for status" "$(classify_code_status '{"foo":1}')" unparseable

echo "-- network failure classification"
eq "curl 6" "$(classify_curl_exit 6)" dns
eq "curl 60" "$(classify_curl_exit 60)" tls
eq "curl 7" "$(classify_curl_exit 7)" refused
eq "curl 28" "$(classify_curl_exit 28)" timeout
printf 'HTTP/2 302\r\nlocation: https://team.cloudflareaccess.com/cdn-cgi/access/login\r\n' >"$T/h"; : >"$T/b"
eq "cloudflare access redirect" "$(classify_http 302 "$T/h" "$T/b")" cloudflare_access
printf 'HTTP/2 403\r\nserver: cloudflare\r\n' >"$T/h"
eq "cloudflare block" "$(classify_http 403 "$T/h" "$T/b")" cloudflare_block
printf 'HTTP/1.1 301\r\nlocation: https://x/\r\n' >"$T/h"
eq "redirect = proxy misconfig" "$(classify_http 301 "$T/h" "$T/b")" proxy_redirect
: >"$T/h"; eq "502 gateway" "$(classify_http 502 "$T/h" "$T/b")" bad_gateway
eq "occ tls" "$(classify_occ_error 'cURL error 60: SSL certificate problem')" tls
eq "occ dns" "$(classify_occ_error 'cURL error 6: Could not resolve host')" dns
eq "occ incompatible" "$(classify_occ_error 'App richdocuments is not compatible with this version')" incompatible_office
eq "occ wopi" "$(classify_occ_error 'WOPI host not allowed')" wopi
eq "mem critical" "$(mem_assessment 500000)" critical
eq "mem low" "$(mem_assessment 1500000)" low
eq "mem ok" "$(mem_assessment 6000000)" ok

echo "-- secret redaction"
NC_SECRET_VALUES=("S3cr3t-Value" "a/b&c")
eq "redact plain" "$(echo 'pw=S3cr3t-Value ok' | redact)" "pw=*** ok"
eq "redact special chars" "$(echo 'x a/b&c y' | redact)" "x *** y"
eq "log redacts" "$(NC_LOG_LEVEL=info log info 'token S3cr3t-Value' | sed 's/^\[[^]]*\] *//')" "info    token ***"
eq "log level filter" "$(NC_LOG_LEVEL=error log info hidden)" ""
export NC_SECRET_VALUES
NC_SECRET_VALUES=()

echo "-- config.php rewrite (migration)"
cat >"$T/src.php" <<'PHP'
<?php
$CONFIG = array(
  'instanceid' => 'oc123', 'passwordsalt' => 'SALT', 'secret' => 'SECRET', 'version' => '35.0.1.2', 'installed' => true,
  'datadirectory' => '/data', 'dbtype' => 'mysql', 'dbhost' => 'old-db', 'dbname' => 'old', 'dbuser' => 'o', 'dbpassword' => 'op',
  'apps_paths' => array(array('path' => '/config/www/nextcloud/apps')), 'trusted_proxies' => array('1.2.3.4'),
  'memcache.local' => '\OC\Memcache\Redis', 'redis' => array('host' => 'r'), 'overwrite.cli.url' => 'https://old',
  'default_phone_region' => 'GB', 'maintenance' => true,
);
PHP
echo '{"datadirectory":"/data/nextcloud-data","dbtype":"mysql","dbhost":"new-db:3306","dbname":"nextcloud","dbuser":"n","dbpassword":"np","trusted_domains":["x.example"]}' >"$T/ov.json"
dropped="$(php "$LIB/rewrite-config.php" "$T/src.php" "$T/out.php" "$T/ov.json")"
res="$(php -r 'include $argv[1]; echo json_encode($CONFIG);' "$T/out.php")"
eq "keeps instanceid" "$(jq -r .instanceid <<<"$res")" oc123
eq "keeps passwordsalt" "$(jq -r .passwordsalt <<<"$res")" SALT
eq "keeps secret" "$(jq -r .secret <<<"$res")" SECRET
eq "keeps region" "$(jq -r .default_phone_region <<<"$res")" GB
eq "new datadirectory" "$(jq -r .datadirectory <<<"$res")" /data/nextcloud-data
eq "new db host" "$(jq -r .dbhost <<<"$res")" "new-db:3306"
eq "drops apps_paths" "$(jq -r 'has("apps_paths")' <<<"$res")" false
eq "drops redis" "$(jq -r 'has("redis")' <<<"$res")" false
eq "drops non-APCu memcache" "$(jq -r 'has("memcache.local")' <<<"$res")" false
eq "maintenance cleared" "$(jq -r .maintenance <<<"$res")" false
case "$dropped" in *apps_paths*) eq "reports dropped keys" ok ok ;; *) eq "reports dropped keys" bad ok ;; esac

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" = 0 ]
