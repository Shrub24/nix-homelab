{ pkgs, ... }:
{
  # Host-local admin runtime remainder (decouple-identity-admin-capabilities
  # 3.3): the `/srv/data` operator ACL and its reconcile unit. The admin SSH
  # identity registrations existed only for the retired Quantum workload and
  # were removed with it (2026-09-21).
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
          find "/srv/data" -xdev -type d -exec ${pkgs.acl}/bin/setfacl -m d:u:dev:rX {} +
        fi
      '';
    };
  };
}
