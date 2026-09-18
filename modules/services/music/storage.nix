# Private music storage leaf (dendritic Stage 6, S6-7): owns the media
# collaboration groups, every media root/layout tmpfiles + ACL rule, the
# media permission-reconcile service, and the media-fixperms operator CLI.
# Imported only by the music composition (modules/flake/music.nix); publishes
# no aspect and is never host-imported. Paths, modes, owners, ACLs, unit name,
# and execution context are unchanged.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.services.musicStorage;

  mediaPaths = rec {
    inherit (cfg)
      libraryDir
      playlistsDir
      inboxDir
      quarantineDir
      versionArchiveRoot
      ;
    untaggedDir = "${quarantineDir}/untagged";
    approvedDir = "${quarantineDir}/approved";
    setsDir = "${cfg.storageRoot}/sets";
  };

  mediaFixPermsBin = pkgs.writeShellApplication {
    name = "media-fixperms";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      set -euo pipefail
      systemctl start media-permission-reconcile.service
    '';
  };
in
{
  options.services.musicStorage = {
    enable = lib.mkEnableOption "music media storage ownership (groups, tmpfiles/ACLs, permission reconcile)";

    storageRoot = lib.mkOption {
      type = lib.types.str;
      description = "Music storage root (mount prerequisite). Required; injected by the composition.";
    };

    libraryDir = lib.mkOption {
      type = lib.types.str;
      description = "Library directory. Required; injected by the composition.";
    };

    playlistsDir = lib.mkOption {
      type = lib.types.str;
      description = "Playlists directory. Required; injected by the composition.";
    };

    inboxDir = lib.mkOption {
      type = lib.types.str;
      description = "Inbox directory. Required; injected by the composition.";
    };

    quarantineDir = lib.mkOption {
      type = lib.types.str;
      description = "Quarantine root. Required; injected by the composition. Fixed untagged/approved subdirs are derived from it.";
    };

    versionArchiveRoot = lib.mkOption {
      type = lib.types.str;
      description = "Syncthing staggered-version archive root. Required; injected by the composition.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.music-ingest.gid = 990;
    users.groups.media.gid = 987;

    systemd.services.media-permission-reconcile = {
      description = "Reconcile ACLs and ownership on media directories";
      after = [ "local-fs.target" ];
      unitConfig.RequiresMountsFor = [ cfg.storageRoot ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart =
          let
            fixupScript = pkgs.writeShellApplication {
              name = "media-permission-reconcile";
              runtimeInputs = [
                pkgs.coreutils
                pkgs.findutils
                pkgs.acl
              ];
              text = ''
                set -euo pipefail
                fixup() { local d="$1"; [ -d "$d" ] || return 0
                  find "$d" -type d -exec chgrp music-ingest {} + -exec chmod 2775 {} +
                  find "$d" -type f -exec chgrp music-ingest {} + -exec chmod 0664 {} +
                  setfacl -R -m g:music-ingest:rwx "$d"
                  find "$d" -type d -exec setfacl -m d:g:music-ingest:rwX {} +
                  setfacl -R -m g:media:r-X "$d"
                  find "$d" -type d -exec setfacl -m d:g:media:r-X {} +
                  setfacl -R -m u:syncthing:rwx "$d"
                  find "$d" -type d -exec setfacl -m d:u:syncthing:rwX {} +
                }
                fixup "${mediaPaths.libraryDir}"
                fixup "${mediaPaths.playlistsDir}"
                fixup "${mediaPaths.quarantineDir}"
                fixup "${mediaPaths.untaggedDir}"
                fixup "${mediaPaths.approvedDir}"
                fixup "${mediaPaths.inboxDir}"
              '';
            };
          in
          "${fixupScript}/bin/media-permission-reconcile";
      };
    };

    environment.systemPackages = [ mediaFixPermsBin ];

    systemd.tmpfiles.rules = [
      "d ${mediaPaths.untaggedDir} 2775 root music-ingest - -"
      "d ${mediaPaths.approvedDir} 2775 root music-ingest - -"
      "a+ ${mediaPaths.untaggedDir} - - - - group:music-ingest:rwx"
      "a+ ${mediaPaths.untaggedDir} - - - - default:group:music-ingest:rwX"
      "a+ ${mediaPaths.untaggedDir} - - - - group:media:r-X"
      "a+ ${mediaPaths.untaggedDir} - - - - default:group:media:r-X"
      "a+ ${mediaPaths.approvedDir} - - - - group:music-ingest:rwx"
      "a+ ${mediaPaths.approvedDir} - - - - default:group:music-ingest:rwX"
      "a+ ${mediaPaths.approvedDir} - - - - group:media:r-X"
      "a+ ${mediaPaths.approvedDir} - - - - default:group:media:r-X"
      "d ${cfg.storageRoot} 0755 root root - -"
      "z ${cfg.storageRoot} 0755 root root - -"
      "d ${mediaPaths.versionArchiveRoot} 2775 root media - -"
      "d ${mediaPaths.versionArchiveRoot}/library 2775 root media - -"
      "a+ ${mediaPaths.versionArchiveRoot}/library - - - - user:syncthing:rwx"
      "a+ ${mediaPaths.versionArchiveRoot}/library - - - - default:user:syncthing:rwX"
      "d ${mediaPaths.versionArchiveRoot}/quarantine 2775 root media - -"
      "a+ ${mediaPaths.versionArchiveRoot}/quarantine - - - - user:syncthing:rwx"
      "a+ ${mediaPaths.versionArchiveRoot}/quarantine - - - - default:user:syncthing:rwX"
      "d ${mediaPaths.versionArchiveRoot}/inbox 2775 root media - -"
      "a+ ${mediaPaths.versionArchiveRoot}/inbox - - - - user:syncthing:rwx"
      "a+ ${mediaPaths.versionArchiveRoot}/inbox - - - - default:user:syncthing:rwX"
      "d ${mediaPaths.libraryDir} 2775 root music-ingest - -"
      "a+ ${mediaPaths.libraryDir} - - - - group:music-ingest:rwX"
      "a+ ${mediaPaths.libraryDir} - - - - default:group:music-ingest:rwX"
      "a+ ${mediaPaths.libraryDir} - - - - group:media:r-X"
      "a+ ${mediaPaths.libraryDir} - - - - default:group:media:r-X"
      # Playlists are a sibling of library, not a child: Navidrome reads
      # library/, so exporting under it would surface playlists as tracks.
      "d ${mediaPaths.playlistsDir} 2775 root music-ingest - -"
      "a+ ${mediaPaths.playlistsDir} - - - - group:music-ingest:rwX"
      "a+ ${mediaPaths.playlistsDir} - - - - default:group:music-ingest:rwX"
      "a+ ${mediaPaths.playlistsDir} - - - - group:media:r-X"
      "a+ ${mediaPaths.playlistsDir} - - - - default:group:media:r-X"
      "d ${mediaPaths.quarantineDir} 2775 root music-ingest - -"
      "a+ ${mediaPaths.quarantineDir} - - - - group:music-ingest:rwX"
      "a+ ${mediaPaths.quarantineDir} - - - - default:group:music-ingest:rwX"
      "a+ ${mediaPaths.quarantineDir} - - - - group:media:r-X"
      "a+ ${mediaPaths.quarantineDir} - - - - default:group:media:r-X"
      # Recorded-set uploads are a sibling of library, not a child: Navidrome
      # reads library/, so storing sets under it would index them as tracks.
      "d ${mediaPaths.setsDir} 2775 root music-ingest - -"
      "a+ ${mediaPaths.setsDir} - - - - group:music-ingest:rwX"
      "a+ ${mediaPaths.setsDir} - - - - default:group:music-ingest:rwX"
      "a+ ${mediaPaths.setsDir} - - - - group:media:r-X"
      "a+ ${mediaPaths.setsDir} - - - - default:group:media:r-X"
      "d ${mediaPaths.inboxDir} 2775 root music-ingest - -"
      "z ${mediaPaths.inboxDir} 2775 root music-ingest - -"
      "d ${mediaPaths.inboxDir}/dropbox 2775 root music-ingest - -"
      "a+ ${mediaPaths.inboxDir} - - - - group:music-ingest:rwX"
      "a+ ${mediaPaths.inboxDir} - - - - default:group:music-ingest:rwX"
      "a+ ${mediaPaths.inboxDir} - - - - group:media:r-X"
      "a+ ${mediaPaths.inboxDir} - - - - default:group:media:r-X"
      "f /var/lib/slskd/environment 0640 slskd slskd - -"
      "f /var/lib/tagr/environment 0640 root root - -"
    ];
  };
}
