# Proposal

## Why

Authentik currently loads each application's `/favicon.ico` directly in the viewer's browser. Some icons require an Access session; Actual and Karakeep serve raster favicons no larger than 48 pixels even though better artwork is available.

## What Changes

- Use the existing `shrublab-assets` R2 bucket and `assets.shrublab.xyz` custom domain. Neither is recreated or adopted into OpenTofu in this change; the asset host stays outside web route policy.
- Declare source choices centrally in `policy/assets.nix`: vendored files, local service paths, or explicit upstream URLs. Small SVG sources and attribution live under `assets/`; raster media remains manually uploaded.
- Service modules register their own listener, unit ordering and package/image refresh triggers through a declaration-only asset contract. A selected `assets-publisher` aspect generates independent publication units.
- Publish at runtime, not during evaluation or a Nix build. Compare content and metadata, skip unchanged writes, and preserve the last good object on failure. No automatic pruning or refresh timer.
- Use the existing bucket-scoped credential in `secrets/common.yaml`, readable by publishing hosts. No secret is decrypted or edited by the agent.
- Publish icons for all twelve routed Authentik applications, using installed artwork where available and reviewed upstream SVGs otherwise. The operator approved the initial Actual/Homarr/Karakeep pilot. Publish the repo-owned brand icon and horizontal logo from the identity host; Authentik consumes stable R2 URLs. Cloudflare Access is an external federation client with no application launch route, not an icon publication owner.

## Capabilities

### New Capabilities

- `shared-assets`: public asset addressing, centrally declared sources, service-owned registration and runtime publication with idempotency and last-good preservation.

### Modified Capabilities

- `internal-service-auth`: permit a shared credential whose authority is limited to one inert object bucket.

## Impact

New `policy/assets.nix`, curated SVGs, `modules/assets/`, service registrations, host aspect selections, Authentik icon projection, focused publisher checks and operator documentation. The existing R2 domain, bucket, wallpaper and encrypted credential remain operator-owned infrastructure. No Worker, write API, build-time fetch hashes, Authentik media writes, image conversion, automated pruning or Access topology changes.
