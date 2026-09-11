# Builder access: nixbuild.net SSH trust only (OPS-7). Substituter policy
# stays in the base aspect; the retired fleet.nixbuild-ssh.enable option is
# replaced by this aspect's selection.
{ ... }:
{
  flake.modules.nixos.builder-access = {
    imports = [ ./_builder-access/nixbuild-ssh.nix ];
  };
}
