## MODIFIED Requirements

### Requirement: Route ownership is modular by host and service
Ingress route declarations SHALL remain composable per host and service through canonical web policy, while deployment placement SHALL be controlled by explicit host selection of the discovered `edge` aspect. Selecting the aspect SHALL provide application enablement; the host SHALL retain only its explicit `edge` or `origin` role and genuine exceptions rather than importing the ingress implementation.

#### Scenario: Different hosts expose different services
- **WHEN** host role composition differs between nodes
- **THEN** each participating host selects the same discovered `edge` aspect with its explicit role
- **AND** each host publishes only the route set resolved for that host from canonical policy
- **AND** a host that does not select `edge` activates no ingress runtime
- **AND** no host directly imports the edge application or proxy implementation

#### Scenario: Edge placement conversion preserves routing
- **WHEN** edge/origin composition moves from the evaluator-class application root to the discovered concern owner
- **THEN** primary domain, ACME email, trusted proxy policy, Authenticated Origin Pulls, secret paths, and every rendered route remain unchanged
- **AND** discovery alone does not expose any route
