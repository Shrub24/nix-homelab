# Tasks

Implementation follows `design.md` PL-1, EX-1, ID-1, AC-1, ME-1, TU-1, SEC-1, VER-1, DOC-1. Each step is verified before the next; the parent owns the integration gates and the operator handoff.

## 1. Identity, policy and secret groundwork

- [x] 1.1 Add the three OAuth2 clients (`actual`, `memos`, `tududi`) to `policy/identity.json` under `systems.oauth2`, each with its display name, `secretKeyPrefix`, `routeKey` naming the route added in 1.2, and the callback path taken from upstream documentation — not guessed for any of them. Verify each callback path against its source (Actual's OpenID guide, Memos' `/auth/callback`, tududi's `docs/10-oidc-sso.md`).
- [ ] 1.2 Add the three routes to `policy/web-services.nix` under `oci-melb-1`: `actual` (`budget`, 5006), `memos` (`memos`, 5230), `tududi` (`tududi`, 3002), each published with `access.requireCloudflareAccess = false` and `access.oidc.enabled = true`. Each route's exposure mode follows the socket it dials — loopback binds use `direct`, host networking uses `tailscale-upstream` — and is confirmed against the ingress module's handling of that mode before it is written. Verify port freedom on the host first, and verify the route keys match 1.1.
- [x] 1.3 Add `tududi` to `policy/oci-images.nix` as `registry/repo:tag@sha256:digest`, resolving the real digest rather than writing a placeholder, and confirm the multi-arch index is what both fleet architectures can use.
- [ ] 1.4 Register the three client secrets in the identity provider's secret-source map, each pointing at `secrets/hosts/oci-melb-1/oidc.yaml`, and record the exact key names the operator must add there.
- [ ] 1.5 Give tududi's app-local secrets a home: `.sops.yaml` rule for `secrets/services/tududi.yaml`, a template for the two values, and the secret-scope fixture's expected readers. Verify `check-secret-scope` passes and that no other host gains readership.

## 2. Actual Budget aspect

- [ ] 2.1 Add `modules/apps/actual.nix` publishing `flake.modules.nixos.actual`: static `actual` user and group, `settings.dataDir = "/srv/data/actual"` with tmpfiles ownership, loopback `hostname`, port from the route, `loginMethod = "openid"` with `allowedLoginMethods = [ "password" "openid" ]`, and the `openId` block derived from the identity contract with `client_secret._secret`. Verify the evaluated `config.json` carries every key and that the unit's read/write paths include the data dir.
- [ ] 2.2 Register `/srv/data/actual` with state-backups. Verify the evaluated registration renders and that the export handles `account.sqlite` coherently rather than copying a live WAL database.

## 3. Memos aspect

- [ ] 3.1 Add `modules/apps/memos.nix` publishing `flake.modules.nixos.memos`: `dataDir = "/srv/data/memos"`, loopback address, port from the route, sqlite driver, `MEMOS_INSTANCE_URL` set to the public route, `openFirewall` left unset. Verify the rendered environment file and that the unit owns the data dir.
- [ ] 3.2 Register `/srv/data/memos` with state-backups. Verify the evaluated registration renders.
- [ ] 3.3 Render Memos' identity-provider file: a `sops.templates` entry targeting `/etc/secrets/memos-idp-kanidm.json` and readable by the memos account, holding one OAuth2 provider with its `name`, `type`, the authorization, token and userinfo endpoints taken from the identity contract, `fieldMapping` keyed on `sub`, and the client secret sourced from the host-scoped secret file. Verify the rendered file's shape and readability, and that no secret value is written anywhere in plaintext.
- [x] 3.4 Write the runbook covering that seam: how to verify at first deploy that Memos honours the rendered file, the fallback instance-settings values (the same endpoints, scopes and field mapping, read from the live discovery document), what to test afterwards, and the consequence of the fallback — the provider then lives in Memos' database, so a bare reimage without restoring the database would lose it.

## 4. tududi aspect

- [ ] 4.1 Add `modules/apps/tududi.nix` publishing `flake.modules.nixos.tududi`: the pinned image, `dataDir = "/srv/data/tududi"` with `db`, `uploads` and `backups` created at the image's runtime uid (read from its Dockerfile), the full environment from `design.md` TU-1, and the three secret bindings. Verify the evaluated container, mounts, uid, environment and unit prerequisites.
- [ ] 4.2 Register `/srv/data/tududi` with state-backups, coherent with its sqlite database. Verify the evaluated registration renders.

## 5. Host selection and contracts

- [ ] 5.1 Select `actual`, `memos` and `tududi` on `oci-melb-1`'s host record. Verify the host evaluates and that the three services and the one container are present.
- [ ] 5.2 Add `tests/check-user-app-placements.sh` covering `design.md` VER-1 — placement publication and selection, route-port to listener agreement, exposure mode against the socket, OIDC client and route-key agreement, backup registrations, and tududi's mounts and image ref — and register it in `.just/checks.just`. Verify it fails when one of those observables is broken.
- [ ] 5.3 Update the scaffold placement pins, the secret-scope fixture and the identity directionality expectations for three new aspects, one new container and three new clients. Verify each suite passes for the reason it exists, not because a list was widened.

## 6. Records and gates

- [x] 6.1 Record the change: the three placements and the Memos caveat in `ARCHITECTURE.md`, `STRUCTURE.md` and `docs/architecture.md`; the exposure and identity decision in `docs/decisions.md`; the operator steps (two secret files) in the runbook from 3.4.
- [ ] 6.2 Run the repository battery (`treefmt --fail-on-change`, `just checks all`, strict OpenSpec validation) and confirm the three-host evaluation is unchanged for hosts that do not select the new aspects. Report the operator handoff: the two secret files to prepare, Memos provider-file acceptance and its instance-settings fallback, then the deploy command.
