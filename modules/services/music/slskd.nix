{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.services.slskd;
  secretHelpers = import ../../../lib/secrets.nix { inherit lib; };
  downloadsParent = builtins.dirOf cfg.downloadsPath;
  incompleteParent = builtins.dirOf cfg.incompletePath;
in
{
  options.services.slskd.downloadsPath = lib.mkOption {
    type = lib.types.str;
    default = "/srv/media/inbox/slskd";
    description = "Directory for completed slskd downloads.";
  };

  options.services.slskd.incompletePath = lib.mkOption {
    type = lib.types.str;
    default = "/srv/media/slskd-incomplete";
    description = "Directory for incomplete slskd downloads.";
  };

  options.services.slskd.secretFiles.host = secretHelpers.mkSecretFileOption "slskd-host-secrets";

  options.services.slskd.downloadCompleteScript = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    description = "Script to run on slskd DownloadDirectoryComplete events (debounced).";
  };

  config = lib.mkIf (cfg.secretFiles.host != null) {
    assertions = [
      (secretHelpers.mkRequiredSecretAssertion {
        enable = cfg.secretFiles.host != null;
        file = cfg.secretFiles.host;
        feature = "services.slskd";
        label = "secretFiles.host";
      })
    ];

    sops.templates."slskd.env" = lib.mkIf (cfg.secretFiles.host != null) {
      owner = "slskd";
      group = "slskd";
      mode = "0400";
      content = ''
        SLSKD_SLSK_USERNAME=${config.sops.placeholder.slskd_slsk_username}
        SLSKD_SLSK_PASSWORD=${config.sops.placeholder.slskd_slsk_password}
        ${lib.optionalString (
          config.sops ? placeholder.soulsync_slskd_api_key
        ) "SLSKD_API_KEY=${config.sops.placeholder.soulsync_slskd_api_key}"}
        SLSKD_NO_AUTH=false
        SLSKD_USERNAME=api-only
        SLSKD_PASSWORD=${config.sops.placeholder.slskd_web_password}
      '';
    };

    sops.secrets.slskd_slsk_username = {
      sopsFile = cfg.secretFiles.host;
      key = "slskd/slsk_username";
      path = "/run/secrets/slskd.slsk_username";
      owner = "slskd";
      group = "slskd";
    };

    sops.secrets.slskd_slsk_password = {
      sopsFile = cfg.secretFiles.host;
      key = "slskd/slsk_password";
      path = "/run/secrets/slskd.slsk_password";
      owner = "slskd";
      group = "slskd";
    };

    sops.secrets.slskd_web_password = {
      sopsFile = cfg.secretFiles.host;
      key = "slskd/web_password";
      path = "/run/secrets/slskd.web_password";
      owner = "slskd";
      group = "slskd";
    };

    services.slskd = {
      enable = true;
      openFirewall = false;
      settings = {
        directories = {
          downloads = cfg.downloadsPath;
          incomplete = cfg.incompletePath;
        };
        shares.directories = [
          "/srv/media/library"
        ];
      }
      // lib.optionalAttrs (cfg.downloadCompleteScript != null) {
        integration.scripts.download_complete = {
          on = [ "DownloadDirectoryComplete" ];
          run = {
            executable = "${pkgs.bash}/bin/bash";
            arglist = [
              cfg.downloadCompleteScript
            ];
          };
        };
      };
      environmentFile = config.sops.templates."slskd.env".path;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.downloadsPath} 0775 slskd music-ingest - -"
      "z ${cfg.downloadsPath} 0775 slskd music-ingest - -"
      "d ${cfg.incompletePath} 0775 slskd music-ingest - -"
      "z ${cfg.incompletePath} 0775 slskd music-ingest - -"
    ];

    systemd.services.slskd = {
      unitConfig.RequiresMountsFor = [
        cfg.downloadsPath
        cfg.incompletePath
      ];
      wants = [
        "network-online.target"
        "syncthing.service"
      ];
      after = [
        "network-online.target"
        "syncthing.service"
      ];
      serviceConfig.ReadWritePaths = lib.mkAfter (
        lib.unique [
          "/srv/media"
          downloadsParent
          incompleteParent
          cfg.downloadsPath
          cfg.incompletePath
        ]
      );
      serviceConfig.PrivateMounts = lib.mkForce false;
      serviceConfig.ProtectSystem = lib.mkForce "off";
      serviceConfig.SupplementaryGroups = lib.mkAfter [
        "music-ingest"
        "media"
      ];
    };
  };
}
