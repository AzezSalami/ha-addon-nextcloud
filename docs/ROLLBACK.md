# Rollback

## A. Migration failed or you are not happy (old add-on untouched)

The migration never modifies the old add-on, its database or its data, so:

1. Stop the new add-on.
2. Remove the new add-on's `migration_mode`/test data if you want a clean retry (optional): delete the new database
   (`DROP DATABASE nextcloud_new`) and the new `data_path`. **Only** those – never the old database/data.
3. Re-point the Cloudflare Tunnel service at the old add-on.
4. Start the old add-on. Nothing was changed, so it behaves exactly as before.

If, against the instructions, the old add-on ran while the new one was in use (both pointing at *different* DB/data),
changes made in the new instance after the cut-over are **not** in the old one. Export them first if needed.

## B. Rolling back an upgrade of the new add-on

Every upgrade first creates a verified backup (`/backup/nextcloud_official/<ts>-pre-upgrade-<version>`). The image
refuses to start on data newer than itself (`Installed Nextcloud X is newer than the image`), so a plain downgrade of the
add-on version will not corrupt anything – it just will not start.

1. Install the previous add-on version (repository tag) so the image matches the pre-upgrade backup.
2. Start the add-on with `migration_mode: true` (Apache stays off), then:
   ```bash
   docker exec addon_<slug> nc-backup list
   docker exec addon_<slug> nc-backup restore /backup/nextcloud_official/<dir> --yes-restore
   ```
   `restore` verifies the backup, takes a safety backup of the current state, restores DB + data + config.
3. Set `migration_mode: false`, restart, run `nc-diag`.

> `nc-backup restore` requires an installed instance. If the config was lost, restore `config.tar.gz` manually
> first: `tar -xzf config.tar.gz -C /data/nextcloud/html` then run the command above.

## C. Full disaster recovery

Home Assistant backup of the add-on (includes `/data`: webroot, config, and the data directory when `data_path` is under `/data`)
plus a MariaDB add-on backup restores both sides. Restore both from the *same point in time*.
