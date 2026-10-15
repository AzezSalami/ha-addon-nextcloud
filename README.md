# Home Assistant add-on: Nextcloud on the official image, with built-in CODE

Replaces a LinuxServer.io-based Nextcloud add-on whose Nextcloud Office fails with
`{"status":"error","error":"no_glibc"}`.

## Why `no_glibc` happened

`proxy.php` of the built-in CODE app (`CollaboraOnline/richdocumentscode`) runs `LD_TRACE_LOADED_OBJECTS=1 collabora/Collabora_Online.AppImage`;
if that exits non-zero it answers `no_glibc`. The AppImage is a glibc binary (its README: "does not support musl libc"), and the
LinuxServer Nextcloud image is Alpine/musl, so the loader cannot run it. Cloudflare Tunnel is not involved. (The upstream source
was read at the time of writing; re-verify against current `proxy.php` when upgrading.)

## What this repository does differently

* Base: **`nextcloud:35.0.1-apache`** (official Docker image, Debian trixie, glibc 2.41, PHP 8.5, amd64 + arm64). Adds `fontconfig`
  (required by `proxy.php`), MariaDB client, `jq`, `rsync`. The build fails if the base is musl.
* The add-on scripts (`nc-run`) validate options, check arch/libc, connect to MariaDB (Supervisor service or external), refuse to
  install over existing databases/data, take a verified backup before upgrades, start the **unmodified upstream entrypoint** and Apache,
  run background jobs, install/enable Nextcloud Office + the architecture-matched CODE app, and handle SIGTERM gracefully.
  (Only paths are substituted: `/var/www/html` → `/data/nextcloud/html`, because that upstream path is a Docker `VOLUME`.)
* `nc-diag`, `nc-backup`, `nc-migrate` – see [nextcloud/DOCS.md](nextcloud/DOCS.md).

## Install

Add this repository to the Home Assistant add-on store (Settings → Add-ons → ⋮ → Repositories → `https://github.com/AzezSalami/ha-addon-nextcloud`), install **MariaDB** and
**Nextcloud (official image + built-in CODE)**.

Docs: [DOCS](nextcloud/DOCS.md) · [Cloudflare](docs/CLOUDFLARE.md) · [Migration](docs/MIGRATION.md) · [Rollback](docs/ROLLBACK.md) ·
[Backup/restore](docs/BACKUP-RESTORE.md) · [Compatibility](docs/COMPATIBILITY.md) · [Updating](docs/UPDATING.md) ·
[Testing & evidence](docs/TESTING.md) · [Collabora alternative](docs/ALTERNATIVE-COLLABORA.md)

## Known limitations

* Not tested on a real Home Assistant OS/Supervisor, nor through a real Cloudflare Tunnel, by the author (see TESTING.md).
* `aarch64` is declared and built in CI, but the `richdocumentscode_arm64` app's availability for Nextcloud 35 was not verified.
* `nc-migrate` supports MySQL/MariaDB sources only; it was not run against real LinuxServer data.
* Built-in CODE uses HTTP long-polling through a PHP proxy (no WebSockets) and runs in the Nextcloud container (reduced isolation).
* Needs ~2 GiB free RAM for comfortable use; 6 GiB is fine.
* DOCX open/edit/save in a browser is a manual acceptance test (checklist in TESTING.md).
* Image signatures: Docker Official Images publish no cosign signatures; pin digests instead.
* Secrets are stored in Supervisor's `options.json` (plain text, `/data`) like any add-on option.
