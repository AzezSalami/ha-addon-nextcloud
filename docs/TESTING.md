# Testing and evidence

## Test layers

| Layer | Command | Needs |
|---|---|---|
| Unit (config validation, arch/libc detection, CODE-status & failure classification, secret redaction, migration config rewrite) | `docker run --rm -v "$PWD/nextcloud":/src --entrypoint bash <image> /src/tests/unit/run.sh` | Docker (or Linux with bash, jq, php-cli) |
| Integration (real MariaDB + real Nextcloud 35 + real built-in CODE) | `bash nextcloud/tests/integration/run.sh <image>` | Docker, internet (app store), ~3 GB RAM, ~10 min |
| Static | ShellCheck, hadolint, `frenck/action-addon-linter` | in CI (`.github/workflows/ci.yml`) |
| Real Home Assistant | manual checklist below | HAOS/Supervisor |

The integration run covers: first install, `status.php` JSON, glibc, CODE `status == OK`, capabilities (JSON), discovery (WOPI XML),
healthcheck, `nc-diag`, no secrets in logs/diag, graceful stop & exit code 0, restart recovery, persistence of users and files, backup →
verify → restore round trip, refusal to install over an existing DB, downgrade refusal.

Tests print no passwords: credentials are random per run and the test asserts that they never appear in container logs.

## Results actually obtained (author's machine: Windows 11, Docker Desktop, linux/amd64)

See the section at the bottom of this file, filled in from the real run output.

## Not covered by automated tests (need a real system)

* Supervisor behaviour: service discovery of the MariaDB add-on (`db_mode: supervisor`), watchdog, add-on start/stop from the UI,
  `addon_config`/`share`/`backup` mounts, HA backup/restore.
* Cloudflare Tunnel end-to-end (public hostname, DNS, Access policies).
* arm64 execution (runs in CI on `ubuntu-24.04-arm` once the repository is pushed).
* WOPI editing session in a browser and WebSocket/long-poll behaviour through the tunnel.
* `nc-migrate` against real AlexBelgium/LinuxServer data.
* Rollback of a failed migration (procedure is "stop new, start old", nothing in the old install is modified).

## Manual acceptance checklist (real system)

1. `nc-diag` shows no findings; `proxy.php?status : ok`.
2. Upload a DOCX, open it in the browser, type, close; re-open: change is present.
3. Restart the add-on; the document is intact; `nc-diag` still clean.
4. `nc-backup create`, verify; restore on a scratch instance.
5. Access the public hostname through the tunnel; `https status.php : HTTP 200 (ok)`.

## Recorded results (2026-10-15, Windows 11 + Docker Desktop, linux/amd64, image `ncaddon:test` built from this repository)

Unit suite: **94 passed, 0 failed.**

Integration suite (`tests/integration/run.sh`, Nextcloud 35.0.1 and again on 35.0.2, Nextcloud Office + built-in CODE installed from the app store): **23 passed, 0 failed with MariaDB 11, and 23 passed, 0 failed with PostgreSQL 17** (`NC_TEST_DB=postgresql`).

| Check | Result |
|---|---|
| First install; `status.php` healthy JSON; glibc | pass |
| CODE `proxy.php?status` returns `{"status":"OK"}` (not `no_glibc`) | pass |
| `/hosting/capabilities` valid JSON; `/hosting/discovery` WOPI XML | pass |
| Container healthcheck; `nc-diag` reports CODE ok; no secrets in diag or logs | pass |
| Graceful stop (3 s) and exit code 0 on SIGTERM | pass |
| Restart recovery; users and files survive restart; config on persistent `/data` | pass |
| Backup create + verify; restore brings back a deleted file; healthy after restore | pass |
| Refuses to install over an existing database; refuses to start on newer data (downgrade) | pass |

Bugs found and fixed by these runs: `/var/www/html` is a Docker VOLUME (webroot moved to `/data/nextcloud/html`); store-installed CODE is served under
`/custom_apps/`, not `/apps/`; the base image's `STOPSIGNAL SIGWINCH` made `docker stop` wait for SIGKILL; Apache signals its process group on stop
(Apache is now started with `setsid`).

Still **not** verified: arm64, a real Home Assistant Supervisor, Cloudflare Tunnel, a browser DOCX edit/save session, and `nc-migrate import` against real
LinuxServer data.

PostgreSQL note: Nextcloud's installer creates its own `oc_admin` role, which owns the tables but not the `public` schema, so `nc-backup restore` resets
the database by dropping only the tables and sequences owned by the connecting role (dropping the schema failed in testing).

### Upgrade test (2026-10-16): 35.0.1 → 35.0.2 on existing data

`tests/integration/upgrade.sh <old-image> <new-image>` installs with the old add-on image, then starts the new image on the same volumes.
Result: **10 passed, 0 failed** – the upgrade was detected, a verified `pre-upgrade-35.0.1` backup was created automatically, Nextcloud reported
35.0.2 with no pending upgrade or maintenance mode, and the user and a test file were preserved. Run on MariaDB only (the logic is engine-independent).
The full suite above was re-run on the 35.0.2 image for both MariaDB and PostgreSQL with 0 failures.

### Web interface test (2026-10-16): `tests/integration/ssl.sh`

15 checks, 0 failed (MariaDB, self-signed certificate): plain HTTP on container port 443 with `ssl: false`; HTTPS with a verifying certificate and no plain HTTP on that
port with `ssl: true`; port 80 stays plain HTTP; a LAN visitor keeps its own address (`http(s)://192.168.1.50:8099/...`) instead of being redirected to `public_url`;
a visitor arriving from a trusted proxy with `X-Forwarded-Proto: https` gets `https://<public_url>`; `force_public_url: true` pins links to `public_url`; a key that does not
match the certificate, or a missing certificate file, stops the add-on with a clear message. The full MariaDB suite was re-run afterwards: 23/23. Unit tests: 108/108.

### Nextcloud Office configuration (2026-10-16)

Found from a real log: `nc-diag` reported `activate-config FAILED (wopi)` because Nextcloud Office had no server address (it only auto-configures when an admin opens Files in a browser,
from that admin's address, and then disables TLS verification). The add-on now sets `wopi_url` from `public_url`. `tests/integration/run.sh` gained 4 checks (activate-config OK,
`wopi_url` set, certificate verification left on, no FUSE/fontconfig noise in the log): 27 passed, 0 failed on MariaDB.

### Self-signed HTTPS for local IP access (2026-10-16)

`ssl: true` with empty `certfile`/`keyfile`: `tests/integration/ssl.sh` now has 22 checks, 0 failed. The generated certificate verifies for the LAN IP and host name listed in
`trusted_domains` (checked with `openssl s_client -verify_ip` / `-verify_hostname`; a different IP is rejected), the key is stored with mode 600, the certificate is kept across
restarts and regenerated when `trusted_domains` changes. Unit tests: 122/122, ShellCheck clean. Not verified: how each browser presents the self-signed warning.

### Expired certificate (2026-10-19): `ssl_allow_expired`

`tests/integration/ssl.sh`: 27 checks, 0 failed. A certificate that really expired (created with `-not_before/-not_after`) is refused by default with a message naming the option; with
`ssl_allow_expired: true` the add-on starts, serves HTTPS, logs a loud warning each start, and clients still see `certificate has expired`. Unit tests: 130/130 in the image. The expiry unit
tests need OpenSSL 3.4+ to back-date a certificate, so they are skipped on older hosts (Ubuntu 24.04 runs 123 checks and skips these; CI also runs the full set inside the image).

### Office file types (2026-10-19)

On a clean install Nextcloud reports 41 Office mimetypes via the OCS capabilities endpoint, including docx, xlsx, pptx and the OpenDocument formats (Markdown is handled by the Text app, not Office).
`tests/integration/run.sh` now asserts six of these types and that the add-on refreshed Office's file-type cache at start: 34 checks, 0 failed on MariaDB. Found while testing: `richdocuments:activate-config`
resets the callback URL (`internal_url`); the add-on and `nc-diag` now restore it. Not reproduced: a stale-empty cache on a real instance; that part of the fix is untested against the reported symptom.

### Office with an empty public_url (2026-10-19): `tests/integration/office.sh`

Reproduced "Nextcloud Office (Collabora) is not configured" (empty `public_url` left `wopi_url` empty). With the fix, 11 checks, 0 failed: `wopi_url` is derived from the first trusted domain, a **non-admin** user
receives a configured Office with docx/xlsx/pptx, `nc-diag` reports `activate-config OK`; with `ssl` + the self-signed certificate the certificate is imported into Nextcloud's trust store, `wopi_url` is https,
TLS verification for Office stays on and `activate-config` succeeds. A loopback design (server address 127.0.0.1 plus a separate browser address) was tried and rejected: `activate-config` overwrites the public
address with the discovered one. Not verified: reaching the host's LAN IP and published port from inside the add-on container on a real Home Assistant (the usual Docker behaviour, but untested here).

### "Starting the built-in CODE server is taking longer than expected" (2026-10-19)

Reproduced with a real browser (the app's Browser pane against a local test instance): Nextcloud on `localhost:8099` while Office is bound to `127.0.0.1:8099` fails with the CSP error `connect-src 'self'` on `…/proxy.php?status`.
With matching addresses the same `.ods` file opens, the Collabora spreadsheet UI renders and the `/cool/ws` long-polling requests return 200, i.e. editing works end to end in the add-on. A server-side conversion of a real `.ods`
to PDF through the built-in server takes about a second warm. Ideas tried and dropped: CORS headers (the block is CSP, not CORS); a `proxy.php`-free alias for the server address; a loopback server address (`activate-config` overwrites the public address with what it discovers).
`tests/integration/office.sh` now also checks the bound-address log line, the `nc-diag` address and warning, and the `force_public_url` redirect when `public_url` is empty. Unit tests: 136/136.

Bug found by the extended Office test (2026-10-19): after a run with `ssl: true`, switching `ssl` back to `false` stopped Apache from starting (duplicate `Listen 443`). Fixed (mod_ssl is disabled when ssl is off) and covered by a new check in `tests/integration/ssl.sh` (29 checks, 0 failed). `office.sh`: 18 checks, 0 failed. Unit tests: 136/136.
