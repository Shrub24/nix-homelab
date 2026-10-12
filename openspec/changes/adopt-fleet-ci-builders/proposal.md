# Proposal

## Why

The fleet inventory and CI artifacts are already consumed, but builders have no dedicated dispatch account and the workflows still depend on the legacy nixbuild.net setup. Adopt nix-fleet's complete build/cache contract so CI can build across architectures and publish signed substitutes without duplicating its machinery here.

**Core Value:** reproducible fleet builds, explicit builder access, and cached routine deployments through one upstream contract.

## What Changes

- Select a local `build-account` convention contributor on home-forge, oci-melb-1 and la-admin-1, importing nix-fleet's account mechanism and authorizing its canonical coordinator public key. Verify the account can use the remote Nix store, not merely log in.
- Keep `builder-access` as the canonical SSH trust projection. Consume the upstream `ci` profile unchanged, including LA's lower scheduling weight; do not restate inventory or profiles.
- Adopt the reusable build/cache workflow at the same immutable revision as the flake input: one coordinator job whose architecture and target systems are selected by input, with local builds always publishing through the niks3 action over GitHub OIDC and remote builds through builder hooks. Consume its metadata packages, Tailscale federation and authorization contract. Build all three deploy profiles and verify both publication paths and signed cache substitution.
- Keep distributed scheduling on CI runners. Upstream does not enable host-daemon `nix.buildMachines`; adopting its defaults leaves that option empty on the hosts. Builder accounts accept inbound jobs independently of outbound scheduling.
- Validate pull requests without privileged fleet access. Publish on main and manual main dispatch after validation; do not widen the existing main-only cache claim policy.
- **BREAKING:** remove legacy nixbuild CI/prebuild setup and obsolete prebuild recipes. Retain deploy-rs, manual deployment, fail-fast serial ordering and its separate deployment authorization boundary. Do not turn the build coordinator key into a deployment key.
- Keep the flake pin and the workflow revision aligned at one immutable revision. The intended pin is `6c26cce9fd2f898bfcf8e41fcc94c5ee791ddc0b` (the "unify CI builds with configurable architecture and action-owned publication" contract); the index is staged to it so `.#` evaluates the same contract, and no other lock node moves.

### Constraints

No manual secret edits or decryption; private coordinator-key provisioning remains operator-owned. No source changes in nix-fleet, no new metered builder, no public builder access, no automatic deployments, and no change to telemetry placement or mutable service state. Cache signing, retention and host publication credentials remain intact.

## Capabilities

### New Capabilities

- `fleet-build-plane`: canonical builder accounts, trust, profiles, CI validation/build/publication and the separate deployment boundary.

### Modified Capabilities

- `nixbuild-build-plane`: retire its five legacy requirements in favor of `fleet-build-plane`, preserving shared substitutes and manual serial deployment in the replacement.
- `fleet-infrastructure`: derive the substitute baseline from nix-fleet rather than prescribe legacy provider ordering.
- `cache-push-workflow`: distinguish CI/post-build publication from the activation-triggered publication path; a failed activation must not trigger the latter.
- `sovereign-binary-cache`: replace the CI-push prohibition and old post-build-hook suppression with scoped OIDC CI publication and builder-owned post-build uploads; align reads with the existing public HTTPS cache backed by R2, without giving readers write credentials.

## Impact

`modules/flake/builder-access.nix`, a new `modules/flake/build-account.nix`, the three host records, existing cache-publisher and niks3 policy, `.github/workflows/{ci,deploy,deploy-host}.yml`, removal of `.github/actions/setup-nixbuild/`, `justfile`, related checks and operator documentation. The flake/workflow revision pair must be reconciled before mutation. Existing cache, infrastructure and operations specs supply the retained signing, recoverability, formatting and deployment constraints.
