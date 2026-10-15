# Migrating from AlexBelgium's (LinuxServer-based) Nextcloud add-on

**Principle:** the old add-on, its database and its files are only ever *read*. Everything is copied into
the new add-on, so rollback is "stop new, start old" (see [ROLLBACK.md](ROLLBACK.md)).

> `nc-migrate` has been unit-tested (config rewriting) and the new add-on's backup/restore round-trip is
> integration-tested. The full import path against a real LinuxServer data set has **not** been run by the
> author: do it first with a copy, follow every check, and keep the old add-on stopped but installed.

## 0. Discover what you have (nothing is changed)

Use the *Terminal & SSH* add-on (disable "Protection mode" only if you need `docker exec`; the host paths below are
visible without it).

| Item | Where to look |
|---|---|
| Old add-on slug | Settings → Add-ons → Nextcloud → URL, e.g. `db21ed7f_nextcloud` |
| Old `config.php` | `/addon_configs/<slug>/…/www/nextcloud/config/config.php` (search: `find /addon_configs -name config.php -path '*nextcloud*'`) |
| Old data directory | `datadirectory` in that `config.php` (AlexBelgium default is configurable, often `/share/nextcloud` or inside the add-on config) |
| Database | `dbtype`, `dbhost`, `dbname` in `config.php`. Must be MySQL/MariaDB. |
| Version | `version` in `config.php` (yours: 35.0.1) |

SQLite or PostgreSQL? Convert in the **old** install first (`occ db:convert-type --all-apps mysql …`) *or* ask for
a PostgreSQL variant of this tool (limitation, see README).

## 1. Install the new add-on (empty) in migration mode

1. Install the MariaDB add-on (or have an external MariaDB) and the new add-on. The importer needs a MariaDB target; if you want PostgreSQL, migrate into MariaDB first and convert afterwards with `occ db:convert-type`.
2. In the new add-on options set `db_mode`, `db_name` (**a new, empty database name**; never the old one),
   `data_path` (new, empty), `public_url`, and **`migration_mode: true`**. Leave `admin_*` empty.
3. Start it. The log says *MIGRATION MODE: Apache is NOT started*. No tables are created.

## 2. Make the old config and data visible to the new add-on

The new add-on maps only `/data`, `/share`, `/backup`, `/addon_config`. Copy (do not move) from the SSH add-on:

```bash
mkdir -p /share/nc-migration
cp /addon_configs/<old-slug>/.../config.php /share/nc-migration/config.php
# if the old data directory is NOT already under /share:
rsync -a --info=progress2 <old-data-dir>/ /share/nc-migration/data/
```

If the old data directory is already under `/share`, pass it as it is. Do not edit anything in it.

## 3. Take a consistent copy – stop the OLD add-on first

In Home Assistant stop the old Nextcloud add-on (keep MariaDB running). Then, from the host SSH:

```bash
docker exec addon_<new-slug> nc-migrate preflight   --source-config /share/nc-migration/config.php --source-data /share/nc-migration/data
docker exec addon_<new-slug> nc-migrate dump-source --source-config /share/nc-migration/config.php --out /share/nc-migration/old-db.sql.gz
```

(`<new-slug>` is `nextcloud_official` prefixed with the repository hash, check `docker ps`.)

`preflight` checks: source version vs. image (equal or at most one major behind; never newer), DB engine, DB
reachable, encryption status, apps without code in the image, data readable, free space, target DB empty, target
not installed, `data_path` empty. It must print `PREFLIGHT PASSED`. `dump-source` verifies the dump
(gzip integrity, completion marker, SHA-256 file).

**Also take a Home Assistant full backup now** (includes the old add-on) – independent safety net.

## 4. Import

```bash
docker exec addon_<new-slug> nc-migrate import \
  --source-config /share/nc-migration/config.php \
  --source-data   /share/nc-migration/data \
  --source-sql    /share/nc-migration/old-db.sql.gz
```

What happens: preflight again → data `rsync` copy → dump imported into the **new** database → Nextcloud code is
installed → a new `config.php` is written from the old one (keeps `instanceid`, `passwordsalt`, `secret`, so
encryption, app passwords, 2FA, tokens keep working; drops container-specific keys such as `apps_paths`, redis,
`trusted_proxies`, `overwrite*`, log paths and lists them) → `occ upgrade` **only if** the image is newer
(runs against the new DB) → missing apps are installed from the app store if a compatible release exists →
`maintenance:data-fingerprint`.

Preserved: users, files, folder structure, metadata (file cache), shares, calendars/contacts (they live in the DB), versions,
trash bin and encryption keys (both in the data directory), app settings. Previews are in the data directory too and
are copied; they regenerate if missing. Apps that have no compatible release stay disabled and are listed.

## 5. Switch over

1. Set `migration_mode: false` and `admin_*` empty (installed already), restart the new add-on.
2. The add-on starts Apache, sets trusted domains, background jobs, Office + built-in CODE.
3. Point the Cloudflare Tunnel service at the new add-on ([CLOUDFLARE.md](../docs/CLOUDFLARE.md)).
4. Run `docker exec addon_<new-slug> nc-diag` – everything should be OK.
5. Log in, open a DOCX, edit, save. Check shares, calendar, contacts.
6. Keep the old add-on **installed and stopped** for at least a few weeks. Never run both against the same DB/data.

## What can go wrong

| Symptom | Meaning / fix |
|---|---|
| Preflight: source newer than image | You'd need a newer image tag; the tool refuses downgrades. |
| `occ upgrade` fails | Old install untouched. Drop the new DB, start over after reading the error. |
| Apps disabled after import | No compatible release for this NC version; update/replace them. |
| "Access through untrusted domain" | Add the hostname to `trusted_domains` / `public_url`, restart. |
| Files missing | You copied the wrong data dir; compare `datadirectory` with the copied one and run `occ files:scan --all`. |
