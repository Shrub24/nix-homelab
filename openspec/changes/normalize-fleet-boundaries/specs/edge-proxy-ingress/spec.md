# Delta Spec: Edge Proxy Ingress

## ADDED Requirements

### Requirement: Edge host composition SHALL project from the edge-ingress owner's catalog
The edge host's ingress composition SHALL be derived by the edge-ingress owner from the canonical resolved route catalog, and host-local edge overlays SHALL be removed when they only re-project catalog data.

#### Scenario: Edge host declares routes through the owner module
- **WHEN** an edge host is composed
- **THEN** routes, primary domain, and edge defaults resolve from the edge-ingress owner's projection of the canonical catalog
- **AND** the host file does not duplicate the projection logic

#### Scenario: Host retains an explicit edge exception
- **WHEN** an edge host needs a host-specific edge value not present in the catalog projection
- **THEN** the value is declared as an explicit exception in the host assembly
- **AND** the exception is visible and documented rather than a full re-projection of catalog data
