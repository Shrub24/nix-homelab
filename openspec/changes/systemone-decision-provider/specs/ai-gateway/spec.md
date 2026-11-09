# Spec Delta: AI Gateway

## ADDED Requirements

### Requirement: Decision models SHALL be reachable through the gateway

The gateway SHALL serve TypeSafe's System One decision API so an in-fleet consumer can
reach a decision model without a provider credential of its own. A decision provider
SHALL be declared separately from a chat provider over the same upstream, because a
decision is not an OpenAI-format operation, and SHALL admit only the decision request
type and only the model named in policy.

#### Scenario: Consumer sends a decision

- **WHEN** an in-fleet consumer posts a System One request to the gateway's native route
  naming `<provider>/<vendor>/<model>`
- **THEN** the gateway SHALL forward the vendor-prefixed model to that provider's base URL
  and return the decision answers
- **AND** a request naming a provider the policy does not declare SHALL be refused before
  any upstream call

#### Scenario: A restricted provider is addressed directly

- **WHEN** a request names the decision provider for work other than a decision
- **THEN** the gateway SHALL refuse it locally rather than forward it upstream

### Requirement: Provider credentials SHALL stay in the shared service scope

A provider credential SHALL reach every host that places the gateway from one
service-scoped secret file, rendered into the gateway environment. A consumer SHALL NOT
need the provider credential to reach a decision model.

#### Scenario: A consuming host holds no provider key

- **WHEN** a host runs a service that calls the gateway for decisions
- **THEN** that host's configuration SHALL reference the gateway endpoint only
- **AND** the provider credential SHALL remain bound to the gateway's own hosts
