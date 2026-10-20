# Tasks

## 1. Pin Homarr v2 and establish canonical identity and routing

- [x] 1.1 Verify the released `ghcr.io/homarr-labs/homarr:v2.5.2` image index includes `linux/arm64`, record its immutable digest in `policy/oci-images.nix`, and confirm the registry reference evaluates for `aarch64-linux`.
- [x] 1.2 Add the `home.shrublab.xyz` route on `oci-melb-1` using Homarr's verified port and Tailscale-Serve transport so bootstrap remains privately reachable while the route's `publish` is false; keep Cloudflare Access disabled and app OIDC enabled. Run web-policy and service-catalog contracts and verify the exported route uses the canonical host.
- [x] 1.3 Add a dedicated Homarr client to `policy/identity.json` with the canonical OIDC callback and the HTTPS Tailscale Serve callback derived from the service catalog provider host and port; use minimal identity scopes and the correct Kanidm authorization group. Bind its client secret to the OCI host OIDC source and add the generated key to its secret template/SOPS scope. Verify identity directionality and secret-scope checks without decrypting or editing encrypted secrets.

## 2. Implement the isolated service and verify OIDC behavior

- [ ] 2.1 Add the `homarr` aspect under `modules/apps/` and select it on `oci-melb-1`; render persistent service-scoped `AUTH_SECRET` and `SECRET_ENCRYPTION_KEY`, set `BASE_URL` to the private Tailscale origin during credentials bootstrap and the public origin in steady state, leave `NEXTAUTH_URL` unset, persist `/appdata` under `/srv/data/homarr`, and bind only the loopback listener without any container-runtime socket. Provide an explicit, disabled-by-default temporary credentials bootstrap option. Verify OCI toplevel evaluation and inspect the rendered container, listener, environment-file permissions, and unit dependencies.
- [ ] 2.2 Add a Homarr placement contract covering image pin, host selection, withheld public route, Tailscale-Serve exposure, canonical and private OIDC callbacks, both persistent secrets, phase-specific `BASE_URL`, secret boundaries, persistence, temporary bootstrap defaults, and absence of a runtime socket; include mutation controls for premature public-route release and raw SQLite capture, and run them successfully.
- [ ] 2.3 Document secret preparation and first-administrator bootstrap in `docs/runbooks/homarr.md`. Through the private Tailscale endpoint, create Homarr's initial credentials admin, sign in through Kanidm to create a separate OIDC account, promote that account, then remove the temporary account and disable credentials before public release. Verify each callback and bootstrap step against the implementation and release-matched docs.

## 3. Make Homarr user state recoverable

- [x] 3.1 Register Homarr's persistent state with `state-backups`; capture non-database appdata and export the SQLite/WAL database with the SQLite backup API. Extend the placement contract to reject raw live-database capture.
- [x] 3.2 Extend `docs/runbooks/homarr.md` with pre-upgrade backup, staging restore, encryption-key recovery, and restore-before-image-rollback steps; validate the chosen database export/capture and restore against disposable Homarr state without using production data.

## 4. Verify integration and record the deployment boundary

- [ ] 4.1 Update the scaffold contract pins for the new image, selected aspect, container, route, identity client, and backup registration; run the focused placement, identity, secret-scope, service-catalog, and scaffold contracts.
- [x] 4.2 Run `treefmt --fail-on-change`, `openspec validate --strict`, and `just checks all`; resolve any failures before considering the change ready for operator deployment.
- [x] 4.3 Update `ARCHITECTURE.md`, `STRUCTURE.md`, and `docs/architecture.md` to distinguish user-facing Homarr from operator Homepage, and document that Homarr's user, group, board, and catalogue state is edited in the app rather than generated from policy.

## Workflow follow-up

- Operator creates and encrypts the Homarr service key and adds the Kanidm client secret using the documented secret workflow; agents must not decrypt or edit the encrypted values.
- Before public enablement, operator validates first-admin setup, two distinct Kanidm logins, unauthenticated denial, independent board permissions/home boards, and the correct restore key.
- Deploy only after the arm64 image check and required secrets are ready; verify the live service and a restic backup/restore before declaring operational acceptance.
