# Publishes the tracked configuration set to /etc/nixos-source. `.#` resolves tracked
# content only, so the copy carries no VCS metadata, tool state or plaintext credentials.
{
  self,
  ...
}:
{
  flake.modules.nixos.provenance = {
    system.configurationRevision = self.rev or self.dirtyRev or null;
    environment.etc."nixos-source".source = self.outPath;
  };
}
