# Update strategy

* The add-on version is `<nextcloud version>-<add-on revision>`. Bumping the image tag in `nextcloud/build.yaml`,
  `nextcloud/Dockerfile` (`ARG BUILD_FROM`) and `nextcloud/config.yaml` is the only change needed for a Nextcloud update.
* Nextcloud supports upgrading one major version at a time. Never skip a major.
* On start the add-on compares installed vs. image version. If the image is newer it creates a **verified backup**
  and aborts the upgrade if that fails. A newer installed version than the image is refused (no downgrades).
* Before updating the add-on in Home Assistant: take a Home Assistant backup of the add-on **and** MariaDB.
* Pin by digest for reproducible builds:
  ```bash
  docker buildx imagetools inspect nextcloud:35.0.1-apache | grep Digest
  ```
  then use `nextcloud:35.0.1-apache@sha256:<digest>` in `build.yaml` and the Dockerfile default.
  The weekly CI job (`ci.yml`, schedule) rebuilds and re-runs the integration tests so upstream drift is noticed.
* Provenance: the Docker Official Images are built by Docker Inc. and the Nextcloud tarball is GPG-verified inside the
  upstream build. Verify the digest you pin against the `nextcloud/docker` repository / Docker Hub page before pinning.
  Image signature verification (cosign) is not published for Docker Official Images; this is a documented gap.
* `richdocuments` / CODE app updates come through Nextcloud's app updater; run `nc-diag` after each.
