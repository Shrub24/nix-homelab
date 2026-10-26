{
  config,
  lib,
  ...
}:
let
  cfg = config.services.authentik;
  upstreamUnits = [
    "authentik.service"
    "authentik-worker.service"
    "authentik-migrate.service"
  ];
  runtime = config.systemd.services.authentik;
  script = ./gate.py;
  command = "exec(compile(open('${script}').read(), '${script}', 'exec'))";
in
{
  config = lib.mkIf cfg.enable {
    systemd.services.authentik-blueprint-validate = {
      wantedBy = [ "multi-user.target" ];
      requires = upstreamUnits;
      after = upstreamUnits;
      restartTriggers = [
        script
        cfg.settings.blueprints_dir
        config.environment.etc."authentik/config.yml".source
      ];
      path = runtime.path;
      environment = (removeAttrs runtime.environment [ "PATH" ]) // {
        AUTHENTIK_BLUEPRINT_PATH = "${cfg.settings.blueprints_dir}/homelab-identity.yaml";
      };
      script = ''
        exec ${cfg.authentikComponents.manage}/bin/manage.py shell --no-imports -c ${lib.escapeShellArg command}
      '';
      serviceConfig =
        (lib.getAttrs [
          "DynamicUser"
          "User"
          "StateDirectory"
          "WorkingDirectory"
          "UMask"
        ] runtime.serviceConfig)
        // {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "360s";
          EnvironmentFile = lib.optional (cfg.environmentFile != null) cfg.environmentFile;
        };
    };
  };
}
