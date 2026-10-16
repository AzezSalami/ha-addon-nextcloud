# Nextcloud for Home Assistant (official image + built-in Office)

A Home Assistant add-on that runs **Nextcloud** on the official Nextcloud Docker image, with **Nextcloud Office**
(Collabora) built in, so you can open and edit Word, Excel and PowerPoint files in your browser without running a separate
document server.

[![CI](https://github.com/AzezSalami/ha-addon-nextcloud/actions/workflows/ci.yml/badge.svg)](https://github.com/AzezSalami/ha-addon-nextcloud/actions/workflows/ci.yml)

## Features

* **Official Nextcloud image** (Debian-based), pinned to a specific release, rather than a community rebuild.
* **Built-in Nextcloud Office** installed and enabled automatically for your CPU type (x86-64 or ARM64).
* **Your choice of database**: the Home Assistant MariaDB add-on (default, auto-discovered), an external MariaDB/MySQL, or **PostgreSQL**. Your database is never on throwaway storage.
* **Safe by default**: refuses to install over an existing database or data folder, refuses to start on data from a newer
  Nextcloud version (no accidental downgrade), and takes a verified backup before every upgrade.
* **Backups and restore** from the command line, with integrity checks.
* **Health and diagnostics**: a built-in report that tells you *why* Office isn't working (missing libraries, DNS, TLS, proxy or
  Cloudflare problems, low memory, and more).
* **Works behind a reverse proxy or Cloudflare Tunnel** without opening ports on your router.
* **Migration helper** for moving an existing Nextcloud over without touching the old install.
* No privileged mode, no extra capabilities, no host networking.

## Requirements

* Home Assistant OS or Supervised (anything that supports add-on repositories).
* A 64-bit CPU: **amd64** or **aarch64** (Raspberry Pi 4/5, most mini PCs). 32-bit ARM and 32-bit x86 are not supported by the
  built-in Office.
* The **MariaDB** add-on (or an external MariaDB 10.6+ / MySQL 8, or PostgreSQL; tested with 17).
* About **2 GiB of free RAM** for comfortable use of Office, plus storage for your files.

## Installation

1. In Home Assistant go to **Settings → Add-ons → Add-on Store → ⋮ → Repositories** and add:
   ```
   https://github.com/AzezSalami/ha-addon-nextcloud
   ```
2. Install and start the **MariaDB** add-on if you don't already have it.
3. Install **Nextcloud**. The first install builds the image on your device and takes a few minutes.
4. Open the add-on's **Configuration** tab and set at least:
   * `public_url`: the address you will use, e.g. `https://cloud.example.com`
   * `admin_user` and `admin_password`: needed only for the very first start (minimum 10 characters)
5. Start the add-on and watch the **Log** tab. The first start installs Nextcloud, then Nextcloud Office.
6. Make it reachable: through a [Cloudflare Tunnel](docs/CLOUDFLARE.md) (target the add-on's plain HTTP port), or locally with the **Open Web UI** button (host port `8099`, HTTPS if you turn on `ssl` and point `certfile`/`keyfile` at certificates in Home Assistant's `/ssl` folder). Add the address you use, with its port, to `trusted_domains` (for example `192.168.1.50:8099`).
7. Check everything with the diagnostics report:
   ```bash
   docker exec addon_<repository-hash>_nextcloud_official nc-diag
   ```
   (Use the *Advanced SSH & Web Terminal* add-on with protection mode off, or the host console. Find the exact container name with `docker ps`.)

After the first start, clear `admin_password` from the configuration.

## Already running Nextcloud?

Don't start this add-on with admin credentials on top of an existing setup. Follow the [migration guide](docs/MIGRATION.md): it
copies your data and database into the new add-on and leaves the old one untouched, so you can switch back at any time
([rollback guide](docs/ROLLBACK.md)).

## Configuration at a glance

| Option | What it does |
|---|---|
| `public_url` | Your public address. Sets trusted domains and HTTPS handling. |
| `trusted_domains` | Extra hostnames (for example a local name). |
| `trusted_proxies` | Addresses of your reverse proxy / tunnel that may set forwarded headers. |
| `ssl`, `certfile`, `keyfile` | HTTPS for the web interface using certificates from Home Assistant's `/ssl` folder. |
| `force_public_url` | Pin all links to `public_url` (off by default, so local access by IP stays local). |
| `db_type`, `db_mode`, `db_*` | MariaDB add-on (default), or an external MariaDB/PostgreSQL server (see [PostgreSQL setup](nextcloud/DOCS.md#using-postgresql)). |
| `data_path` | Where user files are stored. Use `/share/...` for a large disk. |
| `enable_office` | Install and enable Nextcloud Office with the built-in server. |
| `backup_on_start` | Take a verified backup every time the add-on starts. |

Every option is explained in the [full documentation](nextcloud/DOCS.md).

## Useful commands

Run these inside the add-on container (`docker exec addon_<name> <command>`):

| Command | Purpose |
|---|---|
| `nc-diag` | Readable health report with actionable fixes (`--json` for scripts). |
| `nc-backup create` / `verify` / `list` / `restore` | Backups, see [backup guide](docs/BACKUP-RESTORE.md). |
| `nc-migrate preflight` / `import` | Move an existing install, see [migration guide](docs/MIGRATION.md). |

## Documentation

[Full add-on documentation](nextcloud/DOCS.md) · [Cloudflare Tunnel setup](docs/CLOUDFLARE.md) · [Migration](docs/MIGRATION.md) ·
[Backup and restore](docs/BACKUP-RESTORE.md) · [Rollback](docs/ROLLBACK.md) · [Updating](docs/UPDATING.md) ·
[Compatibility](docs/COMPATIBILITY.md) · [Testing](docs/TESTING.md) · [Using a separate Collabora server instead](docs/ALTERNATIVE-COLLABORA.md)

## Why not the LinuxServer-based add-ons?

The built-in Office server is a prebuilt program that needs the standard Linux C library (glibc). Add-ons based on Alpine Linux
(such as images from LinuxServer.io) use a different library (musl), so Nextcloud Office reports
`{"status":"error","error":"no_glibc"}` and documents never open. This add-on uses the official Debian-based image, which has glibc.

## Status and known limitations

Tested so far: unit tests and a full integration suite (install, Office server start, discovery and capabilities, graceful stop,
restart, backup and restore, safety checks) on **amd64** in Docker. Details in [TESTING.md](docs/TESTING.md).

Not yet verified by the maintainer, so treat as **beta**:

* Running under a real Home Assistant Supervisor, and through a real Cloudflare Tunnel.
* **aarch64**: built and tested in CI, but whether an Office server release exists for your Nextcloud version isn't guaranteed.
* Editing and saving a document in the browser (manual check).
* The migration tool on real data from other Nextcloud add-ons. **Take a backup and test with a copy first.**

Other limitations:

* Migration (`nc-migrate`) supports MariaDB/MySQL sources only. PostgreSQL is supported for new installs, backups and restores.
* The built-in Office server runs inside the Nextcloud container and talks to the browser over HTTP polling rather than
  WebSockets. A separate Collabora server is more scalable and isolated ([alternative](docs/ALTERNATIVE-COLLABORA.md)).
* Settings such as admin and database passwords are stored by Home Assistant in plain text in the add-on's options, like any add-on.
* Docker Official Images don't ship signatures; pin an image digest if you need strict provenance ([updating](docs/UPDATING.md)).

## Contributing and support

Issues and pull requests are welcome. Please include the output of `nc-diag` (it never prints passwords) and the add-on log
(passwords are redacted) when reporting a problem. CI runs ShellCheck, the Home Assistant add-on linter, hadolint, unit tests and the
integration suite on amd64 and arm64.

## License

[MIT](LICENSE). Nextcloud and Collabora are separate projects with their own licenses; this repository only packages them.
