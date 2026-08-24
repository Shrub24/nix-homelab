# Tasks

## 1. Bump Kanidm package pins to 1.11

- [x] Bump `services.kanidm.package` from `pkgs.kanidmWithSecretProvisioning_1_10` to `pkgs.kanidmWithSecretProvisioning_1_11` in `modules/services/admin/kanidm.nix` (~line 419)
- [x] Bump `environment.systemPackages` from `pkgs.kanidm_1_10` to `pkgs.kanidm_1_11` in `modules/services/admin/kanidm.nix` (~line 458)
- [x] Bump host-auth default from `pkgs.kanidm_1_10` to `pkgs.kanidm_1_11` in `modules/shared/kanidm-host-auth.nix` (~line 28)
- [x] Verify evaluation: `nix eval --impure '.#nixosConfigurations.la-admin-1.config.services.kanidm.package.version'` prints `1.11.0`

refs: proposal.md What Changes; specs/kanidm-identity/spec.md ADDED Requirement 1
criteria: All three pins reference `_1_11`; eval of the la-admin-1 config resolves the package version to `1.11.0`
verify: `nix eval --impure --raw '.#nixosConfigurations.la-admin-1.config.services.kanidm.package.version'`
delegate: CoderAgent

## 2. Remove the v1.10.4 revoked-OAuth-session exception from the restore helper

- [x] Delete the `revoked_oauth_exception_ok` function and its comment block from `modules/services/admin/kanidm.nix`
- [x] Delete the `index_log` / `entry_log` fixture handling and `db-scan` proof branches from the verify gate
- [x] Remove the exception branch (verify_rc != 0 but exception accepted) so every nonzero verify is fatal with output surfaced
- [x] Update the helper's header comment: no version-pinned exception, fail-closed only
- [x] Ensure `kanidm_restore_cleanup` trap, chown, and manual-start message remain intact on the clean path

refs: proposal.md What Changes; specs/kanidm-identity/spec.md ADDED Requirement 2
criteria: The rendered restore script contains no `revoked_oauth_exception_ok`, no `RefintNotUpheld`, no `db-scan` proofs; any nonzero verify exits fatal
verify: `./tests/kanidm-restore-contract.sh` (after task 3)
delegate: CoderAgent
notes: This is a change to the Kanidm restore/verify helper — requires independent fail-closed/security review plus real-binary CLI contract validation per project rule before deployment.

## 3. Update restore contract tests to the fail-closed shape

- [x] In `tests/kanidm-restore-contract.sh`: remove `accept_scenario`, `predicate_reject_scenario` helpers and the `refintonly`, `refintwithroutine`, `wrongversion`, `wrongfinding`, `refintsameline`, `wrongindexentry`, `wrongrsuuid`, `wrongstate`, `missingindex`, `missingentry`, `indexscanfail`, `entryscanfail`, `wrongprefix`, `missingoauthattr`, `extraindexid`, `extrasession`, `extraoauth2line` scenarios
- [x] Keep: clean, cleanwitherror, nofinding, failedplain, refintwitherror (as fatal), strayerr, errormarkers, cleanupfailure scenarios — all reject paths
- [x] Update the `make_stub` kanidmd stub: no `version`/`list-index`/`get-id2entry` subcommands needed; `verify` exits per scenario
- [x] Update the real-binary CLI contract section: `kanidmd version` must print `kanidmd 1.11.0`; drop `db-scan` shape assertions
- [x] Update header comments referencing the v1.10.4 pinned binary

refs: proposal.md Impact
criteria: Test runs green; no 1.10.4/319/UUID/IDLBitRange references remain in the test file except historical comments
verify: `./tests/kanidm-restore-contract.sh`
delegate: CoderAgent

## 4. Update la-admin-1 phase contract test

- [x] In `tests/phase-la-admin-contract.sh`: update the restore-helper source contract block (comment + grep list) to require fail-closed behavior with no `RefintNotUpheld(319)`, no `kanidmd 1.10.4`, no `db-scan` proof tokens, no `05e3c021-*` UUID
- [x] Keep the negative greps: no `db-scan quarantine`, no `database repair`, no `|| true`

refs: proposal.md Impact
criteria: Contract test passes with the new module source; old 1.10.4/319 greps replaced by absence checks
verify: `./tests/phase-la-admin-contract.sh`
delegate: CoderAgent

## 5. Update migration runbook and migrate-change delta spec

- [x] In `docs/runbooks/admin-host-migration.md`: note the 1.10.4 exception applied only to the migration restore and was removed with the 1.11 upgrade (helper is now fail-closed)
- [x] In `openspec/changes/migrate-admin-host-to-la/specs/kanidm-identity/spec.md`: mark the v1.10.4 exception requirement as superseded/removed so archiving that change cannot resurrect the exception contract

refs: proposal.md What Changes
criteria: Runbook states the exception is removed; migrate delta spec no longer mandates the exception
verify: grep for `1.10.4` in `docs/runbooks/admin-host-migration.md` and `openspec/changes/migrate-admin-host-to-la/specs/kanidm-identity/spec.md` returns only historical/superseded references
delegate: DocWriter

## 6. Review gate for the restore helper change

- [x] Independent fail-closed/security review of the modified restore helper (CodeReviewer): no acceptance path remains, no `|| true`, no unguarded scan, cleanup trap intact, chown gated on clean verify
- [x] Real-binary CLI contract validation: `kanidmd version` prints `kanidmd 1.11.0`, `database verify` passes on a scratch DB (covered by `tests/kanidm-restore-contract.sh` real-binary section once kanidm 1.11 is built)

refs: proposal.md; project rule: changes to the Kanidm restore/verify helper require independent fail-closed/security review plus real-binary CLI contract validation
criteria: Reviewer approves; real-binary contract passes with kanidmd 1.11.0
verify: CodeReviewer sign-off + `./tests/kanidm-restore-contract.sh` with `KANIDMD` built
delegate: CodeReviewer

## 7. Full validation and handoff

- [x] `treefmt --fail-on-change` clean
- [x] `./tests/kanidm-restore-contract.sh` green
- [x] `./tests/phase-la-admin-contract.sh` green
- [x] (with caveat) `nix flake check` (or at minimum the affected checks) passes
- [x] `openspec validate --strict` passes
- [x] Summarize deploy precondition: fresh backup exists on la-admin-1 before `just deploy la-admin-1`; upgrade is one-way

refs: proposal.md Impact
criteria: All listed validations green
verify: run each command
delegate: BuildAgent
