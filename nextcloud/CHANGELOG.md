# Changelog

## 35.0.1-3
* Fix: the Supervisor overrides the `BUILD_FROM` build argument with its own Alpine image, which broke the build (`apt-get: command not found`). The Dockerfile now pins the official Debian-based Nextcloud image directly, and CI builds with the Supervisor's arguments to prevent a regression.

## 35.0.1-2
* PostgreSQL support (`db_type: postgresql`, external server): install, backup, restore. `db_port: 0` selects the engine default.

## 35.0.1-1
* Initial release: Nextcloud 35.0.1 on the official Debian (glibc) `apache` image, Nextcloud Office + built-in CODE,
  MariaDB via Supervisor, verified backups, `nc-diag`, `nc-migrate`.
