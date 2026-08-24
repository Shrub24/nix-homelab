# Delta Spec: Kanidm Identity

## ADDED Requirements

### Requirement: OIDC client metadata SHALL derive safe defaults from identity policy
Consumer-facing OIDC client defaults (callback paths, display names, scope/claim mappings, and route keys) SHALL be derived from canonical identity metadata, with security-relevant overrides (PKCE relaxation, legacy crypto, short-username preference) allowed only as explicit, test-covered exceptions.

#### Scenario: A consumer's OIDC client is provisioned or rendered
- **WHEN** an OIDC consumer is provisioned or rendered
- **THEN** its metadata is resolved from the canonical identity policy rather than restated in host or web-catalog files
- **AND** security-relevant non-default settings appear as explicit overrides

#### Scenario: Scope mappings are tested strictly
- **WHEN** identity policy scope/claim mappings change
- **THEN** strict scope tests verify the derived client registrations and access posture
- **AND** accidental scope widening fails checks
