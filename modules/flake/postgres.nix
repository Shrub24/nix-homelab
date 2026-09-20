# PostgreSQL placement aspect (dendritic Stage 7 / D-053; modular instance from
# modular-postgres-instances, D-058). Selecting this aspect on a host places the
# cluster there and supplies its top-level enablement; consumers register their
# databases and roles from their own modules. The instance's port and data
# directory are host facts, so the host's `_nixos.nix` declares them under
# `services.postgres.instances.<name>` — this aspect owns enablement only.
{ ... }:
{
  flake.modules.nixos.postgres = {
    imports = [ ../services/postgres.nix ];

    # Selecting this aspect is the substrate's top-level enablement.
    services.postgres.enable = true;
  };
}
