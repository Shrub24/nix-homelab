# Decision processing

## Purpose

Provide inexpensive typed email decisions while retaining the existing generative path and explicit privacy and recovery boundaries.

## ADDED Requirements

### Requirement: Default email decision processing

Eligible Inbox Zero users SHALL use the configured Perplexity decision model through AI Gateway by default, including cold-email detection. Existing user choices SHALL retain precedence. Ordinary LLM work and decision failures SHALL retain the configured Bifrost path.

#### Scenario: Eligible user processes mail

- **WHEN** a user without a personal AI key or explicit opt-out reaches a supported decision task
- **THEN** the deployment SHALL select `perplexity/pplx-decider-v1.2` through AI Gateway
- **AND** decision failure SHALL use the existing LLM fallback

### Requirement: Isolated provider credential

The decision credential SHALL be operator-populated, app-scoped and delivered outside the Nix store. An absent or empty credential SHALL prevent startup rather than silently disable the requested integration. It SHALL NOT become the credential for unrelated Bifrost LLM requests.

#### Scenario: Missing decision credential

- **WHEN** the application starts without its required AI Gateway credential
- **THEN** startup SHALL fail with a non-secret diagnostic

### Requirement: Accurate privacy and upgrade acceptance

The privacy policy SHALL retain the no-training commitment without guaranteeing ZDR and SHALL disclose external email processing and possible retention. Upgrade instructions SHALL require a pre-upgrade database export and distinguish evaluated configuration from live migration and decision acceptance.

#### Scenario: Operator prepares deployment

- **WHEN** the upgraded image and credentials are ready to deploy
- **THEN** the instructions SHALL require no-training provider controls, user disclosure and a database export
- **AND** a successful Nix evaluation SHALL NOT be presented as successful migration or inference
