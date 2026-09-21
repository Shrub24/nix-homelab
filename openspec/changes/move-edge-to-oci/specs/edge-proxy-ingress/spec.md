## ADDED Requirements

### Requirement: Routes SHALL declare how they are exposed

Every route in canonical policy SHALL declare its `exposureMode`, the single axis describing how the service is exposed and whether it is published. No default SHALL apply, so an unlabelled route fails evaluation, and a route reachable only through a front rendered by its providing host SHALL declare `tailscale-serve`.

#### Scenario: A route is served through its providing host

- **WHEN** a route declares `tailscale-serve`
- **THEN** the edge dials the provider's canonical private name on the route's port
- **AND** it verifies the presented certificate against public roots

#### Scenario: A served route keeps conflicting transport settings out

- **WHEN** a route declaring `tailscale-serve` also sets an upstream TLS server name, an insecure flag, or a CA file
- **THEN** policy evaluation fails closed with the conflicting fields named

#### Scenario: A route without an exposure mode

- **WHEN** a route declares no `exposureMode`
- **THEN** policy evaluation fails closed, naming the route and the allowed values

### Requirement: Providers SHALL render their own front for private-transport routes

A host that provides a private-transport route SHALL render the front the edge dials, driven by resolved policy and owned by the ingress origin role, so that no service module depends on the private network's exposure mechanism.

#### Scenario: The provider renders exactly one front

- **WHEN** an origin-role host provides a route declaring a private transport
- **THEN** it renders one front for that route on the route's declared port
- **AND** the front dials the service's loopback socket on the same port

#### Scenario: A host that does not provide the route renders nothing

- **WHEN** a host does not provide the route, including the edge host that dials it
- **THEN** no front is rendered for it

#### Scenario: The front is reconciled, not assumed

- **WHEN** the front's unit starts
- **THEN** it waits for the private-network daemon and applies its configuration idempotently
- **AND** when the unit stops it withdraws the configuration
