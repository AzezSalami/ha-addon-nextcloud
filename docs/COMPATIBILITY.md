# Compatibility matrix

Sources: `nextcloud/docker` 35 apache Dockerfile (`php:8.5-apache-trixie`, Nextcloud 35.0.1); Docker Hub tag listing
for `nextcloud:35.0.1-apache` (amd64, arm64/v8, arm/v5, arm/v7, 386, ppc64le, s390x, riscv64); `proxy.php` of
`CollaboraOnline/richdocumentscode` (checks: `not_linux`, `not_x86_64`, `appimage_missing`, `appimage_not_executable`,
`exec_disabled`, `no_glibc`, `no_fontconfig`); that repository's README (AppImage does not support musl; ARM64 users install
`richdocumentscode_arm64`).

| Platform | Base image | libc | Built-in CODE app | Add-on support |
|---|---|---|---|---|
| amd64 / x86_64 | `nextcloud:35.0.1-apache` (Debian trixie) | glibc | `richdocumentscode` | **Yes** – integration-tested (see TESTING.md) |
| aarch64 / arm64 | same multi-arch tag | glibc | `richdocumentscode_arm64` | **Declared**; built and tested only if the CI arm64 job ran (see TESTING.md). Availability of a release of `richdocumentscode_arm64` matching NC 35 must be checked in the app store. |
| armv7 / armhf, i386 | exists | glibc | none (AppImage is x86_64/aarch64 only) | **No** – the add-on refuses to start; use standalone Collabora on another host |
| any | `*-fpm-alpine`, LinuxServer (Alpine) | **musl** | AppImage cannot run → `no_glibc` | **Never** |

| Component | Version in this release |
|---|---|
| Nextcloud | 35.0.1 (image tag pinned; update per UPDATING.md) |
| PHP | 8.5 (from the image) |
| Nextcloud Office (`richdocuments`) | latest store release compatible with the installed Nextcloud (installed at first start) |
| CODE app | latest store release compatible; the AppImage bundles its own Collabora Online build |

Nextcloud Office and the CODE app are installed from the Nextcloud app store; their versions are not pinned by the image.
If the store has no release compatible with a brand-new Nextcloud major, installation reports `incompatible_office`.

## Databases

| Engine | Versions | Discovery | Backup/restore | `nc-migrate` import |
|---|---|---|---|---|
| MariaDB / MySQL | MariaDB 10.6+ / 11 (tested with 11), MySQL 8 | Supervisor `mysql` service (MariaDB add-on) or external | `mariadb-dump` / `mariadb` | yes |
| PostgreSQL | tested with 17; client tools are v17, so the server must not be newer | external only | `pg_dump` / `psql` | no (new installs, backup, restore only) |
