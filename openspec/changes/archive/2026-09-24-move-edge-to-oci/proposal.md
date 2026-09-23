# Move the Caddy edge to oci-melb-1

## Why

The public edge (Caddy + ACME + Cloudflare credentials) has been running on `la-admin-1` only because LA was the first host brought up. It belongs on the provider host that serves most public routes, so the public listener sits next to the workloads it publishes and LA becomes what it actually is — an admin origin.

The move turned out not to be a routing change. It exposed a coupling: the Kanidm provider on LA borrowed the edge's ACME certificate and hid behind the edge's local reverse proxy, so its route stopped working the moment the edge left. Nine other LA services are plain-HTTP upstreams reached over the tailnet and needed only to bind the private interface; Kanidm is the one service that requires TLS of its own, so its transport needs a decision rather than a bind-address change.

## What Changes

- **Edge placement:** `oci-melb-1` serves the edge role (Caddy, ACME, Authenticated Origin Pulls, Cloudflare DNS-01 credentials); `la-admin-1` serves the origin role and publishes no route of its own.
- **One declared exposure axis:** every route declares its `exposureMode`, and the served mechanism joins the existing vocabulary as `tailscale-serve` (the providing host renders the front the edge dials) beside `tailscale-upstream`, `tailscale-only`, and the edge-local `direct`. The field is required, so no route inherits an unlabelled default.
- **Provider-side front:** a host that provides such a route renders its own front for the edge, driven by resolved policy. The mechanism is implemented once, in the ingress aspect's origin role, so no service learns how the private network exposes it.
- **Kanidm owns its TLS:** the provider generates and owns a host-local certificate instead of reading the edge's ACME material through the edge-only `caddy` group, and stops ordering itself after a reverse proxy that no longer exists on its host.

## Impact

- Affected specs: `edge-proxy-ingress`, `policy-service-catalog`, `kanidm-identity`
- Affected code: `policy/web-services.nix`, `lib/policy.nix`, `modules/web/{web-policy,ingress,ingress-runtime}.nix` plus a new origin-role contributor, `modules/identity/{identity-provider,kanidm-runtime}.nix`
- Affected contracts: dendritic scaffold contract (resolved-policy keys, new unit), web-service catalog contract
- Cutover order: deploy `la-admin-1`, deploy `oci-melb-1`, then flip the edge DNS record. The record flip is the only step that changes public behaviour, and it is reversible on its own.
