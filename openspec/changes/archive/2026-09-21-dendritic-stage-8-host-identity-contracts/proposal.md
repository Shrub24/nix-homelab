## Why

Host identity is currently restated across the typed registry, deploy metadata, web policy, and cross-host endpoint literals. Stage 8 should finish host discovery while establishing one canonical identity authority and only the two demonstrated private transport contracts: shared PostgreSQL and Niks3 writes.

**Core Value:** Hosts declare stable identity once, and placement, deployment, routing, and internal consumers reference that identity without creating a universal topology framework.

## What Changes

- Convert each `modules/hosts/<host>/default.nix` into a recursively discovered flake-parts contributor that registers its own typed host record and NixOS composition.
- Reduce `modules/flake/registry.nix` to generic schema/materialization with no concrete host names; make host-private NixOS fragments undiscovered private paths.
- Establish canonical typed host identities containing stable host ID, target system, and Tailscale identity; derive `networking.hostName` and Tailscale FQDNs from that record.
- Make deployment metadata and web-policy physical host references validate against canonical host IDs instead of restating identity.
- Add narrow typed internal contracts for PostgreSQL and the private Niks3 write API; consumers resolve endpoint data from these contracts, while cache reads and identity/ntfy URLs remain on the existing web catalog.
- Assert that each contract provider is a known host selecting the matching provider aspect.
- Move settled contributors into semantic feature/domain source paths as they are touched; keep `modules/flake/` for genuine output/materialization concerns and leave unconverted service leaves behind the remaining discovery boundary.

## Capabilities

### New Capabilities

- `internal-service-contracts`: Typed PostgreSQL and Niks3-write provider/endpoint contracts keyed by canonical host identity.

### Modified Capabilities

- `fleet-infrastructure`: Make discovered host contributors and canonical host identities the authority used by host composition and physical metadata.
- `feature-topology`: Separate feature-oriented source ownership from deployment aspect composition and permit recursively discovered contributors outside a flat flake directory.
- `repository-structure`: Remove the host discovery exception and reserve `modules/flake/` for flake/output materialization concerns.
- `postgres-shared-access`: Make cross-host PostgreSQL consumers resolve the provider endpoint through the internal contract.
- `sovereign-binary-cache`: Separate the stable public read identity from the private Niks3 write transport contract.

## Impact

- Affects host contributors, generic registry/materializer, deploy metadata, web-policy host references, AudioMuse PostgreSQL wiring, Niks3 upload clients, source paths, checks, and architecture docs.
- Existing flake output names, deployment targets, Tailscale names, systems, URLs, ports, and service placement remain unchanged.
- Does not add internal DNS, infer placement from module evaluation, or create a universal service graph.
- Depends on the identity/admin boundary being directional before the host registry becomes the next architectural template.
