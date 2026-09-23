# Repository provenance.
#
# The published copy is the tracked configuration set: every local reference to
# this flake uses the Git-tree form (`.#`), which resolves tracked content only,
# so `/etc/nixos-source` carries fleet sources without VCS metadata, tool state,
# vendored bulk, or plaintext credential files. `self.rev`/`self.dirtyRev` are
# populated for that form, so `configurationRevision` is meaningful.
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
