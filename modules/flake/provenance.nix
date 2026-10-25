# Publishes the tracked configuration set to /etc/nixos-source. `.#` resolves tracked
# content only, so the copy carries no VCS metadata, tool state or plaintext credentials.
{
  self,
  ...
}:
{
  flake.modules.nixos.provenance = {
    environment.etc."nixos-source".source = self.outPath;
  };
}
