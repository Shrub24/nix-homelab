# kanidm-1-11-upgrade

## Why

Kanidm 1.10 reaches end-of-life on 2026-08-31. The locked nixpkgs already carries the next supported line (`kanidm_1_11` / `kanidmWithSecretProvisioning_1_11`, 1.11.0), and `kanidmd domain upgrade-check` on `la-admin-1` passes (domain level 14 → 15), so the upgrade path is clear and gated. Separately, the 1.10.4 revoked-OAuth-session exception in the `kanidm-restore@` helper is dead residue: the deployed binary is already 1.10.5, the helper version-pins acceptance to exactly `kanidmd 1.10.4`, and on 1.11 it can never fire. It exists solely as migration evidence from the DO→LA cutover and should be removed so the helper is fail-closed with no acceptance path, as intended.

## Core Value

Stay on a supported Kanidm line before EOL and remove the version-pinned migration exception so restore verification is unconditionally fail-closed.

## What Changes

- Bump `services.kanidm.package` to `pkgs.kanidmWithSecretProvisioning_1_11` and `environment.systemPackages` / host-auth default to `pkgs.kanidm_1_11` in `modules/services/admin/kanidm.nix` and `modules/shared/kanidm-host-auth.nix`.
- Remove the `revoked_oauth_exception_ok` predicate (version pin, `RefintNotUpheld(319)` acceptance, `db-scan` proofs) and its branch from the `kanidm-restore@` script; every nonzero offline verification result becomes fatal with no exception path.
- Update `tests/kanidm-restore-contract.sh` to drop the exception acceptance and predicate-rejection scenarios, keep the fail-closed gate coverage, and pin the real-binary CLI contract to `kanidmd 1.11.0`.
- Update `tests/phase-la-admin-contract.sh` source contract to require a fail-closed helper with no version-pinned acceptance tokens.
- Update `docs/runbooks/admin-host-migration.md` to note the 1.10.4 exception applied only to the migration restore and was removed with the 1.11 upgrade.
- Amend the unarchived `migrate-admin-host-to-la` change's `kanidm-identity` delta spec so the archived exception requirement cannot be resurrected on archive.

## Impact

- `modules/services/admin/kanidm.nix`, `modules/shared/kanidm-host-auth.nix`, `tests/kanidm-restore-contract.sh`, `tests/phase-la-admin-contract.sh`, `docs/runbooks/admin-host-migration.md`, `openspec/changes/migrate-admin-host-to-la/specs/kanidm-identity/spec.md`.
- Deployment: `la-admin-1` must be rebuilt with the 1.11 package after a fresh backup exists; the upgrade is one-way.
- The `kanidm-restore@` helper becomes strictly fail-closed (no `RefintNotUpheld` acceptance), matching the intended end state.
