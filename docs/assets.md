# Shared assets

`assets.shrublab.xyz` is the public custom domain of the existing R2 bucket
`shrublab-assets`. It is not a web-policy route and is not behind Cloudflare Access.
The bucket and domain remain operator-managed; this repository manages selected objects,
not the whole bucket.

## What the bucket holds

Brand assets are declarations, not files: `policy/assets.nix` names a URL for the icon, the
logo and the wallpaper, and by default all three point at this fleet's bucket. An entry that
also names a tracked source file — the icon and the logo — is published there by one unit per
entry, which replaces the object when the bytes or the credential change and skips it when the
digest already matches. An entry with a URL but no file is served by whoever hosts it, so it
gets no unit; pointing a brand asset at another public location is a one-line policy edit.

Publishing is a bucket write rather than a host fact, so one host owns it: `oci-melb-1` selects
`assets-publisher`, and it also owns rotation. Publishing from every host that references the
URLs would repeat the same idempotent upload and materialise the bucket credential three times.

Application icons are **not** published. A copy in the bucket would be ours to license and to
keep current, so every tile points at a commit-pinned upstream file — a dashboard-icons or
selfhst CDN path, or the application's own repository — recorded in `policy/assets.nix`. Pinning
the commit rather than the moving branch is what keeps a tile stable when upstream reorganises
its set, and the fleet redistributes nothing. Taking the artwork from the running application
instead was tried and dropped: several serve no icon, several serve it only behind Cloudflare
Access, and the paths move between versions. A client with no declared entry falls back to its
own favicon.

## The background

The wallpaper is the one brand asset with no tracked source and no upload step. Its URL is a
path on the identity host, and `assets-wallpaper.timer` picks a random image from the bucket
prefix `backgrounds/` and copies it over the file that path serves. The URL therefore never
changes, a new wallpaper is an object upload rather than a rebuild, and the previous image
stays in the prefix as a candidate.

A rotation is a copy inside the bucket, so one host owns it (`services.assets.wallpaper.enable`
on `oci-melb-1`); a second rotator would overwrite the first. After the copy it purges that URL,
which is what lets the object carry a long edge lifetime while a replaced image still appears on
the next request. A failed purge is logged and ignored — the previous image then stays visible
until the cache lifetime expires, which is the same state as no purge at all.

The bucket's custom domain is the delivery path, not `r2.dev`: Cloudflare rate-limits `r2.dev`
and documents it for development only, and only a custom domain is served through Cloudflare's
cache. `assets.shrublab.xyz` is therefore exempt from the zone rate limit and holds objects with
a long edge lifetime and a short browser lifetime, so a rotation reaches the edge without
outliving a browser's copy.

## Authority

`policy/assets.nix` is the whole declaration. A `brand` entry is a URL plus, optionally, the
tracked file that publication uploads to it; an entry whose URL leaves `publicUrl` must have no
file, because there is nowhere to publish it. An `icons` entry is a pinned upstream URL. No
service module registers assets, so adding an application tile is one policy entry.

| Consumer | Upstream file | Host |
| --- | --- | --- |
| Actual | `dashboard-icons/svg/actual-budget.svg` | `cdn.jsdelivr.net` |
| Beszel | `dashboard-icons/svg/beszel.svg` | `cdn.jsdelivr.net` |
| BookOrbit | `dashboard-icons/webp/bookorbit.webp` | `cdn.jsdelivr.net` |
| GeoPulse | `selfhst/icons/svg/geopulse-light.svg` | `cdn.jsdelivr.net` |
| Grafana | `dashboard-icons/svg/grafana.svg` | `cdn.jsdelivr.net` |
| Homarr | `dashboard-icons/svg/homarr.svg` | `cdn.jsdelivr.net` |
| Inbox Zero | `docs/favicon.png` | `raw.githubusercontent.com` |
| Karakeep | `selfhst/icons/svg/karakeep.svg` | `cdn.jsdelivr.net` |
| Langfuse | `web/public/icon.svg` | `raw.githubusercontent.com` |
| Memos | `dashboard-icons/svg/memos.svg` | `cdn.jsdelivr.net` |
| Paperless | `selfhst/icons/svg/paperless-ngx.svg` | `cdn.jsdelivr.net` |
| tududi | `selfhst/icons/svg/tududi-light.svg` | `cdn.jsdelivr.net` |

A tile renders even while its application is unreachable, because the artwork comes from a CDN
rather than the service; a tile is blank only while that CDN is unreachable. Published third-party
artwork would be ours to license and keep current, which is why the bucket carries only the fleet's
own brand files.

The wallpaper is declared as a URL with no source file, so publication cannot recreate it: it is
uploaded by hand, and it may equally be pointed at any other public location. Cloudflare Access is an external federation client without an
application launch route and is excluded.
