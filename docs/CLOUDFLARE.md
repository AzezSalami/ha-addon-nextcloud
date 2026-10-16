# Cloudflare Tunnel setup

`no_glibc` is **not** caused by Cloudflare: it is produced locally by `proxy.php` when the CODE AppImage cannot be
executed (musl/Alpine). Cloudflare only matters for the checks *after* CODE starts.

## Topology (nothing exposed directly)

```
Browser ──HTTPS──> Cloudflare ──tunnel──> cloudflared ──HTTP──> Nextcloud add-on :80
                                                                   │ built-in CODE (127.0.0.1:9983, via proxy.php)
```

* The add-on publishes plain HTTP on host port `8099` by default (Configuration → Network). If `cloudflared` runs as a Home Assistant add-on you can clear that port (leave it empty) so nothing is reachable on the LAN except through the tunnel. Target
  `http://<repo-hash>-nextcloud-official:80` (shown as the add-on hostname on its Info page, with `_` replaced by `-`).
  If `cloudflared` runs elsewhere, keep the port enabled and use it only on a trusted LAN; never port-forward it on your router.
* TLS terminates at Cloudflare. The tunnel→add-on hop is plain HTTP on the internal Supervisor network.

## Add-on options

| Option | Value | Why |
|---|---|---|
| `public_url` | `https://cloud.example.com` | Sets trusted domain, `overwritehost`, `overwriteprotocol=https`, `overwrite.cli.url` |
| `trusted_domains` | extra names only (e.g. LAN name) | The `public_url` host is added automatically |
| `trusted_proxies` | `172.30.32.0/23` (default: HA add-on network) plus the cloudflared source if it is elsewhere | Makes Nextcloud trust `X-Forwarded-*` / client IP **only from those hops**. Never use `0.0.0.0/0`. |
| `internal_url` | usually empty | See below |

Cloudflare tunnels already send `X-Forwarded-Proto: https` and `X-Forwarded-For`/`CF-Connecting-IP`. WebSocket
passthrough is enabled by default in Cloudflare Tunnel; no extra setting is needed.

## Does the container need to reach its own public hostname?

Yes, for built-in CODE: `coolwsd` fetches the document from Nextcloud over the WOPI URL that contains `public_url`, and
Nextcloud validates its own CODE URL. The container therefore must (1) resolve `cloud.example.com`, (2) reach it, and
(3) validate its TLS certificate (Cloudflare's edge certificate is publicly trusted, so this works with no changes).

`internal_url` (e.g. `http://127.0.0.1`) sets `richdocuments wopi_callback_url`, i.e. a different URL for CODE to call
Nextcloud back. Use it **only** if `nc-diag` shows `dns_failure`/`public_unreachable` (hairpin through Cloudflare is blocked).
It may differ from `public_url` only on the callback path; user-facing URLs must stay the public hostname. This option is
supported by Nextcloud Office but was **not** verified end-to-end with built-in CODE by the author (the built-in
`coolwsd` must allow the callback host); verify with `nc-diag` and by opening a document.

## Cloudflare Access

If Access protects `cloud.example.com`, server-to-server calls (Nextcloud→itself, `coolwsd`→Nextcloud) will receive the
Access login page. `nc-diag` reports this as `cloudflare_access`. The add-on never bypasses Access. Options:
a service-token-based *Service Auth* policy or a *Bypass* policy limited to the egress IP for `/status.php`,
`/apps/richdocuments/*`, `/index.php/apps/richdocuments/wopi/*`, `/remote.php/*` – or exclude those paths from Access.
Browsers must still be able to load Nextcloud (use Nextcloud's own login rather than Access, or Access with a user policy).

## Verification

```bash
docker exec addon_<slug> nc-diag
```

Expected: `proxy.php?status : ok`, `hosting/capabilities` HTTP 200 JSON, `hosting/discovery` HTTP 200 XML,
`https status.php : HTTP 200 (ok)`, `activate-config : OK`.

| nc-diag code | Meaning |
|---|---|
| `dns_failure` | Container cannot resolve the public host |
| `tls_failure` | Certificate chain invalid from inside the container (never disabled by this add-on) |
| `cloudflare_access` / `cloudflare_block` | Access policy / WAF blocks server-to-server calls |
| `proxy_misconfig` | Redirect loop, wrong service URL, or another service answering |
| `wopi_validation` | Nextcloud rejected the WOPI host; check `public_url` |
| `websocket_unreachable` | Upgrade probe failed to connect |

## WebSockets with built-in CODE

According to the current `proxy.php` source, the built-in server is fronted by a PHP proxy that handles plain HTTP
requests and has no `Upgrade` handling, so the Collabora client uses its HTTP long-polling fallback. `nc-diag` reports
the probe result (`101` would mean native WebSocket). A standalone Collabora behind its own tunnel hostname uses real
WebSockets (see [ALTERNATIVE-COLLABORA.md](ALTERNATIVE-COLLABORA.md)).
