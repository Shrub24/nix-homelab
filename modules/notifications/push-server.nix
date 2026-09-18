# ntfy push-server deployment aspect (dendritic Stage 7, D-053). Published from
# this discovered contributor and selected only on `la-admin-1` (S7-2); the
# ntfy server leaf is the intrinsic implementation and selection supplies the
# existing top-level enablement. Host-scoped variants (Firebase key, auth secret
# file, and the loopback server URL consumed by the notification daemon) stay
# host-set.
#
# Publisher authorization is fleet policy, not an LA machine fact, so it lives
# here and is validated against the canonical host records: every publisher must
# be a declared host ID, and the module derives the ntfy `auth-access` entries
# from it. The matching `auth-users`/`auth-tokens` provisioning stays in the
# encrypted `auth.secretFiles.auth` (see `secrets/.templates/services/ntfy.yaml`);
# `tests/phase-la-admin-contract.sh` pins policy membership against that
# plaintext template so the two cannot drift.
top@{ lib, ... }:
let
  publishers = {
    "oci-melb-1" = "write-only";
    "la-admin-1" = "write-only";
    "home-forge" = "write-only";
  };

  unknownPublishers = lib.filter (id: !(top.config.nixos.hosts ? ${id})) (
    builtins.attrNames publishers
  );
in
{
  flake.modules.nixos.push-server = {
    imports = [ ../services/ntfy.nix ];

    # Selecting this aspect is the server's top-level enablement.
    services.ntfy.enable = true;

    services.ntfy.auth.publishers = publishers;

    assertions = [
      {
        assertion = unknownPublishers == [ ];
        message = "push-server: notification publisher '${builtins.concatStringsSep "', '" unknownPublishers}' is not a declared canonical host ID";
      }
    ];
  };
}
