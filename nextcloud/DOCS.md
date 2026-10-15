# Nextcloud (official image + built-in CODE) – documentation

## Install

1. Home Assistant → Settings → Add-ons → Add-on store → ⋮ → Repositories → add this repository's URL.
2. Install the **MariaDB** add-on (core) and start it (or prepare an external MariaDB 10.6+/11 and use `db_mode: external`).
3. Install **Nextcloud (official image + built-in CODE)**. Building locally from the Dockerfile takes a few minutes.
4. Configure (below), start, watch the log. First start installs Nextcloud and then Nextcloud Office + built-in CODE.
5. Run `nc-diag` (see Diagnostics). Tunnel setup: [../docs/CLOUDFLARE.md](../docs/CLOUDFLARE.md).

Existing install? Do **not** start with admin credentials; follow [../docs/MIGRATION.md](../docs/MIGRATION.md).

## Options

| Option | Default | Meaning |
|---|---|---|
| `public_url` | empty | `https://cloud.example.com` (no path). Drives trusted domain, `overwritehost`, `overwriteprotocol`, `overwrite.cli.url`. |
| `internal_url` | empty | Optional callback URL for CODE → Nextcloud (`richdocuments wopi_callback_url`). Leave empty unless diagnostics demand it. |
| `trusted_domains` | `[]` | Additional hostnames (`public_url` host is automatic; `localhost` if both empty). Managed by the add-on: manual entries are replaced at start. |
| `trusted_proxies` | `172.30.32.0/23` | IPs/CIDRs allowed to set `X-Forwarded-*`. Never `0.0.0.0/0`. |
| `db_mode` | `supervisor` | `supervisor` = MariaDB add-on via Supervisor service discovery (database is created if missing). `external` = `db_host/db_port/db_user/db_password`. |
| `db_name` | `nextcloud` | Must be empty/non-existent for a new install. The add-on refuses to install over a database that already has `oc_*` tables. |
| `admin_user`, `admin_password` | empty | Required **only** for the very first install (≥10 chars). Ignored afterwards; clear them after install. |
| `data_path` | `/data/nextcloud-data` | Must be below `/data`, `/share` or `/media`. Refused if non-empty on a fresh install. |
| `background_jobs` | `cron` | `cron` = built-in loop runs `cron.php` every 5 minutes; also `ajax`, `webcron`. |
| `php_memory_limit`, `upload_limit` | `1024M`, `16G` | PHP limits (official image variables). |
| `default_phone_region` | empty | ISO country code. |
| `enable_office` | `true` | Install/enable Nextcloud Office and the architecture-matched CODE app. |
| `code_diagnostics` | `true` | Run `nc-diag` after start (logged, read-only). |
| `code_start_timeout` | `240` | Seconds diagnostics wait for CODE. |
| `backup_on_start` | `false` | Verified backup on every start (always done before an upgrade). |
| `migration_mode` | `false` | Park the container without Apache so `nc-migrate` can run. |
| `log_level` | `info` | `debug/info/warning/error`. |

Persistent locations: `/data/nextcloud/html` (code, `config/`, `custom_apps/`, `themes/` – symlinked to `/var/www/html`),
`data_path` (user data), MariaDB (own add-on), `/backup/nextcloud_official` (backups).

## Permissions and security notes

* No `privileged`, no extra capabilities, no `host_network`, no devices, no full filesystem. Mapped folders: `addon_config` (rw, reserved),
  `share` (rw, for `data_path` on large disks and migration staging), `backup` (rw, for `nc-backup`).
* The container's main process runs as root (the official entrypoint requires it to adjust ownership); Apache workers and `occ`/cron run as `www-data`.
* `options.json` (Supervisor-managed) stores `admin_password`/`db_password` in plain text inside `/data`; Supervisor schema type `password`
  hides them in the UI. Secrets are redacted from this add-on's logs (verified by an integration test with random values).
  Supervisor-provided MariaDB credentials are never written to disk by the add-on (`db_mode: supervisor`), but Nextcloud itself
  stores `dbpassword` in `config.php` (unavoidable).
* Ingress is **not** used: Nextcloud needs its own hostname/cookies/WebDAV/clients, which is incompatible with Supervisor ingress path rewriting.
* Built-in CODE runs inside this container in the AppImage's reduced-privilege mode (no mount jails). Documents are processed in the same container
  as Nextcloud: that is the main security trade-off compared with a standalone Collabora container.
* TLS verification, WOPI allow-lists and Cloudflare Access are never relaxed by this add-on.

## Diagnostics

```bash
docker exec addon_<slug> nc-diag            # human readable report
docker exec addon_<slug> nc-diag --json     # machine readable
docker exec addon_<slug> nc-diag --wait 600 # wait for CODE
```
Classifies: missing glibc (`missing_glibc`/`no_glibc`), missing fontconfig, unsupported architecture, CODE startup timeout, DNS/TLS failures of
the public URL, Cloudflare Access/WAF, reverse-proxy misconfiguration, WOPI validation, WebSocket probe, low memory, incompatible Office app.
Only a JSON `{"status":"OK"}` from `proxy.php?status` counts as healthy – never just HTTP 200. The container `HEALTHCHECK` uses the same rule.

## Troubleshooting

| Log / symptom | Cause | Fix |
|---|---|---|
| `Configuration invalid` | semantic option check failed | message names the option |
| `Refusing to install over it` | DB has `oc_*` tables but no config | choose a new `db_name` or migrate |
| `newer than the image` | downgrade attempted | install matching add-on version or restore backup |
| `CODE status: starting` for minutes | low RAM / first extraction of the AppImage | check `nc-diag`, free memory, `--wait 600` |
| `no_glibc` | musl image | impossible with this image; you replaced the base image |
| `Access through untrusted domain` | host not in list | `public_url` / `trusted_domains` |
| Redirect loop on public URL | scheme mismatch | `public_url` https, tunnel service `http://...:80`, `trusted_proxies` |
| `incompatible_office` | no store release for this NC | wait for release, or [ALTERNATIVE-COLLABORA.md](../docs/ALTERNATIVE-COLLABORA.md) |
