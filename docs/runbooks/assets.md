# Asset publication

Mechanism and ownership: [Shared assets](../assets.md).

## Cache purging after a rotation

Rotation purges the replaced object so a new image appears without waiting out the edge cache.
That needs a Cloudflare API token with **Zone Read** and **Cache Purge** on the zone.

1. Create the token, then put it in its own service scope — not `common.yaml`, because only the
   rotating host reads it:

   ```sh
   sops secrets/services/assets.yaml    # assets.cf_purge_token: <token>
   git add secrets/services/assets.yaml # .# resolves tracked files only
   ```

   The key is declared in `secrets/.templates/services/assets.yaml.j2`; the file's `.sops.yaml`
   rule encrypts it to the owner and the rotating host alone. If it is missing, the rotator logs
   `purge: no Cloudflare credential configured` and rotation still works, bounded by the object's
   cache lifetime.

## Rotating the background

1. Upload candidate images to the `backgrounds/` prefix of `shrublab-assets`, with their own
   content type. Nothing in Git changes and no rebuild is needed.
2. Force a rotation without waiting for the timer:
   `ssh oci-melb-1 sudo systemctl start assets-wallpaper`.
3. Fetch the wallpaper URL from the brand policy without cookies and record status, content
   type and `cf-cache-status`; expect 200 and an image type. The rotation purges the URL, so a
   `MISS` or `REVALIDATED` on the next request is expected. If the journal reports
   `purge failed`, the previous image stays at the edge until the cache lifetime expires.
4. Confirm the journal records which candidate was chosen:
   `journalctl -u assets-wallpaper -n 5`.

## Preflight

1. Confirm `shrublab-assets` and its custom domain `assets.shrublab.xyz` exist.
2. Confirm the token has object read/write authority for that bucket only.
3. As the operator, populate `access_key_id` and `secret_access_key` in
   `secrets/common.yaml` using the existing secrets workflow. Do not print their values.
4. Run the repository checks before deployment.

## Deploy and inspect

1. Deploy `oci-melb-1` and `home-forge`, then `la-admin-1` through the normal deploy workflow.
2. On each host, list the jobs:

   ```sh
   systemctl status assets-publish
   ```

3. Inspect any failure:

   ```sh
   journalctl -u assets-publish.service -b
   ```

## Refresh

Publication is one unit covering every file-backed brand object, so a refresh is one command on
the host that owns the bucket writes:

```sh
sudo systemctl restart assets-publish
```

Each object reports `published` or `unchanged`, so a second run right after the first should be
all `unchanged`. After fixing a source or credential error, repeat the same command.

## Acceptance to record

1. Request the icon and logo URLs the brand policy declares without cookies. Record HTTP
   status and Content-Type; expect 200 and `image/svg+xml`.
2. Refresh twice and inspect the journals. Record the second run's `unchanged` outcome.
3. Confirm the wallpaper object remains present with `Content-Type: image/jpeg`.
4. In a fresh browser session, open the Authentik Application Dashboard and confirm every tile
   renders an icon. A tile rendered from an application's own origin stays blank while that
   application is unreachable or its Cloudflare Access session is absent.
5. Record a controlled failed-source check only on a disposable test key: the prior object's
   body must remain unchanged. Do not break a production source to run this check.

## Application browser favicons

Application icons are not published, so the dashboard reads them from each application. Where
an application's own favicon is configurable, point it at the icon it already serves:

1. In Homarr's administration branding settings, set the favicon URL to
   `https://raw.githubusercontent.com/homarr-labs/homarr/3f5cb84f705701c0748f8fb0aabdd9373e87109d/apps/docs/public/img/logo.svg`.
2. In Memos' instance custom profile, set the logo URL to its own `/logo.webp`. Confirm both its
   header logo and browser favicon.
