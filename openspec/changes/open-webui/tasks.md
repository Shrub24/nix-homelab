## 1. Policy, identity, and secret contracts

- [ ] 1.1 Verify the selected Open Terminal upstream image has an immutable ARM64 digest and add it to the OCI image policy.
  - refs: `policy/oci-images.nix`
  - criteria: A declared Open Terminal image reference is digest-pinned, usable on `aarch64-linux`, and contains no mutable tag-only runtime dependency.
  - verify: `nix eval .#nixosConfigurations.oci-melb-1.config.system.build.toplevel.drvPath`

- [ ] 1.2 Add the Open WebUI Kanidm client and private-origin web route to canonical identity and web-service policy.
  - refs: `policy/identity.json`, `policy/web-services.nix`, `modules/shared/identity-oidc.nix`
  - criteria: The callback URL derives from the declared Open WebUI URL and the route uses the existing Caddy-to-Tailscale origin pattern without a directly public origin port.
  - verify: `just checks all`

- [ ] 1.3 Add Open WebUI and Open Terminal secret templates, path-scoped SOPS policy, and secret-scope fixture coverage without creating encrypted values.
  - refs: `secrets/.templates/`, `.sops.yaml`, `tests/fixtures/secret-scope.nix`, `tests/check-secret-scope.sh`
  - criteria: Templates identify all runtime-only secrets; the service secret path is decryptable only by declared recipients; no plaintext secret is committed.
  - verify: `just checks all`

## 2. Service and application composition

- [ ] 2.1 Add a constrained Open Terminal Podman leaf service module.
  - refs: `modules/services/open-terminal.nix`, `policy/oci-images.nix`, `lib/secrets.nix`
  - criteria: The service is digest-pinned, private to the host/Open WebUI path, SOPS-keyed, resource-bounded, uses multi-user workspaces, and has no privileged mode, host mounts, runtime socket, SSH credential, or fleet-secret mount.
  - verify: `nix eval .#nixosConfigurations.oci-melb-1.config.virtualisation.oci-containers.containers.open-terminal`

- [ ] 2.2 Add the AI workbench application composition root around native Open WebUI and hosted Open Terminal.
  - refs: `modules/applications/ai-workbench/default.nix`, `modules/services/open-terminal.nix`, `modules/services/bifrost-gateway.nix`, `lib/secrets.nix`
  - criteria: The application configures the native `services.open-webui` module, narrow unfree permission, persistent state, immutable baseline configuration, server-side terminal connection, and host-local Bifrost OpenAI-compatible connection.
  - verify: `nix eval .#nixosConfigurations.oci-melb-1.config.services.open-webui.enable`

- [ ] 2.3 Configure Kanidm OIDC, group/role synchronization, and application state ownership without making UI configuration canonical.
  - refs: `modules/applications/ai-workbench/default.nix`, `modules/services/admin/kanidm.nix`, `modules/shared/identity-oidc.nix`
  - criteria: The rendered environment uses the policy-derived external URL and OIDC values, disables persistent baseline configuration, and keeps sensitive values in a SOPS environment file.
  - verify: `nix eval .#nixosConfigurations.oci-melb-1.config.systemd.services.open-webui.serviceConfig.EnvironmentFile`

- [ ] 2.4 Wire the composition root and OIDC client-secret binding into both host assemblies.
  - refs: `hosts/oci-melb-1/default.nix`, `hosts/do-admin-1/default.nix`, `modules/applications/default.nix`
  - criteria: `oci-melb-1` explicitly enables the workbench and `do-admin-1` can provision the corresponding Kanidm client without a blanket module import.
  - verify: `nix eval .#nixosConfigurations.oci-melb-1.config.applications.ai-workbench.enable`

## 3. Operational integration and user-owned Computer onboarding

- [ ] 3.1 Register Open WebUI and any persistent Open Terminal workspace data with state backups, health checks, resource monitoring, and notification monitoring.
  - refs: `modules/services/state-backups.nix`, `modules/services/notification-daemon/default.nix`, `policy/web-services.nix`, `hosts/oci-melb-1/default.nix`
  - criteria: Backups cover the database, uploads, and vector state together; the service exposes a declared health path; failures follow the notification-daemon path.
  - verify: `just checks all`

- [ ] 3.2 Write the curated Open WebUI Computer onboarding, model-ACL, Tailscale reachability, and experimental Direct Connections runbook.
  - refs: `docs/architecture.md`, `docs/decisions.md`, `docs/plan.md`
  - criteria: Documentation distinguishes hosted Open Terminal from user-owned Computer, prohibits shared/public Computer endpoints, and records that Computer identity is not forwarded from Open WebUI.
  - verify: `git diff --check`

- [ ] 3.3 Write the operator runbook for initial OIDC bootstrap, trusted terminal-group administration, terminal workspace retention, backup restoration, and rollback.
  - refs: `docs/architecture.md`, `docs/decisions.md`, `docs/plan.md`, `README.md`
  - criteria: The runbook identifies the manual user-owned secret-creation step and provides recovery steps without instructing operators to decrypt or edit secrets manually.
  - verify: `git diff --check`

## 4. Validation and controlled rollout

- [ ] 4.1 Add focused contract checks for the workbench's private origin, immutable configuration, Bifrost-only baseline connection, and Open Terminal prohibition on unsafe mounts.
  - refs: `tests/`, `justfile`, `.just/checks.just`
  - criteria: Checks fail when the declared service exposes an unsafe origin, uses unpinned terminal image policy, enables persistent baseline config, bypasses Bifrost, or mounts prohibited host resources.
  - verify: `just checks all`

- [ ] 4.2 Format and evaluate the exact ARM host configuration, including the narrow unfree allowance.
  - refs: `flake.nix`, `hosts/oci-melb-1/default.nix`
  - criteria: Formatting is clean and the `oci-melb-1` configuration evaluates with all Open WebUI/Open Terminal contracts enabled.
  - verify: `treefmt --fail-on-change && nix flake check`

- [ ] 4.3 Complete a staged operator acceptance check after the user creates encrypted secrets.
  - refs: `docs/`, `secrets/.templates/`
  - criteria: An authorized user can sign in through Kanidm, use a Bifrost-backed model, invoke a bounded hosted terminal, restore a test backup, and connect one personal Computer workspace over Tailscale.
  - verify: `just deploy oci-melb-1`

- [ ] 4.4 Validate the completed OpenSpec change.
  - refs: `openspec/changes/open-webui/`
  - criteria: All implemented tasks are checked off and the change validates against the strict OpenSpec schema.
  - verify: `openspec validate --strict`
