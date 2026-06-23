## Why

Navidrome and Symfonium now have a useful similarity/radio path, but this repo does not yet have the AudioMuseAI service and Navidrome plugin wiring needed to make that experience work end-to-end. At the same time, the music stack has grown enough that the flat `modules/services/*.nix` layout obscures ownership; this change should introduce AudioMuse as a Navidrome-facing music-stack extension while mechanically regrouping music services under a coherent service subtree.

**Core Value:** make the listening experience richer without sacrificing the repo's host-thin, service-owned, reproducible NixOS fleet model.

Key constraints for this change:
- Preserve `applications.music` as the composition root and keep host files thin.
- Move files under `modules/services/music/` without changing public Nix option namespaces unless a compatibility fix requires it.
- Reuse the existing music host secret source; do not manually decrypt or edit encrypted secrets.
- **Use nixpkgs-native plugin wiring (`pkgs.navidromePlugins.audiomuseai`) instead of manual `.ndp` asset fetch/install** — no pinned plugin-URL or asset-fetch logic in repo code.
- Keep AudioMuse deployable before first-run UI/plugin bootstrap is complete, but make the remaining operator work explicit.
- AudioMuse connects to the existing shared PostgreSQL instance (`services.postgres-shared`) instead of running an embedded Postgres container. Current AudioMuse state is disposable — no migration or data-preservation work is needed; the service can be recreated from scratch.
- Do not promote Redis/temp state to canonical backup scope unless evidence requires it; shared-Postgres coverage handles durable state.
- Service restart on env/config-file changes follows repo patterns — do not introduce unique restart mechanisms for AudioMuse.
- **Do NOT bump Navidrome to 0.62.0**; defer that until nixpkgs unstable carries it natively.

## What Changes

- Add AudioMuseAI as an explicit, optional feature of `applications.music` that acts as a Navidrome extension for Symfonium similar/radio behavior.
- Add a service-owned AudioMuse module for the core service topology, images, SOPS-backed bootstrap secrets, and shared-Postgres durability.
- Extend Navidrome's music service module to include the AudioMuse plugin via `pkgs.navidromePlugins.audiomuseai` and set declarative runtime flags; leave only unavoidable plugin/UI setup as documented operator work.
- Mechanically regroup music service modules under `modules/services/music/` while preserving existing option names such as `services.navidrome`, `services.beets`, `services.slskd`, etc.
- Update the music secret template and operator docs/runbooks so deployment, first-run bootstrap, plugin setup, backup expectations, and Symfonium E2E validation are explicit.

## Capabilities

### New Capabilities
- `audiomuse-navidrome-similarity`: AudioMuseAI-backed Navidrome similarity integration for Symfonium radio/similar-track behavior.

### Modified Capabilities
- `media-services`: The music application composition expands to include an explicit AudioMuse feature and a coherent music-service module subtree.
- `feature-topology`: Application composition remains the topology signal while leaf service files may be grouped by feature domain without changing option namespaces.
- `repository-structure`: Repository layout documents the `modules/services/music/` subtree for music-owned leaf services.
- `state-backups`: AudioMuse backup policy relies on shared-Postgres coverage for durable state, keeping Redis/temp working data outside canonical backup scope.
- `operations`: Operator workflows cover deployment, first-run setup, Navidrome plugin configuration, and real Symfonium E2E validation.

## Impact

- Affected code: `modules/applications/music/default.nix`, music service modules under `modules/services/`, `policy/oci-images.nix`, music secret template, and relevant docs/runbooks.
- Affected specs/docs: `media-services`, `feature-topology`, `repository-structure`, `state-backups`, `operations`, `docs/architecture.md`, `docs/decisions.md`, and operator workflow documentation.
- External dependencies: AudioMuseAI container image, Redis 7 image, and the AudioMuse Navidrome plugin via `pkgs.navidromePlugins.audiomuseai`. (PostgreSQL is provided by the existing `services.postgres-shared` module, not as a new dependency.)
- Operational impact: deployment must be followed by AudioMuse first-run setup, Navidrome plugin configuration, and real Symfonium validation before the feature is accepted as working.
