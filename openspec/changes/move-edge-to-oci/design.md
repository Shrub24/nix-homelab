# Design — move the Caddy edge to oci-melb-1

## Context

Canonical policy already separates two things: what a service publishes (`catalog`: public URL, access, health, upstream *shape*) and how the edge reaches it (`repo.web.hosts` / `currentHost`, which carry origins). One canonical requirement states the rule directly: *edge-local origin transport remains owned by the host-local policy resolution path*, and catalog consumers must not treat an edge-local origin as a cross-host address.

The edge move broke that separation in one place. `kanidm-admin` is the only route whose provider-side socket is loopback-bound and TLS-only, so its transport needed an owner. Before the move, the owner was "the edge, because it happened to be the same machine".

## Decisions

### D1 — How a service is exposed is one declared axis

The field already carried the vocabulary: `exposureMode` distinguished `tailscale-upstream`, `direct`, and `tailscale-only`, and the architecture notes called `tailscale-upstream` the cross-host route mode. So the served mechanism becomes a value of **that** field (`tailscale-serve`) rather than a second field beside it — one axis, one place to read a route's exposure. The field is required on every route: nothing inherits a default, so an unlabelled route fails evaluation instead of silently reading as a mode nobody meant. `declarePublic` remains the positive opt-in for publishing, and `tailscale-only` is its negative twin.

### D2 — The provider front is rendered by the ingress origin role, from policy

A new origin-side projection (`repo.web.originServices`) tells a host which routes it provides, since `repo.web.hosts` carries the edge's table and `currentHost` is empty on an origin. The ingress aspect's origin role renders one front per `tailscale-serve` route.

Rejected: a host-facing `services.privateExposure.*` namespace. This repository deleted its internal-contracts registry precisely so the web policy would be the single declaration point for private endpoints; a new option namespace would restate the same port and reachability facts in a second place. The replaceable seam is a **file** — all mechanism-specific code lives in one contributor beside the ingress aspect — not another option surface.

Rejected: rendering the front from the service's own module. That inverts the coupling it is supposed to remove: every TLS-only service would have to learn how the private network exposes it.

### D3 — Tailscale Serve, not `tailscale cert`

Serve provisions and renews the node certificate itself; file-based certificates are the operator's renewal problem, which would add a timer, key permissions, and restart ordering to the identity service. Verified on the live node before adopting: the tailnet reports `CertDomains: ["la-admin-1.tail0fe19b.ts.net"]` (HTTPS certificates are provisioned for this node), `https+insecure://` is a supported backend scheme, serve configuration requires root (units run as root), and a live front on a spare port returned the same response as a direct loopback request.

Rejected: `tailscale cert` plus binding the tailnet interface. It also puts a `.ts.net` name into the service's TLS identity — two names for one service — and makes the service depend on a non-loopback bind.

### D4 — Kanidm owns a host-local certificate

The provider generates a self-signed pair on first start and keeps it in its own state directory. The service presents it; nothing validates it, because the only consumer is a loopback hop. Serve terminates the tailnet TLS and proxies with `https+insecure://127.0.0.1:<port>`; the security boundary on that hop is localhost, not PKI. The public identity (`appUrl`, issuer, OIDC discovery) is unchanged, and a future fleet CA can be bound by overriding the certificate paths, which remain host-overridable options.

Rejected: keeping ACME on the provider. It requires the Cloudflare DNS-01 credential on a workload host, which is the blast-radius boundary the edge move tightened.

### D5 — Ports stay equal end-to-end

The front listens on the policy port and dials the service on the same port, so serve port = policy port = bind port and the existing "the port cannot drift" property survives. The provider asserts its configured bind matches the policy port, so a drift fails at evaluation with the two values named.

### D6 — Placement is a canonical ID; each consumer derives transport by its own policy

Routes declare `origin.provider` (a canonical host ID) plus scheme and port; no dial address lives in the policy, so moving the edge or a workload is one placement edit. Two derivation policies share that fact without sharing rules: the **ingress upstream** derives from `exposureMode` (`direct` loops back and is validated edge-local; every tailnet mode dials the provider by FQDN even when colocated, because origin sockets and serve fronts are tailnet-bound — confirmed against live listeners, which showed the fronts on the tailnet IP only), while a private service's **machine-to-machine `endpoint`** resolves against the evaluating host and loops back when colocated with its provider. Identity (public URLs, OIDC endpoints, TLS server names) never derives.

Rejected: a locality rule for ingress upstreams — it would break the colocated cockpit route (its bespoke front is a tailnet listener) and contradict the route's own declared exposure. Rejected: one universal resolver for both consumers — the edge dials by exposure semantics, services dial by locality; forcing one rule would encode the other's policy into a shared helper (D-064 records this split).

## Risks

- **Serve configuration is node-local state, not declarative Nix.** The unit reconciles it on start and clears it on stop; the tailnet's ACLs still decide who may reach the front.
- **The edge verifies the tailnet certificate** against public roots. That is the point of D3 — verification stays on for this hop, unlike the loopback hop behind it.
- **Cutover is three ordered steps** (deploy LA, deploy OCI, flip the record). Public behaviour changes only in the last step, which is reversible alone.
