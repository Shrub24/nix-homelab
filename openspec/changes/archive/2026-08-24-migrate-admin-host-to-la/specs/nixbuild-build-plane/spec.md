## MODIFIED Requirements

### Requirement: Shared substituter contract SHALL be available for active hosts
Active hosts SHALL support a common substituter/trust baseline that prioritizes `nixbuild.net` as the first substituter and the sovereign S3-backed binary cache as the durable secondary tier, with `cache.nixos.org` as the upstream fallback.

#### Scenario: Host build configuration is evaluated
- **WHEN** `nixosConfigurations.la-admin-1` and `nixosConfigurations.oci-melb-1` are evaluated
- **THEN** both include `ssh://eu.nixbuild.net` as the first substituter
- **AND** both include the sovereign S3 cache as the second substituter
- **AND** both include `https://cache.nixos.org` as the upstream fallback
- **AND** host composition remains module-driven rather than ad hoc host-inline Nix settings

#### Scenario: Sovereign cache is unavailable
- **WHEN** the sovereign S3 cache is unreachable during Nix evaluation or build
- **THEN** Nix falls through to `cache.nixos.org` as the next configured substituter
- **AND** host evaluation does not fail solely due to sovereign cache unavailability

### Requirement: Main branch deployment automation SHALL be serial fail-fast
Pushes to `main` SHALL trigger validation and then host deployment in deterministic serial order with fail-fast behavior.

#### Scenario: Main merge deployment is executed
- **WHEN** CI/CD runs on push to `main`
- **THEN** deployment runs `la-admin-1` before `oci-melb-1`
- **AND** failure on the first host stops further deployment for that run
