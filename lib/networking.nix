# Container-facing ingress for native services bound to the host's service
# address (`serviceNetwork` in policy/globals.nix).
{ lib }:
{
  # For `networking.firewall.extraCommands`. `iptables`, not `ip46tables`: the
  # match is IPv4-only.
  mkServiceIngressRule =
    {
      sourceCIDR,
      address,
      ports,
    }:
    "iptables -A nixos-fw -s ${sourceCIDR} -d ${address} -p tcp -m multiport --dports ${lib.concatStringsSep "," (map toString ports)} -j nixos-fw-accept";
}
