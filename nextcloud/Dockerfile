# syntax=docker/dockerfile:1
# Base: official Nextcloud image (Debian trixie, glibc). NEVER use an Alpine/-fpm-alpine tag:
# the built-in CODE AppImage does not support musl libc (proxy.php reports "no_glibc").
ARG BUILD_FROM=nextcloud:35.0.1-apache
FROM ${BUILD_FROM}

ARG NC_IMAGE_REV=1
ARG BUILD_ARCH
ARG BUILD_VERSION=dev

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Runtime deps for the add-on scripts and for CODE (proxy.php requires fontconfig,
# ldconfig, grep, a shell, and `ip` to detect IPv6). mariadb-client = backup/migration.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl jq fontconfig iproute2 procps util-linux \
        mariadb-client rsync gzip tar coreutils libcap2-bin; \
    rm -rf /var/lib/apt/lists/*; \
    # fail the build if the base is not glibc
    if ldd --version 2>&1 | head -n1 | grep -qi musl; then echo "musl base image not supported" >&2; exit 1; fi

COPY rootfs/ /
# The base image declares /var/www/html as an (anonymous) VOLUME, which Home Assistant would lose on container
# re-creation and which cannot be replaced by a symlink. Re-point the upstream entrypoint and Apache at the
# persistent add-on path instead (pure path substitution; entrypoint logic is untouched).
RUN set -eux;     sed "s#/var/www/html#/data/nextcloud/html#g" /entrypoint.sh > /entrypoint-addon.sh;     chmod 0755 /entrypoint-addon.sh;     sed -i "s#DocumentRoot /var/www/html#DocumentRoot /data/nextcloud/html#" /etc/apache2/sites-available/000-default.conf;     grep -q "/data/nextcloud/html" /entrypoint-addon.sh /etc/apache2/sites-available/000-default.conf
RUN chmod 0755 /usr/local/bin/* /usr/local/lib/nc-addon/*.sh \
    && mkdir -p /run/nc-addon

# Single-purpose Apache config: only the Apache RemoteIP module from the base image is used.
HEALTHCHECK --interval=60s --timeout=30s --start-period=15m --retries=3 \
    CMD ["/usr/local/bin/nc-healthcheck"]

LABEL io.hass.type="addon" \
      io.hass.name="Nextcloud (official image + built-in CODE)" \
      io.hass.description="Nextcloud with Nextcloud Office and built-in CODE" \
      io.hass.arch="amd64|aarch64" \
      io.hass.version="${BUILD_VERSION}" \
      org.opencontainers.image.source="https://github.com/AzezSalami/ha-addon-nextcloud"

ENTRYPOINT []
CMD ["/usr/local/bin/nc-run"]
