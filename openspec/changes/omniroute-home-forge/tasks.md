# Tasks: omniroute-home-forge

## 1. Image pin and secrets scaffolding

- [x] 1.1 Pin the OmniRoute image ref in `policy/oci-images.nix`
  - refs: `policy/oci-images.nix`
  - criteria: `omniroute = "ghcr.io/shrub24/omniroute:edge@sha256:<digest>"`; ref format matches existing entries
  - verify: `nix eval .#nixosConfigurations.home-forge.config.services.omniroute.image` resolves once the module exists; ref carries tag + sha256 digest
- [x] 1.2 Create the secret template and scope rule
  - refs: `secrets/.templates/services/omniroute.yaml`, `.sops.yaml`, `tests/fixtures/secret-scope.nix`
  - criteria: template documents `jwt_secret`, `api_key_secret`, `storage_encryption_key`, `initial_password`, `ws_bridge_secret` with generation hints; `.sops.yaml` gains a `^secrets/services/omniroute\.ya?ml$` rule scoped to the home-forge recipient only; the canonical test fixture expects only home-forge; no ciphertext created or edited by the agent
  - verify: `tests/check-secret-scope.sh` enumerates the OmniRoute scope and passes; user encrypts `secrets/services/omniroute.yaml` from the template (operator step)

## 2. Service module

- [x] 2.1 Implement `modules/services/omniroute.nix`
  - refs: `modules/services/bifrost-gateway.nix` (structural template), `modules/services/karakeep.nix` (sidecar DNS pattern), `lib/secrets.nix`, design.md D2–D5, D7
  - criteria: `services.omniroute.enable`/`image`/`dataDir`/`port`/`secretFiles.host` options; required-secret assertion; sops environment template with the five secrets; tmpfiles for `/srv/data/omniroute` (UID 1000); `virtualisation.oci-containers` entries for `omniroute` + `omniroute-redis` (redis unpublished, app reaches it by container name); `--stop-timeout=40`; `OMNIROUTE_MEMORY_MB=8192`, `OMNIROUTE_SERVER_HOST=0.0.0.0`, `AUTH_COOKIE_SECURE=false`, `NODE_ENV=production`; `restartTriggers` on the environment file; state-backups contract excluding logs; no configFile option, no render oneshot
  - verify: module imports cleanly and `services.omniroute` options evaluate on home-forge
- [x] 2.2 Wire the module import through the same path other container services use
  - refs: `modules/services/omniroute.nix`, `hosts/home-forge/default.nix`
  - criteria: `services.omniroute` options exist on home-forge evaluation without touching unrelated hosts
  - verify: `nix eval .#nixosConfigurations.home-forge.config.services.omniroute.enable` succeeds

## 3. Host enablement

- [x] 3.1 Enable OmniRoute on home-forge
  - refs: `hosts/home-forge/default.nix`
  - criteria: `services.omniroute.enable = true` with `secretFiles.host = ../../secrets/services/omniroute.yaml`; defaults kept for dataDir/port; comment records the imperative-config ownership intent
  - verify: host eval passes with the binding; unrelated hosts unaffected

## 4. Validation and rollout

- [x] 4.1 Repo-level validation
  - criteria: `nix flake check --no-build` passes; `nix build .#nixosConfigurations.home-forge.config.system.build.toplevel --no-link` succeeds; `treefmt --fail-on-change` clean; `openspec validate --strict` passes
  - verify: all four commands exit zero
- [ ] 4.2 Deploy and bootstrap (operator, from a clean jj change)
  - refs: `.just/deploy.just`, design.md Migration Plan
  - criteria: prerequisite — user has encrypted `secrets/services/omniroute.yaml`; `just deploy home-forge` activates the stack; both containers running; `/healthz` returns 200; dashboard reachable at `http://home-forge:20128` over LAN and MagicDNS over tailnet; login with `INITIAL_PASSWORD` works; imperative config persists across a redeploy
  - verify: `podman ps` shows omniroute + redis; health check and dashboard login confirmed; workstation `omniroute connect home-forge` succeeds
