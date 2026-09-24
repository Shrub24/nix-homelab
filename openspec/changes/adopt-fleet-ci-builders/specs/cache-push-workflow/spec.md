# Spec Delta

## MODIFIED Requirements

### Requirement: Hosts SHALL push closures after successful deployment activation

Active hosts SHALL preserve their activation-triggered publication of newly activated system closures using host-scoped niks3 credentials. That trigger SHALL remain distinct from CI and builder post-build publication, which may publish successful build outputs before any activation.

#### Scenario: Host pushes after successful deploy
- **WHEN** a deployment activation succeeds and the activation-triggered publication capability is enabled
- **THEN** the host publishes the newly activated closure using its host-scoped credential

#### Scenario: Failed deployment does not push
- **WHEN** a deployment activation fails
- **THEN** failure does not cause a successful-activation publication event
- **AND** outputs already published by CI or a builder remain valid build artifacts, not evidence that activation succeeded

#### Scenario: CI prebuilds a deployable closure
- **WHEN** an authorized CI run successfully builds and publishes a deploy profile
- **THEN** that closure can be substituted before a host activates it
- **AND** build publication does not grant deployment authority
