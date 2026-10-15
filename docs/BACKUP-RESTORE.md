# Backup and restore

All commands run inside the add-on container: `docker exec addon_<slug> <command>` (or the add-on's Terminal if enabled).

```bash
nc-backup create --label manual        # maintenance mode on -> DB dump + config + data snapshot -> verify -> off
nc-backup list
nc-backup verify /backup/nextcloud_official/<dir> [--data-against-live]
nc-backup restore /backup/nextcloud_official/<dir> --yes-restore
```

Layout of one backup directory: `db.sql.gz`, `config.tar.gz` (config, custom_apps, themes), `apps.json`,
`data/` (rsync snapshot; unchanged files are hard-linked to the previous backup, so each extra backup costs only the delta),
`SHA256SUMS`, `manifest.json`, and a `.verified` marker written only after verification.

Verification at creation: SHA-256 of the artifacts, gzip integrity, the dump's completion marker, tar integrity, presence
of `config.php`, and a checksum comparison of the data snapshot against the live data (while in maintenance mode).
A backup that fails verification is renamed `*.FAILED` and the command exits non-zero.

`backup_on_start: true` takes a backup at every add-on start. A backup is always taken before an upgrade.

**Restore** verifies the backup, takes a *pre-restore safety backup of the current state*, drops and recreates the
database, imports the dump, rsyncs the data back with `--delete`, extracts the config, leaves maintenance mode.

**Security:** backups contain `config.php` (DB password, `secret`, `passwordsalt`) and the data. Treat `/backup` like the
data itself. Hard-link snapshots live on one filesystem: copy `/backup/nextcloud_official` off the device too (Home Assistant
backup location sync, rsync to NAS).

Home Assistant's own add-on backups include `/data` – set `data_path` to `/share/...` if you do not want terabytes in HA backups,
and then back up that folder yourself (the `nc-backup` data snapshots do cover it).
