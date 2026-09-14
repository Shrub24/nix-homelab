{
  lib,
  pkgs,
  ...
}:
let
  secretHelpers = import ../../../lib/secrets.nix { inherit lib; };
in
{
  # Host-local admin runtime remainder (decouple-identity-admin-capabilities
  # 3.3): the `/srv/data` operator ACL/reconcile unit and the admin SSH
  # identity SOPS registrations. Both are la-admin-1 machine facts (the SSH
  # secrets are consumed only by the disabled/deferred Quantum workload), so
  # they stay host-local instead of behind a public placement aspect.
  sops.secrets = secretHelpers.mkSecretsFromMap ../../../secrets/applications/admin.yaml {
    admin_ssh_identity = {
      key = "admin/ssh/identity";
      path = "/run/secrets/admin.ssh.identity";
      owner = "root";
      group = "root";
    };
    admin_ssh_known_hosts = {
      key = "admin/ssh/known_hosts";
      path = "/run/secrets/admin.ssh.known_hosts";
      owner = "root";
      group = "root";
    };
  };

  systemd.tmpfiles.rules = [
    "d /srv/data 0755 root root - -"
    "z /srv/data 0755 root root - -"
    "a+ /srv/data - - - - user:dev:r-X"
    "a+ /srv/data - - - - default:user:dev:r-X"
  ];

  systemd.services.admin-dev-data-access-reconcile = {
    description = "Reconcile dev read/traverse access on admin data root";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "admin-dev-data-access-reconcile" ''
        set -euo pipefail
        if [ -d "/srv/data" ]; then
          ${pkgs.acl}/bin/setfacl -m u:dev:rX "/srv/data"
          find "/srv/data" -xdev -type d ! -path "/srv/data/quantum/mnt" ! -path "/srv/data/quantum/mnt/*" -exec ${pkgs.acl}/bin/setfacl -m d:u:dev:rX {} +
        fi
      '';
    };
  };
}
