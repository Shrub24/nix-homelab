# Spec Delta

## REMOVED Requirements

### Requirement: CI SHALL NOT push to the sovereign cache

**Reason:** Nixbot now publishes admitted CI outputs and reconciles main retention roots; limiting publication to successfully activated hosts would prevent the approved CI/cache plane.

**Migration:** Keep existing authority during observed cutover, then retire homelab Actions build/cache grants only. Existing host publication and other repositories remain unchanged.

## ADDED Requirements

### Requirement: Nixbot SHALL reconcile homelab rolling cache roots

A main-only cache effect SHALL publish both architecture retention roots before pinning them under nix-homelab-main-*. Its OIDC rule SHALL bind the exact issuer, audience, homelab repository, main ref, push event and issued effect identifier, granting write and only that pin namespace. Actual claim shapes SHALL be verified before cache-host trust activation. PR and other-effect tokens SHALL be denied.

#### Scenario: Root is not yet cached

- **WHEN** main reconciliation runs after the warn-only uploader missed a root
- **THEN** the effect pushes it before pin creation
- **AND** a failed push or absent root fails visibly rather than moving a misleading pin

#### Scenario: Another repository or effect attempts homelab pinning

- **WHEN** its token does not satisfy the exact reconciliation rule
- **THEN** that rule grants neither upload nor homelab pin authority
- **AND** other repositories retain their independent existing grants

### Requirement: Uploader admin authority SHALL remain explicit

The nixbot uploader MAY use the accepted existing static admin API token because its integration consumes a token file. Documentation SHALL state that it can also move pins and shares revocation with its other users; normal reconciliation SHALL use scoped workload identity instead. No deployment credential SHALL be introduced.

#### Scenario: Uploader credential is provisioned

- **WHEN** the operator prepares the service secret
- **THEN** its authority is not described as write-only, pin-free or independently revocable
