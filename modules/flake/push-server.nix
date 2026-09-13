# ntfy push-server deployment aspect (dendritic Stage 7, D-053). Published from
# this discovered contributor and selected only on `la-admin-1` (S7-2); the
# ntfy server leaf is the intrinsic implementation and selection supplies the
# existing top-level enablement. Host-scoped variants (Firebase key, auth ACL,
# auth secret file, and the loopback server URL consumed by the notification
# daemon) stay host-set.
{ ... }:
{
  flake.modules.nixos.push-server = {
    imports = [ ../services/ntfy.nix ];

    # Selecting this aspect is the server's top-level enablement.
    services.ntfy.enable = true;
  };
}
