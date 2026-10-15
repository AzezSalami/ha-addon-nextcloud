# Alternative: standalone Collabora Online (when built-in CODE is not possible)

Use this if you run on armv7/i386, have < 2 GiB free RAM, no `richdocumentscode_arm64` release exists for your Nextcloud
version, or want real WebSockets and better isolation.

| | Built-in CODE (default) | Standalone `collabora/code` |
|---|---|---|
| Setup | zero | second container + own hostname/tunnel |
| Isolation | runs inside the Nextcloud container, reduced-privilege mode | separate container (needs `SYS_ADMIN` or `--o:security.capabilities=false` style trade-offs) |
| Transport | HTTP via PHP proxy (long-polling) | native WebSockets |
| Performance | PHP proxy overhead; smaller scale | better |
| Architectures | x86_64, aarch64 | amd64 (official), arm64 images exist for newer releases – check Docker Hub |

Sketch (not shipped as an add-on in this repository, therefore **untested here**):

```bash
docker run -d --name collabora -p 127.0.0.1:9980:9980 \
  -e "aliasgroup1=https://cloud.example.com:443" \
  -e "extra_params=--o:ssl.enable=false --o:ssl.termination=true" \
  collabora/code
```

Expose it with its own tunnel hostname (`office.example.com` → `http://localhost:9980`) forwarding WebSockets (default),
then in Nextcloud: disable `richdocumentscode*`, Administration → Nextcloud Office → *Use your own server* →
`https://office.example.com`, and keep certificate validation **on**. `aliasgroup1` is Collabora's WOPI host allow-list:
set it to exactly your Nextcloud origin.
