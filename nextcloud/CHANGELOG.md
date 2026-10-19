# Changelog

## 35.0.2-7
* Nextcloud Office's cached discovery/capabilities (the list of supported file types and the "new document" entries) are refreshed after the add-on configures Office, so Word, Excel, PowerPoint and OpenDocument formats are offered right away.
* `nc-diag` and the refresh keep the callback URL (`internal_url`): `richdocuments:activate-config` resets it, which previously could silently clear it.

## 35.0.2-6
* New option `ssl_allow_expired` (default off): start with an expired certificate, with a loud warning in the log. Only expiry is excused; missing, invalid or mismatched certificate/key files still stop the add-on.

## 35.0.2-5
* `ssl: true` with empty `certfile`/`keyfile` now generates a self-signed certificate covering the addresses in `trusted_domains` (IPs and host names) and `localhost`, so `https://<ip>:<port>` works without certificate files. It is kept across restarts, regenerated when the address list changes or 30 days before expiry, and its public part is copied to `/share/nextcloud/selfsigned-certificate.crt`. `certfile`/`keyfile` now default to empty; naming files in `/ssl` still uses them (and fails clearly if they are unusable).

## 35.0.2-4
* Nextcloud Office: the built-in server address is now set at start from `public_url` (previously Nextcloud Office only configured it when an admin first opened Files, from that admin's address, and then switched off TLS verification). A custom office server is never overwritten.
* `nc-diag` reports "Nextcloud Office has no server address yet" as a warning instead of a misleading WOPI error, and shows the real error text on genuine failures.
* Quieter logs: the AppImage is extracted directly (no FUSE error) and the fontconfig cache is writable.

## 35.0.2-3
* HTTPS option: `ssl`, `certfile`, `keyfile` (certificates from Home Assistant's `/ssl`). Container port 443 is the web interface (HTTPS when `ssl` is on, plain HTTP otherwise) and is published on host port 8099 by default; port 80 is plain HTTP and no longer published by default. The certificate is validated before start.
* The "Open Web UI" button follows `ssl` (`[PROTO:ssl]`).
* `public_url` no longer forces host/https for every request, so opening the add-on by LAN IP stays on that IP. Behind a tunnel, Nextcloud takes the scheme from `X-Forwarded-Proto` (the proxy must be in `trusted_proxies`). The old behaviour is available as `force_public_url: true`.
* Removed `overwrite_from_regex` (introduced in 35.0.2-2), replaced by the simpler `force_public_url`.

## 35.0.2-2
* New option `overwrite_from_regex`: apply the forced public host/https only to requests whose connecting address matches (the tunnel or proxy), so the "Open Web UI" button and LAN access by IP no longer redirect to `public_url`. Empty (default) keeps the old behaviour.

## 35.0.2-1
* Update to Nextcloud 35.0.2 (official `nextcloud:35.0.2-apache`). Existing installs upgrade automatically after a verified backup.

## 35.0.1-5
* "Open Web UI" button on the add-on page (`webui`), pointing at the published HTTP port.

## 35.0.1-4
* The add-on now publishes its HTTP port (container port 80) on host port 8099 by default; clear it under Network to disable LAN access.

## 35.0.1-3
* Fix: the Supervisor overrides the `BUILD_FROM` build argument with its own Alpine image, which broke the build (`apt-get: command not found`). The Dockerfile now pins the official Debian-based Nextcloud image directly, and CI builds with the Supervisor's arguments to prevent a regression.

## 35.0.1-2
* PostgreSQL support (`db_type: postgresql`, external server): install, backup, restore. `db_port: 0` selects the engine default.

## 35.0.1-1
* Initial release: Nextcloud 35.0.1 on the official Debian (glibc) `apache` image, Nextcloud Office + built-in CODE,
  MariaDB via Supervisor, verified backups, `nc-diag`, `nc-migrate`.
