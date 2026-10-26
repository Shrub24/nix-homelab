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
keep current, and the artwork is already reachable where it belongs, so the identity dashboard
resolves each tile from the application itself: `policy/assets.nix` declares a path the service
serves, and the tile URL is built from that application's own origin. Only the two applications
that serve no usable artwork carry a commit-pinned upstream URL instead. The viewer's browser
fetches those icons, so a tile follows the deployed version and the fleet redistributes nothing.

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
file, because there is nowhere to publish it. An `icons` entry names either a path served by the
application or a pinned upstream URL. No service module registers assets, so adding an
application tile is one policy entry.

| Consumer | Source | Resolved as |
| --- | --- | --- |
| Actual | `/android-chrome-512x512.png` | application origin |
| Beszel | `/static/icon.svg` | application origin |
| BookOrbit | `/pwa-icon-source.svg` | application origin |
| GeoPulse | `/geopulse-logo.svg` | application origin |
| Grafana | `/public/img/grafana_icon.svg` | application origin |
| Homarr | pinned upstream `logo.svg` | `raw.githubusercontent.com` |
| Inbox Zero | `/icons/icon-512x512.png` | application origin |
| Karakeep | `/icons/logo-icon-dark.svg` | application origin |
| Langfuse | `/icon.svg` | application origin |
| Memos | `/logo.webp` | application origin |
| Paperless | pinned upstream `logo_leaf.svg` | `raw.githubusercontent.com` |
| tududi | `/icon-logo.png` | application origin |

A tile fails to render while its application is unreachable, and a Cloudflare Access-gated
application shows no icon until the viewer holds that host's session. Both are accepted: the
alternative is publishing copies of third-party artwork we would then have to license and keep
current.

The wallpaper is declared as a URL with no source file, so publication cannot recreate it: it is
uploaded by hand, and it may equally be pointed at any other public location. Cloudflare Access is an external federation client without an
application launch route and is excluded.
