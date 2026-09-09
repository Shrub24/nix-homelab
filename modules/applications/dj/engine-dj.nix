# Engine DJ library hosting on a Windows VM; guest setup is operator-driven
# (docs/runbooks/engine-dj-guest-setup.md).
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.applications.dj;
  inherit (cfg) engine;

  engineEnabled = cfg.enable && engine.enable;
  vmUnit = "windows-vm-${engine.vmName}.service";

  playlistSyncFetch = pkgs.writeShellApplication {
    name = "playlist-sync-fetch";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.findutils
      pkgs.gnugrep
      pkgs.jq
    ];
    text = ''
      set -euo pipefail
      IMPORT_DIR="$1"
      STORAGE_ROOT="$2"
      API="http://127.0.0.1:4533/rest"
      die() { echo "playlist-sync: $*" >&2; exit 1; }
      if [ -z "$ND_USER" ] || [ -z "$ND_PASS" ]; then
        die "navidrome credentials are empty"
      fi
      api() {
        endpoint="$1"
        shift
        curl -fsS -G "$API/$endpoint" \
          --data-urlencode "u=$ND_USER" \
          --data-urlencode "p=$ND_PASS" \
          --data-urlencode "f=json" \
          --data-urlencode "v=1.16.1" \
          --data-urlencode "c=playlist-sync" \
          "$@"
      }
      ok_or_die() {
        [ "$(printf "%s" "$1" | jq -r '.["subsonic-response"].status')" = "ok" ] || die "$2: $(printf "%s" "$1" | jq -r '.["subsonic-response"].error.message // "unknown error"')"
      }
      TMP="$(mktemp -d)"
      trap 'rm -rf "$TMP"' EXIT
      PL_JSON="$(api getPlaylists.view)" || die "getPlaylists request failed"
      ok_or_die "$PL_JSON" "getPlaylists"
      while IFS= read -r pl; do
        id="$(printf "%s" "$pl" | jq -r ".id")"
        name="$(printf "%s" "$pl" | jq -r ".name")"
        # Sanitize the playlist name into a non-empty, non-hidden basename so
        # the *.m3u glob stages every file; the ($id) suffix disambiguates
        # duplicate names.
        base="$(printf "%s" "$name" | tr "/" "-")"
        while [ -n "$base" ] && [ "''${base#.}" != "$base" ]; do base="''${base#.}"; done
        [ -n "$base" ] || base="playlist"
        file="''${base}.m3u"
        if [ -e "$TMP/$file" ]; then
          file="''${base} ($id).m3u"
        fi
        T_JSON="$(api getPlaylist.view --data-urlencode "id=$id")" || die "getPlaylist $name: request failed"
        ok_or_die "$T_JSON" "getPlaylist $name"
        : > "$TMP/$file"
        while IFS= read -r path; do
          case "$path" in
            /*) rel="''${path#"$STORAGE_ROOT"/library/}" ;;
            *) rel="$path" ;;
          esac
          case "$rel" in
            "") echo "playlist-sync: skip empty path" >&2 ;;
            /*) echo "playlist-sync: skip off-root path: $path" >&2 ;;
            *)
              # Reject any ".." path segment (leading, embedded, or trailing).
              case "/$rel" in
                */../*|*/..) echo "playlist-sync: skip escaping path: $path" >&2 ;;
                *) printf "%s\n" "/music/$rel" >> "$TMP/$file" ;;
              esac
              ;;
          esac
        done < <(printf "%s" "$T_JSON" | jq -r '.["subsonic-response"].playlist.entry // [] | (if type == "array" then . else [.] end) | .[].path // empty')
        if [ ! -s "$TMP/$file" ]; then
          echo "playlist-sync: skip empty playlist: $name"
          rm -f "$TMP/$file"
        fi
      done < <(printf "%s" "$PL_JSON" | jq -c '.["subsonic-response"].playlists.playlist // [] | (if type == "array" then . else [.] end) | .[] | {id: (.id | tostring), name}')
      if [ -z "$(find "$TMP" -maxdepth 1 -mindepth 1 -print -quit)" ]; then
        die "exported no playlists, aborting"
      fi
      staged=$(find "$TMP" -maxdepth 1 -name "*.m3u" | wc -l)
      rm -f "$IMPORT_DIR"/*.m3u
      mv "$TMP"/*.m3u "$IMPORT_DIR"/
      rmdir "$TMP"
      trap - EXIT
      echo "playlist-sync: staged $staged playlists"
    '';
  };

  playlistSyncBin = pkgs.writeShellApplication {
    name = "playlist-sync";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      set -euo pipefail
      systemd-run --pipe --wait \
        --unit="playlist-sync-$(date -u +"%Y%m%dT%H%M%SZ")" \
        -p User=playlist-sync \
        -p Group=music-ingest \
        -p EnvironmentFile=${config.sops.templates."playlist-sync-env".path} \
        -p ReadWritePaths=${engine.traktorStateDir}/import \
        -- \
        ${playlistSyncFetch}/bin/playlist-sync-fetch \
          ${engine.traktorStateDir}/import \
          ${engine.musicStorageRoot}
      /run/wrappers/bin/sudo /run/current-system/sw/bin/systemctl start traktor-m3u-sync-import@navidrome.service
      echo "playlist-sync: import started; engine export chains via onSuccess."
      echo "status: sudo systemctl status 'traktor-m3u-sync-import@navidrome' 'traktor-m3u-sync-export@engine' --no-pager"
    '';
  };

in
{
  imports = [
    ../../services/virtualisation/windows-vm.nix
  ];

  options.applications.dj = {
    engine = {
      enable = lib.mkEnableOption "Engine DJ library hosting on a Windows VM";

      vmName = lib.mkOption {
        type = lib.types.str;
        default = "windows-dj";
        description = "windows-vm instance name hosting Engine DJ.";
      };

      sharePath = lib.mkOption {
        type = lib.types.str;
        description = "Root exported to the guest (drive M:). Required; injected by the caller.";
      };

      musicStorageRoot = lib.mkOption {
        type = lib.types.str;
        description = "Music library root (Engine Database2, playlists); host/music-owned. Required.";
      };

      traktorStateDir = lib.mkOption {
        type = lib.types.str;
        description = "traktor-m3u-sync worker state root (SQLite store + inbound M3U drop). Required.";
      };
      setupPackage = lib.mkOption {
        type = lib.types.package;
        description = "Windows guest setup payload shared into the guest; provided by the flake dj aspect.";
      };
      secretFiles.navidrome = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "SOPS file carrying navidrome_username/navidrome_password for the playlist-sync API fetch.";
      };

      vcpu = lib.mkOption {
        type = lib.types.ints.positive;
        default = 4;
        description = "Guest vCPU count.";
      };

      memoryGiB = lib.mkOption {
        type = lib.types.ints.positive;
        default = 8;
        description = "Guest memory in GiB.";
      };

      spicePort = lib.mkOption {
        type = lib.types.port;
        default = 5900;
        description = "Loopback SPICE port for remote display (SSH tunnel over Tailscale).";
      };
    };
  };

  config = lib.mkIf engineEnabled {
    users.groups.music-ingest.gid = lib.mkDefault 990;

    services = {
      windows-vm = {
        enable = true;
        instances.${engine.vmName} = {
          inherit (engine) vcpu spicePort;
          memory = engine.memoryGiB * 1024;
          tpm = true; # Windows 11 installer requires emulated TPM 2.0
          shares = {
            media = {
              source = engine.sharePath;
              readonly = false;
            };
            setup = {
              source = "${engine.setupPackage}";
              readonly = true;
            };
          };
        };
      };

      traktor-m3u-sync = {
        enable = true;
        supplementaryGroups = [
          "media"
          "music-ingest"
          "navidrome"
        ];
        states.library.path = "${engine.traktorStateDir}/store.db";
        jobs = {
          navidrome = {
            action = "import";
            state = "library";
            format = "m3u";
            m3u.library_root = "/music";
            m3u.import_dir = "${engine.traktorStateDir}/import";
            onSuccess = [ "engine" ];
          };
          engine = {
            action = "export";
            state = "library";
            format = "engine";
            # The Engine library is a real directory on the M: music share; the
            # SQLite DB lives at Engine Library/Database2 (guest M:\Engine Library).
            engine.database_path = "${engine.musicStorageRoot}/Engine Library/Database2/m.db";
            # Engine stores Track paths relative to the Database2 parent.
            engine.track_path_prefix = "../library";
          };
          itunes = {
            action = "export";
            state = "library";
            format = "itunes";
            itunes = {
              output_file = "${engine.musicStorageRoot}/playlists/iTunes Music Library.xml";
              location_base = "file://localhost/M:/library";
              check_base_path = "${engine.musicStorageRoot}/library";
            };
          };
        };
      };

      # Quiesce contract: stop the VM only if it was running. The Engine library
      # rides the music storage root, which the media backup already covers in
      # the same window (lib.unique deduplicates the path), so this service
      # contributes only the quiesce hooks and never backs unused /srv/data.
      state-backups.services.engine-dj = {
        enable = true;
        mode = "quiesce";
        paths = [ engine.musicStorageRoot ];
        prepareCommands = [
          ''
            state=$(${pkgs.libvirt}/bin/virsh domstate ${engine.vmName} 2>/dev/null) || {
              echo "engine-dj: cannot determine ${engine.vmName} state, aborting backup" >&2
              exit 1
            }
            if [ "$state" != "shut off" ]; then
              touch /run/windows-vm-${engine.vmName}.backup-was-running
              ${config.services.windows-vm.scripts.stop}/bin/windows-vm-stop ${engine.vmName} 180
            fi
          ''
        ];
        cleanupCommands = [
          ''
            if [ -f /run/windows-vm-${engine.vmName}.backup-was-running ]; then
              rm -f /run/windows-vm-${engine.vmName}.backup-was-running
              ${config.services.windows-vm.scripts.start}/bin/windows-vm-start ${engine.vmName}
            fi
          ''
        ];
      };
    };

    assertions = [
      {
        assertion = engine.secretFiles.navidrome != null;
        message = "applications.dj.engine.secretFiles.navidrome must be set (Navidrome API credentials for playlist-sync).";
      }
    ];

    sops.secrets."navidrome_username" = {
      sopsFile = engine.secretFiles.navidrome;
      owner = "playlist-sync";
    };
    sops.secrets."navidrome_password" = {
      sopsFile = engine.secretFiles.navidrome;
      owner = "playlist-sync";
    };
    sops.templates."playlist-sync-env" = {
      owner = "playlist-sync";
      mode = "0400";
      content = ''
        ND_USER=${config.sops.placeholder.navidrome_username}
        ND_PASS=${config.sops.placeholder.navidrome_password}
      '';
    };

    environment.systemPackages = [ playlistSyncBin ];

    systemd = {
      # Linux-side writers bind this target to inherit mutual exclusion with the VM.
      targets.dj-library-writers = {
        description = "Engine DJ library Linux-side writers (mutually exclusive with ${vmUnit})";
      };
      services."windows-vm-${engine.vmName}".conflicts = [ "dj-library-writers.target" ];
      services.restic-backups-state.conflicts = [ "dj-library-writers.target" ];
      # The playlist-sync import and its chained engine export both write the
      # Engine library DB; bind them to the writer target so starting either
      # stops the VM and starting the VM stops them (BindsTo implies Requires
      # + After on the target, which conflicts with the VM unit).
      services."traktor-m3u-sync-import@navidrome" = {
        bindsTo = [ "dj-library-writers.target" ];
        after = [ "dj-library-writers.target" ];
      };
      services."traktor-m3u-sync-export@engine" = {
        bindsTo = [ "dj-library-writers.target" ];
        after = [ "dj-library-writers.target" ];
      };
      tmpfiles.rules = [
        "d '${engine.musicStorageRoot}/Engine Library' 0755 root root - -"
        "z '${engine.musicStorageRoot}/Engine Library/Database2' 0770 playlist-sync music-ingest -"
        "d ${engine.sharePath} 2770 root music-ingest - -"
        "d ${engine.traktorStateDir} 0750 playlist-sync music-ingest -"
        "d ${engine.traktorStateDir}/import 0770 playlist-sync music-ingest -"
      ];
    };
  };
}
