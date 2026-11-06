# Real provisioning path for consumer logins: boots a NixOS node running the substrate and
# authenticates as the roles it created. Only secret delivery is substituted — the test writes
# the same files sops activation would — because sops decryption is not ours to test.
{
  pkgs,
  sopsModule,
}:
let
  passwordDir = "/run/secrets/postgres";
in
pkgs.testers.runNixOSTest {
  name = "postgres-consumer-roles";

  nodes.machine =
    { lib, ... }:
    let
      # The consumer contract requires a declared secret file to exist; nothing decrypts it.
      passwordSource = ./fixtures/postgres-roles-passwords.yaml;
      password = role: {
        file = passwordSource;
        key = "roles/${role}/password";
      };
      # The file publishes its body as a flake aspect; the node consumes the aspect.
      postgresAspect = (import ../modules/database/postgres.nix { }).flake.modules.nixos.postgres;
    in
    {
      imports = [
        sopsModule
        postgresAspect
      ];

      services.postgres.instances.main = {
        port = 5432;
        dataDir = "/var/lib/postgresql";
      };

      services.postgres.consumers.app = {
        database = "appdb";
        role = "app_owner";
        auth = "scram";
        password = password "app_owner";
        allowedCIDRs = [ "127.0.0.1/32" ];
        additionalRoles.app_login.password = password "app_login";
      };

      services.postgres.consumers.other = {
        database = "otherdb";
        role = "other_owner";
        auth = "scram";
        password = password "other_owner";
        allowedCIDRs = [ "127.0.0.1/32" ];
      };

      sops.secrets = lib.mkForce { };

      system.activationScripts.postgresRolePasswords.text = ''
        install -d -m 0755 -o root -g root ${passwordDir}
        printf '%s' owner-initial > ${passwordDir}/app.password
        printf '%s' login-initial > ${passwordDir}/app-app_login.password
        printf '%s' other-initial > ${passwordDir}/other.password
        chmod 0644 ${passwordDir}/app.password ${passwordDir}/app-app_login.password ${passwordDir}/other.password
      '';

      environment.systemPackages = [ pkgs.postgresql_17 ];
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("postgresql.service")
    machine.wait_for_unit("postgresql-provision.service")

    def psql(user, password, database, sql):
        return machine.succeed(
            f"PGPASSWORD={password} psql -h 127.0.0.1 -U {user} -d {database} -tAc {sql!r}"
        ).strip()

    def refused(user, password, database, sql="SELECT 1"):
        return machine.fail(
            f"PGPASSWORD={password} psql -h 127.0.0.1 -U {user} -d {database} -tAc {sql!r}"
        )

    assert psql("app_owner", "owner-initial", "appdb", "SELECT current_user") == "app_owner"
    assert psql("app_login", "login-initial", "appdb", "SELECT current_user") == "app_login"
    machine.succeed("systemctl restart postgresql-provision.service")
    machine.wait_for_unit("postgresql-provision.service")
    assert (
        psql("app_owner", "owner-initial", "appdb",
             "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = 'appdb'")
        == "app_owner"
    )

    refused("app_login", "login-initial", "otherdb")
    refused("app_login", "login-initial", "appdb", "CREATE ROLE escalated")

    machine.succeed(
        "PGPASSWORD=owner-initial psql -h 127.0.0.1 -U app_owner -d appdb -tAc "
        "'CREATE TABLE entry (value int); INSERT INTO entry VALUES (42); "
        "GRANT SELECT ON entry TO app_login'"
    )
    machine.succeed(
        "printf '%s' login-rotated > ${passwordDir}/app-app_login.password"
        " && chmod 0644 ${passwordDir}/app-app_login.password"
    )
    machine.succeed("systemctl restart postgresql-provision.service")
    machine.wait_for_unit("postgresql-provision.service")

    assert psql("app_login", "login-rotated", "appdb", "SELECT value FROM entry") == "42"
    refused("app_login", "login-initial", "appdb")
    assert psql("app_owner", "owner-initial", "appdb", "SELECT current_user") == "app_owner"
  '';
}
