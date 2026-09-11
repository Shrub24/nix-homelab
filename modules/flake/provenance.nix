# Repository provenance; replaces the args.self handling in core/base.nix.
{ self, ... }:
{
  flake.modules.nixos.provenance = {
    system.configurationRevision = self.rev or self.dirtyRev or null;
    environment.etc."nixos-source".source = self.outPath;
  };
}
