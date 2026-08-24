# Delta Spec: Bootstrap Storage

## ADDED Requirements

### Requirement: Adoption bootstrap SHALL NOT inherit OCI-specific defaults
Host bootstrap defaults that are specific to the Oracle Cloud OCI bootstrap path SHALL NOT be inherited by adopted hosts from other providers, and shared bootstrap safety checks SHALL apply without copy-pasting OCI-specific logic.

#### Scenario: Adopted host bootstrap safety is evaluated
- **WHEN** an adopted non-OCI host's bootstrap workflow is evaluated
- **THEN** it does not pull OCI-specific disk, network, or provider defaults from the OCI provider module
- **AND** shared bootstrap-safety checks apply without duplicating OCI logic

#### Scenario: Generic bootstrap helper is reused
- **WHEN** a bootstrap helper or check is shared across providers
- **THEN** it contains no provider-branded defaults
- **AND** provider-specific values remain in provider modules or explicit host composition
