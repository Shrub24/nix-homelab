## Context

This design follows the grill/discovery outcome rather than treating the earlier draft implementation as accepted. The user wants AudioMuseAI added through the proper OpenSpec flow, with enough questioning to clarify whether this is a minimum feature, a long-lived service, and/or a broader music-stack cleanup. The clarified target is: AudioMuseAI as a Navidrome extension, a proper long-lived service, and a mechanical regrouping of music service modules under `modules/services/music/` in one combined change.

The current music stack is composed from `applications.music`, which already owns shared media paths, secret-file input, and service composition for Syncthing, Navidrome, Beets, Tagr, optional SoulSync, and slskd. Navidrome is the user-facing music server; AudioMuse should extend that listening experience rather than become a separate first-class app in the topology.

AudioMuseAI is not a Navidrome flag. It has two independently managed pieces:
- a core service made of Flask, a worker, and Redis (PostgreSQL is provided by the existing shared instance)
- a Navidrome WASM plugin (`pkgs.navidromePlugins.audiomuseai`) that proxies similarity requests to the core API

The repo already has an exposure model involving Caddy/Cloudflare mTLS/Tailscale upstreams. This change should not redesign that model. AudioMuse should be internal-service-first: primarily there to serve the Navidrome plugin and operator bootstrap path, not to introduce a new public surface unless existing exposure policy explicitly composes one later.

## Goals / Non-Goals

**Goals:**
- Add AudioMuseAI as an explicit optional feature under `applications.music`.
- Make the repo own service topology, images, plugin package inclusion (`pkgs.navidromePlugins.audiomuseai`), Navidrome runtime flags, secret contracts, and durable-state backup policy where practical.
- Preserve deployability before first-run bootstrap is complete while making incomplete state obvious in docs/tasks.
- Mechanically move music-owned service modules under `modules/services/music/` without changing option namespaces.
- Require deployment plus real Symfonium similar/radio validation as the end-to-end acceptance proof.

**Non-Goals:**
- Redesign the public/private exposure model.
- Rename options from `services.navidrome`, `services.beets`, etc. to a new `services.music.*` namespace.
- Manually decrypt or edit encrypted SOPS secret payloads.
- Make Redis/temp files canonical backup state unless implementation evidence requires it.
- Pre-seed brittle Navidrome database/plugin state if the plugin does not expose a stable declarative interface.

## Decisions

### AM-1: AudioMuse is an optional Navidrome extension, not a standalone app surface

**Chosen:** expose AudioMuse through an explicit music application toggle such as `applications.music.audiomuse.enable`, with Navidrome plugin wiring enabled from the same composition path.

**Rationale:** The user-facing goal is Symfonium/Navidrome similar/radio behavior. AudioMuse is a supporting music-intelligence service and should not become a host-level concern or an always-on default for every music deployment.

**Alternative considered:** enable AudioMuse automatically whenever `applications.music.enable = true`. Rejected because deployable-but-incomplete bootstrap is acceptable, but operators should opt into that incomplete state intentionally.

### AM-2: Repo-owned foundation, documented manual finish

**Chosen:** manage images, service topology, SOPS bootstrap secrets, plugin package inclusion (`pkgs.navidromePlugins.audiomuseai`), and Navidrome runtime flags declaratively. Document remaining AudioMuse setup wizard and Navidrome plugin UI configuration as operator steps.

**Rationale:** Upstream AudioMuse persists much of its setup in application state. Navidrome plugin configuration may also live in Navidrome-managed state. Declarative state injection is only worth pursuing if upstream exposes a stable, reproducible interface.

**Alternative considered:** force full declarative setup by seeding application/plugin state. Rejected for the initial proposal because it is high-risk and not necessary to get the end-to-end feature working.

### AM-3: Music service regrouping is file-layout-only

**Chosen:** move music-owned service modules under `modules/services/music/` and update imports, while preserving existing option paths such as `services.navidrome`, `services.beets`, and `services.slskd`.

**Rationale:** The user wants the repo layout to reflect that the music stack is now substantial. A file move improves navigability without multiplying risk through option namespace migration.

**Alternative considered:** introduce `services.music.*` options. Rejected for this change because it combines a behavior feature with a public option migration.

### AM-4: Handle Syncthing reuse explicitly during the regroup

**Chosen:** verify all Syncthing module imports before moving it. If Syncthing is used outside `applications.music`, either leave a compatibility wrapper at the old path or keep only music-specific Syncthing composition under the music subtree while preserving shared import compatibility.

**Rationale:** The user asked for one coherent music subtree, but Syncthing may be a reusable service beyond music. The implementation should not break non-music reuse just to satisfy a cosmetic move.

**Alternative considered:** blindly move all services and fix only current evaluation errors. Rejected because it risks hidden future breakage and weakens the repo's reusable service boundary.

### AM-5: Enroll AudioMuse into shared PostgreSQL for durable state

**Chosen:** connect AudioMuse to the existing `services.postgres-shared` instance via TCP with `audiomuse/postgres_password` secret auth. Redis and temp audio working data are not included in the primary backup contract unless implementation validation shows they hold required recovery state.

**Rationale:** The user explicitly selected “Back up only critical DB state.” Using shared Postgres removes an entire embedded container image, a dedicated data volume, a separate Podman network dependency, and a distinct backup path — while keeping backup scope meaningful. Current AudioMuse state is disposable; no migration, dump, or restore work is needed. A dedicated `audiomuse/postgres_password` secret handles TCP auth from the Podman container to the host Postgres instance.

**Alternative considered:** persist/back up every container volume initially. Rejected because it hides which state is actually restorable and increases backup churn.

**Alternative considered:** keep an embedded Postgres container alongside AudioMuse. Rejected because the shared Postgres instance already exists for paperless/niks3; adding one more tenant is lower complexity than managing a separate Postgres container lifecycle.

## Risks / Trade-offs

- [Mechanical move creates noisy diffs] -> Keep it in the same change because the user requested it, but avoid option namespace changes and document the move clearly.
- [Syncthing may be shared beyond music] -> audit import graph and preserve compatibility if non-music consumers exist.
- [AudioMuse can deploy before it works end-to-end] -> require operator docs and tasks that distinguish “deployed” from “Symfonium validated.”
- [Plugin config remains partially manual] -> make repo-owned pieces declarative and document the exact manual UI/config finish.
- [OCI images may be stale or not ARM-safe] -> revalidate current upstream OCI image references before implementation and run host-targeted evaluation/build checks. (The Navidrome plugin comes from `pkgs.navidromePlugins.audiomuseai` — nixpkgs handles freshness and architecture; no separate pinned asset or digest check needed.)
- [Shared-Postgres enrollment requires `audiomuse/postgres_password` secret and TCP auth wiring] -> add the password secret and configure shared Postgres authentication before the AudioMuse container can connect. Current state is disposable, so no migration fallback is required if enrollment is misconfigured.
- [Draft implementation may bias the final design] -> treat it as reference only; reconcile or replace it during implementation after this proposal is accepted.

## Migration Plan

1. Finalize this OpenSpec proposal/design/tasks with the user before implementation.
2. Reconcile the existing draft files against the accepted plan rather than assuming they are correct.
3. Perform the mechanical service rehome and update imports/docs.
4. Enroll AudioMuse into shared PostgreSQL, implement the explicit AudioMuse toggle, service module (using shared Postgres instead of an embedded container), Navidrome plugin wiring, secret template updates, OCI refs, and shared-Postgres backup coverage.
5. Run formatting, strict OpenSpec validation, flake checks, and host-targeted evaluation/build checks.
6. Deploy to `oci-melb-1`, complete AudioMuse and Navidrome plugin setup, and validate actual Symfonium similar/radio behavior.

Rollback: disable the AudioMuse feature toggle and Navidrome plugin wiring while keeping the mechanical file rehome. If the rehome causes unexpected import issues, restore old import paths or retain compatibility wrappers until callers are updated.

## Open Questions

- Exact route/access path for AudioMuse operator bootstrap should follow current exposure policy; do not invent new public exposure in this change.
- Verify whether current Navidrome exposes a stable plugin configuration import/export path before settling for UI-only plugin config.
