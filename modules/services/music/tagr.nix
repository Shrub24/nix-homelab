{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.services.tagr;
  secretHelpers = import ../../../lib/secrets.nix { inherit lib; };
  ingestGid = toString config.users.groups.music-ingest.gid;
  mediaGid = toString config.users.groups.media.gid;
in
{
  options.services.tagr = {
    enable = lib.mkEnableOption "Tagr manual metadata editor";

    dataDir = lib.mkOption {
      type = lib.types.str;
      description = "Persistent data directory for Tagr. Required; injected by the caller.";
    };

    libraryPath = lib.mkOption {
      type = lib.types.str;
      description = "Music library directory bind-mounted read-write into the container. Required; injected by the caller.";
    };

    quarantinePath = lib.mkOption {
      type = lib.types.str;
      description = "Music quarantine directory bind-mounted read-write into the container. Required; injected by the caller.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/tagr/environment";
      description = "Environment file containing Tagr auth values.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Listen address for host port mapping.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3003;
      description = "Tagr web UI port on the host.";
    };

    backup.exportFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/state-backups/tagr/tagr.sqlite3";
      description = "SQLite backup artifact path captured alongside Tagr raw state.";
    };

    secretFiles.host = secretHelpers.mkSecretFileOption "tagr-host-secrets";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      (secretHelpers.mkRequiredSecretAssertion {
        enable = cfg.enable;
        file = cfg.secretFiles.host;
        feature = "services.tagr";
        label = "secretFiles.host";
      })
    ];

    sops.templates."tagr.env" = {
      owner = "root";
      group = "root";
      mode = "0400";
      content = ''
        AUTH_SECRET=${config.sops.placeholder.tagr_auth_secret}
        AUTH_USER=${config.sops.placeholder.tagr_auth_user}
        AUTH_PASSWORD=${config.sops.placeholder.tagr_auth_password}
      '';
    };

    sops.secrets.tagr_auth_secret = {
      sopsFile = cfg.secretFiles.host;
      key = "tagr/auth_secret";
      path = "/run/secrets/tagr.auth_secret";
    };

    sops.secrets.tagr_auth_user = {
      sopsFile = cfg.secretFiles.host;
      key = "tagr/auth_user";
      path = "/run/secrets/tagr.auth_user";
    };

    sops.secrets.tagr_auth_password = {
      sopsFile = cfg.secretFiles.host;
      key = "tagr/auth_password";
      path = "/run/secrets/tagr.auth_password";
    };

    virtualisation.podman.enable = true;

    systemd.tmpfiles.rules = [
      # tagr container writes /data/tagr.db as uid 1001 in group music-ingest
      # (PGID + --group-add); z re-converges the dir when a restore drifts it.
      "d ${cfg.dataDir} 2770 root music-ingest - -"
      "z ${cfg.dataDir} 2770 root music-ingest - -"
      # SQLite export parent: the export prepare command runs in the restic
      # backup unit as root, so the staging dir is root-owned 0700.
      "d ${builtins.dirOf cfg.backup.exportFile} 0700 root root - -"
    ];

    virtualisation.oci-containers.containers.tagr = {
      autoStart = true;
      image = config.repo.ociImages.tagr;
      ports = [ "${cfg.listenAddress}:${toString cfg.port}:3000" ];
      environment = {
        DATABASE_URL = "file:/data/tagr.db";
        MUSIC_FOLDERS = "/music/library,/music/quarantine";
        PUID = "1001";
        PGID = ingestGid;
      };
      environmentFiles = [ config.sops.templates."tagr.env".path ];
      extraOptions = [
        "--group-add=${ingestGid}"
        "--group-add=${mediaGid}"
      ];
      volumes = [
        "${cfg.dataDir}:/data"
        "${cfg.libraryPath}:/music/library:rw"
        "${cfg.quarantinePath}:/music/quarantine:rw"
      ];
    };

    systemd.services."podman-tagr" = {
      wants = [
        "network-online.target"
        "syncthing.service"
      ];
      after = [
        "network-online.target"
        "syncthing.service"
      ];
      unitConfig.RequiresMountsFor = [
        cfg.dataDir
        cfg.libraryPath
        cfg.quarantinePath
      ];
      serviceConfig.SupplementaryGroups = lib.mkAfter [
        "music-ingest"
        "media"
      ];
    };

    services.state-backups.services.tagr = {
      enable = true;
      mode = "export";
      paths = [ cfg.dataDir ];
      exportPaths = [ cfg.backup.exportFile ];
      prepareCommands = [
        ''
          rm -f ${cfg.backup.exportFile}
          ${pkgs.sqlite}/bin/sqlite3 ${cfg.dataDir}/tagr.db ".backup ${cfg.backup.exportFile}"
        ''
      ];
    };
  };
}
