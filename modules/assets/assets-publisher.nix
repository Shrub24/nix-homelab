{ self, ... }:
{
  perSystem = { pkgs, ... }: {
    checks.assets-publisher =
      pkgs.runCommand "check-assets-publisher"
        { nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.boto3 ])) ]; }
        ''
          python ${self}/tests/test-assets-publisher.py
          touch "$out"
        '';
  };

  flake.modules.nixos.assets-publisher =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      policy = import ../../policy/assets.nix;
      # Only entries under our public URL are ours to upload.
      prefix = "${policy.publicUrl}/";
      keyOf =
        entry:
        if lib.hasPrefix prefix entry.url then
          lib.removePrefix prefix entry.url
        else
          throw "assets-publisher: ${entry.url} is outside ${policy.publicUrl}, so its file has no destination";
      published = lib.filterAttrs (_name: entry: entry ? file) policy.brand;
      objects = map (entry: {
        inherit (entry) file;
        key = keyOf entry;
      }) (lib.attrValues published);
      secretFile = ../../secrets/services/assets.yaml;
      python = pkgs.python3.withPackages (ps: [ ps.boto3 ]);
      credentialFile = config.sops.templates."assets-publisher.env".path;
      specification = pkgs.writeText "assets-publish.json" (
        builtins.toJSON {
          inherit (policy) bucket endpoint;
          inherit objects;
        }
      );
    in
    {
      assertions = [
        {
          assertion = lib.length (lib.unique (map (object: object.key) objects)) == lib.length objects;
          message = "assets-publisher: published assets must own distinct object keys.";
        }
      ];

      sops.secrets = {
        assets-access-key-id = {
          sopsFile = secretFile;
          key = "access_key_id";
          path = "/run/secrets/assets-access-key-id";
        };
        assets-secret-access-key = {
          sopsFile = secretFile;
          key = "secret_access_key";
          path = "/run/secrets/assets-secret-access-key";
        };
      };
      sops.templates."assets-publisher.env" = {
        mode = "0400";
        restartUnits = [ "assets-publish.service" ];
        content = ''
          AWS_ACCESS_KEY_ID=${config.sops.placeholder.assets-access-key-id}
          AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.assets-secret-access-key}
        '';
      };

      systemd.services.assets-publish = {
        description = "Publish fleet-owned public assets";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [
          "network-online.target"
          "sops-install-secrets.service"
        ];
        restartTriggers = [
          specification
          secretFile
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "no";
          TimeoutStartSec = 300;
          EnvironmentFile = credentialFile;
          Environment = [
            "AWS_EC2_METADATA_DISABLED=true"
            "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          ];
          ExecStart = "${python}/bin/python ${./_publish.py} ${specification}";
          DynamicUser = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
        };
      };
    };
}
