# Spec Delta

## MODIFIED Requirements

### Requirement: Active hosts SHALL support a shared remote substitute baseline

Active hosts SHALL consume the same substitute and cache-key catalog from nix-fleet's shared baseline. Local host records and builder-access composition SHALL NOT duplicate provider URLs, keys or ordering. Changes to the upstream catalog SHALL be verified through evaluated host settings.

#### Scenario: Active host baseline is reviewed
- **WHEN** oci-melb-1, la-admin-1 and home-forge are evaluated
- **THEN** all inherit the shared upstream substitute/trust baseline
- **AND** their host-private composition does not own provider-specific catalog entries

#### Scenario: Current provider defaults remain policy-driven
- **WHEN** the upstream substitute catalog changes
- **THEN** provider-specific URLs, signing keys and priorities come from the canonical fleet baseline
- **AND** evaluated host settings verify the change without a provider-branded host module

#### Scenario: Builder account is selected
- **WHEN** a host gains a dedicated dispatch account and canonical SSH trust
- **THEN** the shared substitute catalog remains baseline-owned
- **AND** builder authorization does not implicitly enable outbound distributed scheduling
