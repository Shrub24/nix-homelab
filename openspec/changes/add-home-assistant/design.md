# Design

## Shape: the upstream container, not the nixpkgs Core module

Two installation methods exist. nixpkgs' `services.home-assistant` renders `configuration.yaml` from Nix and builds every integration's dependencies into one package; the project's own container image is the method upstream supports.

The deciding fact is where the state lives. Modern Home Assistant keeps integrations, users, tokens and dashboards in `.storage`, and history in a recorder database. The native module makes `configuration.yaml` declarative and leaves all of that imperative, so an operator configures the instance through the UI either way. Against that, the native module rebuilds a large Python closure on every release and tracks nixpkgs rather than Home Assistant's own cadence. The container gives digest-pinned versions that Renovate bumps and no rebuild.

Rejected alternatives are recorded in D-100: the native module (better only for an all-YAML, stable integration set), and a bridged network with a published port (discovery integrations mostly stop working).

## Network: host namespace, nothing published

Discovery integrations — HomeKit, Chromecast, Hue, Matter, ESPHome — discover devices with mDNS/SSDP, which needs the container in the LAN's namespace. Both upstream's container documentation and the nixpkgs wiki use `--network=host` for exactly this reason, so this module does the same and publishes no port. Home Assistant therefore binds `8123` on the host itself.

Consequences: the listener is a host fact, so `services.hass.port` and the policy route's origin port are asserted equal; and a future radio needs `--device` (plus `/run/dbus` for Bluetooth) rather than a network change.

## Options namespace: `services.hass`

nixpkgs owns `services.home-assistant` for its native module. Declaring our container options at that path would make one option name mean two different installations depending on which module a host imported, which is a silent trap. The aspect keeps the discoverable name (`aspects.home-assistant`), while the options use the project's short name. The module never imports the native one.

## State: operator-owned, no Nix-rendered configuration

`/srv/data/home-assistant` is created (mode `0700`) and otherwise untouched. Home Assistant writes a minimal `configuration.yaml` on first start, and the operator owns everything below the directory — including `.storage`, which is the real configuration. Rendering `configuration.yaml` from Nix was rejected: it would fight every UI-driven change and give a partial declarative surface that looks complete.

## Routing: withheld by policy, released by one field

The route is declared with `publicReady = false`, so the edge renders no site for it (D-098: publication is the policy's own field, with no host-side release switch). Until release, the instance is reached over the tailnet at the provider's port — the tailnet is already an encrypted, authenticated transport, so nothing needs to terminate in front of it.

`exposureMode = "tailscale-upstream"`, not `tailscale-serve`: the container binds the host's interfaces, so its socket is reachable on the provider's tailnet name and no provider-side front is needed.

Publishing additionally requires `use_x_forwarded_for` and a pinned `trusted_proxies` entry in `configuration.yaml`; that is operator-owned state, so the runbook carries it rather than the module.

## Authentication: Home Assistant's own login first

Kanidm OIDC for Home Assistant needs the `hass-oidc-auth` custom component inside `/config/custom_components`, which Nix does not manage in a container. Putting an unmanaged component in the authentication path before the instance is proven buys risk rather than parity, so `access.oidc.enabled` stays off and Cloudflare Access will be the outer wall once published. Moving to OIDC later is its own change.

## Backup: export-first

The recorder database is a live SQLite file, so it is exported with SQLite's online backup API into the state-backups staging root, and the database plus its `-wal`/`-shm` sidecars are excluded from the raw copy of the directory. This is the contract `actual`, `memos`, `tududi` and `docs-mcp` already follow.

`.storage` is the part that matters most in a restore: it holds integrations, users and tokens, while the database holds only history. A restore that brings back only the database gives an empty Home Assistant, which the runbook states explicitly.

## Notifications

The container is registered with `services.notify.events` for failure. No start-limit tuning is needed here: the fleet's containers already carry nixpkgs' widened limit (5 starts per hour), which a crash loop crosses, so a failing instance reaches `failed` and the handler fires.
