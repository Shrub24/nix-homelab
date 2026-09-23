## 1. Stage 6 baseline and placement inventory

- [x] 1.1 Capture a clean baseline from the exact completed Stage 6 JJ change before implementation; record its change/commit IDs, clean detached path, all three host drvPaths and structured observables, realize the LA and home-forge outputs, and verify every baseline host toplevel evaluates plus OCI's derivation is introspectable without requiring privileged binfmt changes or an unavailable aarch64 builder.
- [x] 1.2 Inventory every direct host import, product enable, option override, secret binding, application/provider line, and current placement consumer; map each item to exactly one Stage 7 aspect owner or retained host fact, and verify no implementation block is unowned before moving files.
- [x] 1.3 Re-pin the current protected bodies overlapped by `open-webui`, `omniroute-home-forge`, `navidrome-m3u-itunes-worker`, and `traktor-m3u-sync-worker`; verify their scripts, units, timers, inputs, and behavior hashes are recorded before edits.

## 2. Platform, edge, Cockpit, and push placement

- [x] 2.1 Add the discovered `oci` contributor, relocate `modules/providers/oci/default.nix` beside its owner, select it only on `oci-melb-1`, and verify OCI serial-console/GRUB behavior is equal while LA and forge remain inert.
- [x] 2.2 Add the discovered `edge` contributor, relocate the edge application/proxy implementation beside it, preserve `applications.edge-ingress.*`, and verify OCI origin plus LA edge routes, AOP, ACME, trusted proxies, secrets, and Caddy units are equal.
- [x] 2.3 Add the discovered `cockpit` contributor selected on OCI and LA, move common service-user secret/default ownership into the concern, preserve only genuine host variants, and verify both Cockpit configurations and secret metadata are equal.
- [x] 2.4 Add the discovered `push-server` contributor selected only on LA, make selection provide ntfy server enablement, and verify ntfy auth, ACL, Firebase, routes, templates, units, and notification-daemon integration are equal.

## 3. Admin placement split

- [x] 3.1 Extract the discovered `identity-provider` concern from the current admin composition, owning Kanidm server/provisioning/OIDC provider wiring without importing `identity-client`; select it only on LA and verify Kanidm services, secrets, certificates, URLs, and provisioning are equal.
- [x] 3.2 Add the discovered `admin-hub` concern for shared admin-root/SSH wiring and the coupled Termix, Vaultwarden, Homepage, Gatus, Beszel hub, Webhook, and current Quantum policy; select it only on LA and verify every admin service, route, secret, backup, ACL, and Tailscale-serve observable is equal.
- [x] 3.3 Remove obsolete host-only admin enable/projection overlays after their values move to the owning concerns, retaining genuine LA/OCI variants only; verify no public option namespace or security-relevant override changes.

## 4. OCI and home-forge product placement

- [x] 4.1 Add discovered `paperless` and `postgres` contributors selected only on OCI; make selection supply current top-level enablement while preserving GPT/docling and role variants, and verify Paperless/Postgres units, databases, secrets, backups, and OIDC wiring are equal.
- [x] 4.2 Add discovered `ai-gateway`, `karakeep`, `niks3-cache`, and `phoenix` contributors selected only on OCI; preserve current variants and verify services, routes, secrets, container images, firewall behavior, and backups are equal.
- [x] 4.3 Add the discovered `omniroute` contributor selected only on home-forge, preserve the two-step secret-existence gate and monitor integration, and verify OmniRoute service/container/secret/monitor observables are equal.
- [x] 4.4 Relocate DJ implementation files beside the existing `dj` concern without changing its public aspect, music contract, or protected playlist/Traktor behavior; verify protected hashes and all DJ/VM observables are equal.

## 5. Host cleanup and root evacuation

- [x] 5.1 Update exact per-host aspect selections in `modules/flake/registry.nix`; remove every direct application/provider/workload-service import and redundant top-level enable from host files while retaining machine facts and genuine variants, then evaluate all three host drvPaths.
- [x] 5.2 Reconcile every file under `modules/applications/` and `modules/providers/` to its new owner, delete both evacuated roots with no compatibility wrappers, and verify exhaustive references find no stale imports or replacement evaluator-class roots.
- [x] 5.3 Shrink `modules/flake/_unconverted-nixos-dirs.nix` from four entries to exactly `hosts` and `services` only after root evacuation, and verify import-tree discovery evaluates without either removed exclusion.

## 6. Architectural ratchet tests

- [x] 6.1 Update `tests/check-dendritic-scaffold-contract.sh` for the exact Stage 7 publication set, per-host selection matrix, owner/private imports, deleted roots, two-entry filter, and preserved observables; run it and verify semantic set/value checks pass.
- [x] 6.2 Add full-toplevel throwaway mutations that detect missing/extra placement, direct host implementation imports, discovery-driven activation, private-leaf publication, reintroduced compatibility roots, and filter widening; verify every mutation fails or succeeds for its intended reason and leaves the working tree untouched.
- [x] 6.3 Add a future-work guard that forbids growth of the `hosts`/`services` transitional boundary and direct host-to-workload imports while allowing private host-local disk/hardware fragments; verify representative negative mutations are caught.

## 7. Documentation and superseded cleanup mapping

- [x] 7.1 Record D-053 and update `ARCHITECTURE.md`, `STRUCTURE.md`, `CONVENTIONS.md`, and current `docs/` architecture/plan/history/transition analysis for the complete placement aspect surface, deleted roots, exact two-entry filter, and Stage 8 stopping plan; verify all paths match the implemented tree.
- [x] 7.2 Map the surviving edge, Cockpit, conventional-default, topology, CI, ntfy, OIDC, adopted-host, and test-hygiene findings from `normalize-fleet-boundaries`: mark what Stage 7 absorbed and explicitly defer the rest to Stage 8 or independent product changes without editing its historical task checkboxes; verify no unrelated active change artifact is rewritten.

## 8. Validation, equivalence, and review

- [x] 8.1 Run focused host drvPath evaluation after each structural group, then run `bash tests/check-dendritic-scaffold-contract.sh`, `treefmt --fail-on-change`, `just checks all`, `nix flake check --no-build`, and all three host drvPath evaluations; record exact statuses and fix only in-scope failures.
- [x] 8.2 Compare final structured observables against the exact clean Stage 6 baseline, run literal built-output `nix store diff-closures` for LA and home-forge, and compare OCI drvPath/derivation data plus structured observables (adding a literal OCI closure diff only if an aarch64 builder is available); classify every delta, with any unexplained runtime, route, secret, permission, unit, package, backup, provider, worker, or topology difference blocking completion.
- [x] 8.3 Obtain independent review for aspect boundaries, evaluation cycles, secret safety, behavior equivalence, active-change overlap, rollback, and strict scope; run `openspec validate dendritic-stage-7-placement-aspects --strict`, reconcile all task checkboxes to evidence, and leave the change undeployed and unarchived.
