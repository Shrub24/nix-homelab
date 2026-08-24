## Why

DigitalOcean credits will end soon, while `do-admin-1` currently combines the fleet's public edge, Kanidm identity provider, and stateful admin services. The replacement LA VPS is already running NixOS, so the fleet needs a controlled host adoption and data cutover that preserves the existing public URLs, private origins, and recovery posture before the DigitalOcean node is retired.

## Core Value

Replace the provider-bound admin host without sacrificing recoverability, private-first origin access, or the existing identity and public-edge contracts.

## What Changes

- Add `la-admin-1` as the x86_64 LA admin, identity, and public-edge host; retain `do-admin-1` only as the live rollback source until decommission.
- **BREAKING** Replace `do-admin-1` with `la-admin-1` in fleet host identity, deployment metadata, Tailscale tagging, CI ordering, and operator workflows; deliberately change the local-admin Cockpit path to `/la-admin-1`.
- Add a canonical web-policy service catalog so cross-host consumers use stable service IDs and public URLs rather than the current edge or identity hostname.
- Keep physical host references only at physical boundaries: host assemblies, deployment metadata/order, CI jobs, Tailscale identities, backups, and host-scoped secret policy.
- Adopt the preinstalled LA NixOS system non-destructively from a committed LA-only `nixos-facter` report plus captured runtime facts; do not use the DigitalOcean provider module, `nixos-anywhere`, or `disko` against its live volume.
- Consume the LA facter report directly for hardware, drivers, virtualisation, and DHCP; retain only the minimal root/ESP by-UUID mounts that facter cannot report.
- Preserve LA's existing UEFI `systemd-boot` installation; do not inherit the fleet base module's GRUB-removable-media default.
- Move Kanidm, Vaultwarden, Termix, Beszel, and required admin state through an export/restore and final freeze procedure; recreate ntfy auth declaratively from SOPS auth-users/auth-tokens, accepting cache/history/attachments as ephemeral state, while allowing Quantum to start empty. Kanidm restore verification remains fail-closed except for the one version-pinned, independently proven revoked-OAuth-session false positive documented in the migration design.
- Move host and feature secret access to explicitly scoped LA recipients. The operator creates and encrypts secret payloads; repository changes provide policy, contracts, and templates only.
- Cut public traffic by changing the policy-driven OpenTofu origin endpoint after private validation. Preserve the DigitalOcean node for rollback until the LA host completes a new backup and recovery check.
- Move LA backups to a new host-scoped R2 repository and retain the DigitalOcean repository as immutable migration recovery material.
- Add a canonical host-initialization runbook covering both preinstalled-NixOS adoption and destructive reimage paths; update architecture, decision, and plan documentation, and defer deployment of the active `open-webui` change until the migration is complete.

## Capabilities

### New Capabilities

- `policy-service-catalog`: Expose one policy-derived catalog of stable service IDs, public URLs, access metadata, and health metadata for cross-host consumers.

### Modified Capabilities

- `fleet-infrastructure`: Replace the active x86_64 admin host while preserving explicit host composition, cache-consumer, and deployment contracts.
- `network-access`: Move the designated edge and identity host while retaining private origins, Tailscale-first access, and provider-console recovery.
- `edge-proxy-ingress`: Resolve current declared edge routes through `la-admin-1` without changing origin exposure modes and with the approved local-admin Cockpit path change.
- `admin-services`: Move the admin service baseline, local Quantum source, Vaultwarden, and Cockpit route from the DigitalOcean host to LA.
- `admin-service-consolidation`: Update the admin composition host identity.
- `kanidm-identity`: Designate LA as the Kanidm/OIDC host while preserving declared client registration and encrypted identity inputs.
- `secrets-management`: Re-scope host and cross-host OIDC secret readers to LA without broadening unrelated access.
- `state-backups`: Give LA a distinct host-scoped restic repository and require restore verification before DO retirement.
- `bootstrap-storage`: Adopt the preinstalled LA system through a non-destructive first-generation boot path using captured disk, boot, and network facts.
- `host-recovery`: Require verified provider-console and `rescue`-user break-glass access before LA becomes authoritative.
- `provider-owned-oidc-uris`: Move provider-owned OIDC runtime templates to the LA identity host.
- `paperless-service`: Preserve Paperless ingress through the replacement edge host.
- `vaultwarden-email-delivery`: Move the Vaultwarden mail-delivery contract to LA.
- `nixbuild-build-plane`: Replace the active x86_64 deployment target and ordering in the build-plane contract.

## Impact

- Affected host and topology files include `flake.nix`, `hosts/do-admin-1/`, new `hosts/la-admin-1/` including its committed `facter.json`, `lib/deploy/hosts.nix`, `lib/policy.nix`, `modules/shared/web-policy.nix`, `policy/web-services.nix`, `.github/workflows/`, `.just/`, and generated web-policy output.
- Affected control planes are Tailscale tags/ACLs, Cloudflare OpenTofu origin configuration, Cloudflare Access's existing Kanidm IdP, R2/restic repositories, and the DigitalOcean provider account.
- Affected state is Kanidm, Vaultwarden, Termix, Beszel, and host recovery material; ntfy auth is recreated declaratively from SOPS rather than migrated by copy. Quantum data is deliberately out of scope for preservation.
- The operator must supply LA hardware/network facts, create the LA age recipient and encrypted secret files, create a tagged Tailscale auth key, create the LA R2 backup target, and execute provider/Cloudflare cutover actions.
- Future host operators use the canonical runbook rather than reproducing LA-specific manual bootstrap steps.
