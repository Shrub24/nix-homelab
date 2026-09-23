# Kanidm release family: the server wrapper and the client tooling are bound
# together here so they cannot drift, and the `kanidmd domain upgrade-check` gate
# still applies before this binding moves.
{ pkgs }:
let
  release = "1_11";
in
{
  server = pkgs."kanidmWithSecretProvisioning_${release}";
  client = pkgs."kanidm_${release}";
}
