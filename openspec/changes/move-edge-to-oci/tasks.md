# Tasks

## 1. Policy declares how each route is exposed

- [ ] 1.1 Declare `exposureMode = "tailscale-serve"` on `kanidm-admin`, drop the literal upstream TLS server name, and label every other route's exposure mode
- [ ] 1.2 Validate transport values in web policy; fail closed when a private-transport route also sets an upstream TLS override, and when a host fronts itself
- [ ] 1.3 Project the routes a host provides to that host (`repo.web.originServices`)

## 2. The provider renders its own front

- [ ] 2.1 Add an origin-role contributor to the ingress aspect that renders one front per private-transport route the host provides
- [ ] 2.2 Reconcile the front on start and clear it on stop, ordered against the daemon it depends on
- [ ] 2.3 Pin both sides in the dendritic scaffold contract (front present on the provider, absent on the edge)

## 3. Kanidm stops borrowing the edge's TLS

- [ ] 3.1 Generate a host-local certificate pair owned by the service user, under the provider's state directory
- [ ] 3.2 Drop the ACME certificate paths, the edge-only reader group, and the ordering after the reverse proxy
- [ ] 3.3 Assert at evaluation that the configured bind port matches the published route port

## 4. Contracts and documentation

- [x] 4.1 Extend the web-service catalog contract for the new transport and projection
- [x] 4.2 Re-pin the scaffold contract's resolved-policy keys and identity unit assertions
- [x] 4.3 Update architecture documentation and record the decision

## 5. Placement identity, derived transport

- [x] 5.1 Replace `origin.host` with `origin.provider` (canonical host ID) across the policy and delete the FQDN bindings
- [x] 5.2 Derive ingress upstreams from `exposureMode` (`direct` → edge-local loopback with an edge-local guard; every tailnet mode → provider FQDN even when colocated)
- [x] 5.3 Resolve a private service's machine-to-machine `endpoint` against the evaluating host (loopback when colocated), keeping identity fields literal
- [x] 5.4 Rewrite the catalog contract's placement assertions to provider IDs and record the decision (D-064)

## 6. Cutover

- [ ] 6.1 Deploy `la-admin-1` and confirm the front answers on the tailnet name
- [ ] 6.2 Deploy `oci-melb-1` and confirm the edge renders the route
- [ ] 6.3 Flip the edge DNS record and verify a public route plus the identity URL
- [ ] 6.4 Verify OIDC discovery through the full chain and record the result
