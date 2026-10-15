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
