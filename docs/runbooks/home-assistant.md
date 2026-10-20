# Home Assistant Runbook

Home Assistant runs as a container on `home-forge`, sharing the host's network
namespace so discovery integrations work, with its configuration directory
(`/srv/data/home-assistant`) owned by the operator rather than rendered by Nix.
The route `https://hass.shrublab.xyz` is declared but withheld until the
instance is onboarded and accepted.

## Status (2026-10-26)

- The aspect, route, image pin, backup contract and contract test are in the
  repository.
- Selected on `home-forge`; **not deployed yet**.
- The route's `publish` posture is `false`, so the edge serves no site for it.

## 1. Reach it before release

The container binds `8123` on every interface because it shares the host network
namespace, and the tailnet is already an encrypted, authenticated transport, so
there is nothing to terminate in front of it:

```
http://home-forge.tail0fe19b.ts.net:8123
```

Home Assistant's own login is the only gate at this point. Create the owner
account on first visit — that account is the administrator.

If the address does not answer, check in this order:

```
systemctl status podman-home-assistant
journalctl -u podman-home-assistant -n 50 --no-pager
podman logs home-assistant --tail 50
```

## 2. Onboard

Home Assistant creates a minimal `configuration.yaml` on first start; Nix seeds
nothing, so everything in `/srv/data/home-assistant` is yours:

- Complete the onboarding wizard.
- Add integrations from the UI — they live in `.storage`, not in YAML.
- Set `Settings → System → Network` to anything you need; the port must stay
  `8123` (see below).

The directory is mode `0700` and holds `.storage` with every integration
credential and token. It is the sensitive part of this service.

## 3. Ports, and why 8123 is load-bearing

`services.hass.port` and the policy route's `origin.port` are held together by an
assertion. If you change `http.server_port` in `configuration.yaml`, change
`services.hass.port` and `policy/web-services.nix` in the same commit, or the
edge will dial a port nothing listens on.

A second collision to watch for: any other service on `home-forge` that wants
`8123` cannot have it while this container runs.

## 4. Adding a radio later

`home-forge`'s facter report shows no USB devices and no Bluetooth, so nothing
local is being coordinated today. When a Zigbee/Z-Wave coordinator or a Bluetooth
adapter is attached, the container needs the device and, for Bluetooth, the host
bus:

```nix
virtualisation.oci-containers.containers.home-assistant = {
  volumes = [
    "${cfg.dataDir}:/config"
    "/etc/localtime:/etc/localtime:ro"
    "/run/dbus:/run/dbus:ro"          # Bluetooth
  ];
  extraOptions = [
    "--network=host"
    "--device=/dev/ttyACM0:/dev/ttyACM0"   # Zigbee/Z-Wave stick
  ];
};
```

`--device` and `/run/dbus` widen what the container can touch, so add each one
deliberately rather than up front. Host networking is already a wide grant and
is the reason discovery works at all.

## 5. Release to the public hostname

1. Confirm the instance is reachable and healthy over the tailnet.
2. Set the route's `publish = true` in `policy/web-services.nix`.
3. Set Home Assistant to trust the edge as a proxy, in `configuration.yaml`:

   ```yaml
   http:
     use_x_forwarded_for: true
     trusted_proxies:
       - <edge tailnet address>
   ```

   Without this Home Assistant rejects proxied requests, and the login page
   answers 400. The edge is `oci-melb-1`; dial it as the route does (its tailnet
   name) and pin its address, not the whole `100.64.0.0/10` range.
4. Deploy. Cloudflare Access sits outside Home Assistant's login
   (`access.requireCloudflareAccess = true`), so a browser passing Access still
   has to log in to Home Assistant.

`access.oidc.enabled` stays off: this instance uses Home Assistant's own auth.
Moving it to Kanidm later means the `hass-oidc-auth` custom component in
`/config/custom_components`, which Nix does not manage in a container — decide
that as its own change, not as a side effect of publishing.

## 6. Backups and restore

The backup contract is export-first (`docs/runbooks/state-restore.md`):

- The recorder database (`home-assistant_v2.db`) is captured through SQLite's
  online backup API into the state-backups staging root, so a mid-write copy is
  never taken.
- The rest of `/srv/data/home-assistant` (including `.storage`, which is where
  the real configuration lives) is captured raw, with the database and its
  `-wal`/`-shm` sidecars excluded.

To restore:

1. Stop the container: `systemctl stop podman-home-assistant`.
2. Restore `/srv/data/home-assistant` from the restic snapshot, including the
   exported database (place it back as `home-assistant_v2.db`).
3. Start the container and confirm the UI loads with your integrations intact.

`.storage` restore matters more than the database: the database holds history,
while `.storage` holds the integrations, users and tokens. A restore that brings
back only the database gives you an empty Home Assistant.

## 7. Updating

The image is a digest pin in `policy/oci-images.nix` (`homeAssistant`); Renovate
proposes the bump. Recent releases are checked before merging — Home Assistant
ships monthly and its schema migrations are one-way, so a rollback after
starting a new version means restoring the container's state, not just the
image.
