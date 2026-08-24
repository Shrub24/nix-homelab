## Context

See proposal.md — Why. Current state: kanidm 1.10.5 is deployed on la-admin-1 (domain level 14, upgrade-check PASS to level 15); the repo pins `kanidmWithSecretProvisioning_1_10` / `kanidm_1_10`; the `kanidm-restore@` helper carries a version-pinned v1.10.4 revoked-OAuth-session acceptance predicate that is already unreachable (deployed binary is 1.10.5, predicate requires exactly `kanidmd 1.10.4`) and stays dead on 1.11.

## Goals / Non-Goals

**Goals:**
- Move the repo and la-admin-1 onto the supported kanidm 1.11 line before the 1.10 EOL on 2026-08-31.
- Remove the migration-only v1.10.4 acceptance predicate so the restore helper is unconditionally fail-closed.
- Keep the fail-closed contract tests green with the 1.11 binary shape.

**Non-Goals:**
- No DB schema migration work (upgrade-check PASS covers it; the server applies level 15 on first start).
- No change to the declarative provisioning, OIDC client topology, or secret contracts.
- No deploy of la-admin-1 itself (operator action, gated on a fresh backup).

## Decisions

### D-1: Bump the package pins, not the nixpkgs baseline

Switch `services.kanidm.package` to `pkgs.kanidmWithSecretProvisioning_1_11`, `environment.systemPackages` and the host-auth `mkDefault` to `pkgs.kanidm_1_11`. Locked nixpkgs already carries 1.11.0, so no flake input change is needed.

*Alternatives:* introducing a custom overlay — rejected, unnecessary surface; upstream nixpkgs aliases are the repo pattern.

### D-2: Delete the v1.10.4 exception predicate instead of re-pinning it to 1.11

The predicate (`revoked_oauth_exception_ok` + `db-scan` proofs) exists for one proven migration artifact. It cannot fire on 1.11 and would require re-proving the false-positive shape against the new binary to keep it meaningful — a cost with no operational payoff. Removing it restores the intended fail-closed posture (any nonzero verify is fatal; only exit 0 + `Verification passed` + zero error-bearing lines passes).

*Alternatives:* re-pinning the predicate to 1.11 — rejected: the trigger condition was a one-time migration data artifact, not a class of 1.11 behavior; keeping dead acceptance code on a security gate is worse than removing it.

### D-3: Rewrite the contract tests around fail-closed-only scenarios

Keep the clean/clean-with-error/setup-mismatch/plain-failure/cleanup-failure scenarios; delete the acceptance and predicate-rejection scenario families (they test code being removed). The real-binary section re-pins to `kanidmd 1.11.0` and drops the `db-scan` shape assertions (no longer referenced by the helper). The la-admin-1 phase contract flips from "must contain the predicate" greps to "must not contain acceptance tokens" greps.

### D-4: Prevent archive resurrection of the exception contract

The unarchived `migrate-admin-host-to-la` change's `kanidm-identity` delta spec mandates the v1.10.4 exception. If that change archives after this one, the requirement re-enters the canonical spec. Amend its delta spec to mark the exception requirement superseded/removed so archive order cannot resurrect it.

## Risks / Trade-offs

- [One-way upgrade: downgrade after switching to 1.11 is not possible] → Operator gate: confirm a fresh portable backup exists in `/var/lib/kanidm/backups` before `just deploy la-admin-1`; rollback is restore-from-backup, not package revert.
- [First 1.11 start applies domain level 15 migration; failure leaves the DB at an in-between state] → The server runs the migration transactionally; if it fails, restore the pre-upgrade backup while still on 1.10 binary, and re-run after diagnosing (upgrade-check must PASS again).
- [Contract tests drift from real 1.11 output shapes] → The real-binary section runs `kanidmd version` (must print `kanidmd 1.11.0`) and `database verify` against a scratch DB; stub scenarios model only error-bearing markers, which are the fail-closed-relevant shapes.
- [Helper change is security-relevant] → Independent CodeReviewer pass (task 6) before sign-off; the helper gains no new paths, only loses one.
- [Multi-host: host-auth hosts (do-admin-1, oci-melb-1) also get the 1.11 client package] → Client-only impact; kanidm client is backward compatible with the 1.10 server, and both hosts are consumers of the la-admin-1 server.
