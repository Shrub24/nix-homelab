# Delta Spec: Operations

## ADDED Requirements

### Requirement: Operator workflows SHALL cover AudioMuse first-run bootstrap and plugin enablement
Operations documentation and verification flows SHALL include the AudioMuseAI first-run workflow, Navidrome plugin enablement steps, and Symfonium validation required for similarity features.

#### Scenario: Operator prepares AudioMuse similarity on a host
- **WHEN** a host is deployed with AudioMuseAI and Navidrome plugin support
- **THEN** the operator workflow SHALL include how to reach the AudioMuse bootstrap endpoint according to current exposure policy, complete the initial setup flow, and bind Navidrome plugin settings
- **AND** the workflow SHALL distinguish deployed infrastructure from fully validated Symfonium behavior
- **AND** the workflow SHALL document a **fresh-start / recreate posture**: existing AudioMuse application state is disposable, so operators may drop and recreate the `audiomuse` database if bootstrap is misconfigured; no migration procedure is provided or needed

### Requirement: Validation SHALL include AudioMuse and Navidrome similarity readiness checks
Pre-deploy and post-deploy verification for the music stack SHALL include checks that AudioMuse infrastructure is healthy, Navidrome has the plugin runtime posture required for similarity features, and real Symfonium validation is performed before the feature is accepted.

#### Scenario: Operator validates AudioMuse deployment
- **WHEN** the operator runs the canonical validation flow for the music stack after deployment
- **THEN** the checks SHALL confirm that AudioMuse service units or containers are running
- **AND** the checks SHALL confirm that Navidrome has the nixpkgs-provided plugin package (`pkgs.navidromePlugins.audiomuseai`) and plugin runtime flags in place before end-user similarity testing
- **AND** final acceptance SHALL include actual Symfonium similar/radio behavior against the deployed stack
