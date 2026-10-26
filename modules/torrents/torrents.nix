# Native torrent client and indexer UIs, reachable only through tailscale0.
_: {
  flake.modules.nixos.torrents =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.torrents;
      secretHelpers = import ../../lib/secrets.nix { inherit lib; };
      globals = import ../../policy/globals.nix;
      webui = config.repo.web.catalog.qbittorrent.endpoint;
      indexers = config.repo.web.catalog.prowlarr.endpoint;
      downloadDir = "/srv/storage/media/downloads";
      # Host-header validation compares the browser's Host against this semicolon-separated
      # list. The catalog endpoint is loopback for a colocated consumer, so the tailnet name
      # a browser sends has to be derived from the host itself.
      serverDomains = "${config.networking.hostName}.${globals.tailnet.suffix};127.0.0.1";
    in
    {
      options.services.torrents.peerPort = lib.mkOption {
        type = lib.types.port;
        default = 43750;
        description = ''
          BT peer port for qBittorrent, opened in the firewall and forwarded on the router.
          The default avoids 6881, which private trackers ban as a well-known client port.
        '';
      };

      options.services.torrents.secretFiles.host =
        secretHelpers.mkSecretFileOption "torrent-client-secrets";

      config = {
        assertions = [
        ];

        sops.secrets.qbittorrent_webui_password = {
          sopsFile = cfg.secretFiles.host;
          key = "qbittorrent/webui_password";
          restartUnits = [ "qbittorrent.service" ];
        };

        services = {
          prowlarr = {
            enable = true;
            # All addresses, but the firewall admits the port only on the trusted tailscale0 interface.
            settings.server = {
              bindaddress = "*";
              port = indexers.port;
            };
          };

          qbittorrent = {
            enable = true;
            webuiPort = webui.port;
            torrentingPort = cfg.peerPort;
            serverConfig = {
              Preferences.WebUI = {
                Address = "*";
                ServerDomains = serverDomains;
                Username = "admin";
                Password_PBKDF2 = "@SOPS_WEBUI_PASSWORD@";
              };
              BitTorrent.Session = {
                DefaultSavePath = downloadDir;
                GlobalUPSpeedLimit = 4750;
                MaxConnections = 1200;
                MaxConnectionsPerTorrent = 180;
                MaxUploads = 20;
                MaxUploadsPerTorrent = 11;
                QueueingSystemEnabled = true;
                MaxActiveDownloads = 6;
                MaxActiveUploads = 3;
                MaxActiveTorrents = 8;
              };
            };
          };
        };

        networking.firewall = {
          allowedTCPPorts = [ cfg.peerPort ];
          allowedUDPPorts = [ cfg.peerPort ];
        };

        systemd = {
          tmpfiles.rules = [ "d ${downloadDir} 2775 qbittorrent qbittorrent - -" ];
          services.qbittorrent = {
            unitConfig.RequiresMountsFor = [ downloadDir ];
            serviceConfig = {
              LoadCredential = [
                "webui-password:${config.sops.secrets.qbittorrent_webui_password.path}"
              ];
              # Run after nixpkgs installs its generated INI.
              ExecStartPre = lib.mkAfter [
                "${pkgs.python3}/bin/python3 ${./_torrents/set-webui-password.py} ${config.services.qbittorrent.profileDir}/qBittorrent/config/qBittorrent.conf"
              ];
            };
          };
        };
      };
    };
}
