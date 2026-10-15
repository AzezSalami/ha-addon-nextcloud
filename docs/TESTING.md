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

Unit suite: **76 passed, 0 failed.**

Integration suite (`tests/integration/run.sh`, real MariaDB 11, Nextcloud 35.0.1, Nextcloud Office + built-in CODE installed from the app store): **23 passed, 0 failed.**

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
