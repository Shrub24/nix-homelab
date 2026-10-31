# BookOrbit on home-forge

BookOrbit runs on nixpkgs' native `services.bookorbit` on `home-forge` (`modules/apps/bookorbit.nix`). Its acquisition sources are the general `torrents` aspect, Prowlarr and qBittorrent (`modules/torrents/torrents.nix`), which BookOrbit does not own. The route is `books.shrublab.xyz`: Kanidm OIDC gates the web app, and Cloudflare Access is off because OPDS and e-reader clients cannot pass it.

## Operator-provisioned secrets

Create `secrets/services/bookorbit.yaml` (encrypted with `sops`, rule in `.sops.yaml`) with these keys:

| Key | Purpose |
| --- | --- |
| `roles/bookorbit/password` | PostgreSQL role password. URL-safe, because it is interpolated into `DATABASE_URL`. |
| `app/jwt_secret` | `JWT_SECRET` |
| `app/podcast_encryption_key` | `PODCAST_ENCRYPTION_KEY` |
| `app/setup_bootstrap_token` | One-time `SETUP_BOOTSTRAP_TOKEN` for first-run setup |
| `app/email_encryption_key` | `EMAIL_ENCRYPTION_KEY`, 64 hex characters; encrypts saved SMTP passwords. Set before saving a provider password |
| `app/book_request_encryption_key` | `BOOK_REQUEST_ENCRYPTION_KEY`, required before indexer or download-client credentials can be saved |

Until the file exists, `home-forge` fails evaluation with a `secretFiles.host` assertion. This is intended.

qBittorrent uses the existing `secrets/hosts/home-forge/system.yaml`. Before deploying, add `qbittorrent/webui_password` with the WebUI password you want to retain:

```sh
sops secrets/hosts/home-forge/system.yaml
```

The account is `admin`. The unit loads the password through a systemd credential and inserts its PBKDF2 hash after nixpkgs writes the generated INI. Neither the password nor its hash enters the Nix store. Rotating the secret restarts qBittorrent. Set the same password in BookOrbit's download-client settings; qBittorrent has one WebUI account, not separate service accounts or API tokens.

## First activation

1. Deploy `home-forge`. The `bookorbit-migrate` oneshot runs migrations before the service starts.
2. Open `https://books.shrublab.xyz`, then complete setup with `SETUP_BOOTSTRAP_TOKEN` (`/auth/setup`).
3. Add the Kanidm provider in **Settings → OIDC / SSO**: issuer from the `bookorbit` client in `policy/identity.nix`, client ID and secret from Kanidm, scopes `openid profile email`, and redirect URI `https://books.shrublab.xyz/oauth2-callback`. Enable **Allow local account linking** if the first admin already exists locally. Link a superuser before setting `DISABLE_LOCAL_AUTH`.
4. Set the library folder to `/srv/storage/media/books`.

## Acquisition sources

The `torrents` aspect (`modules/torrents/torrents.nix`) provides both sources; BookOrbit has its own Prowlarr and download-client integration, configured in its WebUI.

- **Prowlarr** is tailnet-only at the `prowlarr` catalog endpoint (`http://home-forge.<tailnet>:9696`), with no public route. Add indexers in its UI, then in BookOrbit's WebUI give it `http://127.0.0.1:9696` (same host) and Prowlarr's API key.
- **qBittorrent** WebUI is tailnet-only at the `qbittorrent` catalog endpoint (`http://home-forge.<tailnet>:8091`). In BookOrbit, add a qBittorrent download client with URL `http://127.0.0.1:8091`, username `admin`, and the password stored at `qbittorrent/webui_password` in the host secret file. Leave path mapping unset because both native services see the same filesystem. A `bookorbit` category can distinguish its transfers from other torrents; it is not a permission boundary.
- Downloads save to `/srv/storage/media/downloads`, qBittorrent's default save path.
- qBittorrent's INI is regenerated at every start. Connection limits, queueing and upload limits are declared in `modules/torrents/torrents.nix`; change them there rather than relying on WebUI edits. Torrents and categories remain application-owned profile state.
- Peers reach qBittorrent directly on TCP and UDP 43750 (not 6881, which private trackers ban), so the home address is visible to the swarm. A VPN-bound interface is the planned follow-up.

## Indexer plugins

`pkgs/bookorbit-plugins` vendors the two plugins from `orbit-plugins/bookorbit-plugins-extra` — `libgen` (direct download, no credentials) and `myanonamouse` (torrent, needs the account's session id) — and the module links them into `/srv/data/bookorbit/plugins/indexers/<name>/index.mjs`. Restart BookOrbit, then add a source under Settings → System → Requests; nothing is enabled until a source exists.

Upstream tags each plugin separately, so the package pins a revision rather than a tag. The links are read-only store paths, so an in-app plugin update cannot replace them: bump the pin in `pkgs/bookorbit-plugins/default.nix` instead. These are third-party modules running inside the application, which Nix does not verify beyond the pinned revision.

## Recovery

- The PostgreSQL database is covered by the shared substrate's export-first dump.
- `/srv/data/bookorbit` (covers and app data) is covered by `state-backups`.
- The library at `/srv/storage/media/books` is bulk storage and is not in the backup set. Back it up with the storage plan.
