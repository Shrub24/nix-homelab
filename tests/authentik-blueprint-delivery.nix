{ pkgs, authentikModule }:
pkgs.testers.runNixOSTest {
  name = "authentik-blueprint-delivery";
  nodes.machine =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      directory =
        valid:
        pkgs.runCommand "authentik-test-blueprints" { } ''
          mkdir -p $out
          cp -r ${config.services.authentik.authentikComponents.staticWorkdirDeps}/blueprints/. $out/
          cat > $out/homelab-identity.yaml <<'YAML'
          version: 1
          metadata:
            name: homelab-identity
          entries:
            - model: authentik_core.group
              id: gate-group
              identifiers:
                name: blueprint-gate-test
              attrs:
                name: blueprint-gate-test
                ${lib.optionalString (!valid) "parents: [!KeyOf nonexistent-parent]"}
          YAML
        '';
    in
    {
      imports = [
        authentikModule
        ../modules/identity/authentik/_blueprint/gate.nix
      ];
      virtualisation = {
        cores = 3;
        memorySize = 3072;
      };
      systemd.tmpfiles.rules = [
        "f /etc/authentik.env 0600 root root - AUTHENTIK_SECRET_KEY=test-only-not-a-credential"
      ];
      services.authentik = {
        enable = true;
        environmentFile = "/etc/authentik.env";
        settings = {
          disable_update_check = true;
          blueprints_dir = directory true;
          listen.http = [ "127.0.0.1:9000" ];
          listen.https = [ "127.0.0.1:9443" ];
        };
      };
      specialisation.invalid.configuration.services.authentik.settings.blueprints_dir = lib.mkForce (
        directory false
      );
    };
  testScript = ''
    start_all()
    machine.wait_for_unit("authentik-blueprint-validate.service", timeout=240)
    machine.succeed("systemctl show authentik-blueprint-validate -p Result | grep '=success'")

    with subtest("stale success is not accepted as the current application"):
        machine.succeed("ak shell --no-imports -c \"from authentik.blueprints.models import BlueprintInstance; BlueprintInstance.objects.filter(path='homelab-identity.yaml').update(last_applied_hash='stale')\"")
        machine.succeed("systemctl restart authentik-blueprint-validate.service")
        machine.succeed("ak shell --no-imports -c \"from authentik.blueprints.models import BlueprintInstance; assert BlueprintInstance.objects.get(path='homelab-identity.yaml').last_applied_hash != 'stale'\"")

    with subtest("an invalid reference fails real activation"):
        original = machine.succeed("readlink -f /run/current-system").strip()
        machine.fail(f"{original}/specialisation/invalid/bin/switch-to-configuration test")
        machine.succeed("systemctl is-failed authentik-blueprint-validate.service")
        machine.succeed(f"{original}/bin/switch-to-configuration test")
        machine.wait_for_unit("authentik-blueprint-validate.service")

    with subtest("a stalled worker cannot turn old success into acceptance"):
        machine.succeed("mkdir -p /run/systemd/system/authentik-blueprint-validate.service.d; printf '[Service]\\nEnvironment=AUTHENTIK_BLUEPRINT_TIMEOUT=3\\n' > /run/systemd/system/authentik-blueprint-validate.service.d/timeout.conf; systemctl daemon-reload")
        machine.succeed("systemctl kill --signal=STOP --kill-whom=all authentik-worker.service")
        try:
            machine.fail("systemctl restart authentik-blueprint-validate.service")
            machine.succeed("journalctl -u authentik-blueprint-validate.service --no-pager | grep TimeoutError")
        finally:
            machine.succeed("systemctl kill --signal=CONT --kill-whom=all authentik-worker.service")
  '';
}
