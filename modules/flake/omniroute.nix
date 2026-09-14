# OmniRoute deployment aspect (dendritic Stage 7, D-053). Published from this
# discovered contributor and selected only on `home-forge` (S7-2). Selection
# imports the OmniRoute service leaf and preserves the host's two-step secret
# bootstrap: the service and its notification-daemon monitor registration
# activate only once `secrets/services/omniroute.yaml` exists. The encrypted
# secret file, its `.sops.yaml` rule, and the policy image pin are untouched.
{ ... }:
{
  flake.modules.nixos.omniroute =
    {
      lib,
      ...
    }:
    let
      secretFile = ../../secrets/services/omniroute.yaml;
      hasSecret = builtins.pathExists secretFile;
    in
    {
      imports = [ ../services/omniroute.nix ];

      services.omniroute = lib.mkIf hasSecret {
        enable = true;
        secretFiles.host = secretFile;
      };

      # Monitor participation is owned by this aspect, not by a host reverse
      # index (MON-1/MON-3). It only exists once the service can start; the
      # notification-daemon option namespace is owned by the co-selected
      # `notify` foundation aspect.
      services.notification-daemon.monitor.units."podman-omniroute" = lib.mkIf hasSecret {
        onFailure = true;
        onStart = true;
        onStop = true;
      };
    };
}
