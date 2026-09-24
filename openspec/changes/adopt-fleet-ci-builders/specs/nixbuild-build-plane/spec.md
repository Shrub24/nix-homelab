# Spec Delta

## REMOVED Requirements

### Requirement: CI builds SHALL use nixbuild.net as the primary remote build plane

**Reason:** canonical fleet CI now supplies architecture-aware builders and cache publication without selecting the metered nixbuild.net build path.

**Migration:** use `fleet-build-plane` FB-1, FB-3 and FB-4; remove legacy workflow setup and prebuild credentials. The external builder remains available only through an explicitly selected upstream profile.

### Requirement: Shared substituter contract SHALL be available for active hosts

**Reason:** provider ordering is owned by nix-fleet's baseline rather than this legacy provider-specific spec.

**Migration:** preserve shared substitute consumption through `fleet-build-plane` FB-8 and the updated `fleet-infrastructure` shared-baseline requirement.

### Requirement: Host-side build mode SHALL remain substituter-only in phase 1

**Reason:** the phase-1 nixbuild.net framing is obsolete; inbound fleet build accounts and outbound daemon scheduling are separate contracts.

**Migration:** `fleet-build-plane` FB-2 and FB-3 permit inbound CI jobs while keeping host-daemon remote scheduling disabled by default.

### Requirement: Main branch deployment automation SHALL be serial fail-fast

**Reason:** the existing manual-only deployment boundary must not be replaced by automatic activation when build CI is adopted.

**Migration:** `fleet-build-plane` FB-7 preserves LA-before-OCI fail-fast ordering for manual deployments; main pushes build and cache without deploying.

### Requirement: Builder SSH trust SHALL be owned by the builder-access aspect

**Reason:** the legacy requirement describes nixbuild.net trust rather than the canonical fleet host trust already projected here.

**Migration:** retain the `builder-access` aspect and derive trust from canonical inventory under `fleet-build-plane` FB-1 and FB-2. Substituter policy remains baseline-owned under FB-8.
