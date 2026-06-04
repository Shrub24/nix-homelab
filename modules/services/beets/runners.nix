{
  pkgs,
  lib,
  beets,
  mediaPaths,
  dataDir,
  notify,
}:

let
  mkRunnerBin =
    name: text: runtimeInputs:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = "set -euo pipefail\n${text}";
    };

  mkMediaCheck = dir: ''
    if ! find "${dir}" -type f \( -iname '*.mp3' -o -iname '*.flac' -o -iname '*.m4a' \
      -o -iname '*.aac' -o -iname '*.ogg' -o -iname '*.opus' \
      -o -iname '*.wav' -o -iname '*.aiff' -o -iname '*.aif' \
    \) -print -quit 2>/dev/null | grep -q .; then
      echo "no media in ${dir}"
      exit 0
    fi
  '';

  mkSettleCheck = dir: ''
    SETTLE="''${BEETS_SETTLE_SECONDS:-10}"
    find "${dir}" -type f -name '*.tmp' -print -quit | grep -q . && { echo ".tmp present — skip"; exit 0; }
    (( SETTLE )) && { sleep "$SETTLE"; find "${dir}" -type f -name '*.tmp' -print -quit | grep -q . && { echo ".tmp after settle — skip"; exit 0; }; }
  '';

  mkDemote = dir: ''
    count=0
    while IFS= read -r -d $'\0' f; do
      mv "$f" "${dir}/$(basename "$f")"
      count=$((count+1))
    done < <(find "${dir}" -type f \( -iname '*.mp3' -o -iname '*.flac' -o -iname '*.m4a' \
      -o -iname '*.aac' -o -iname '*.ogg' -o -iname '*.wav' -o -iname '*.aiff' \
    \) -print0)
    echo "demoted $count to ${dir}"
    find "${dir}" -mindepth 1 -type d -empty -delete 2>/dev/null || true
  '';

  sharedEnv = ''
    export BEETSDIR="${dataDir}"
    export HOME="$BEETSDIR"
    mkdir -p "$BEETSDIR/state" "$BEETSDIR/logs"
    CONFIG="''${BEETS_CONFIG_SOURCE:?BEETS_CONFIG_SOURCE must be set}"
    TIMESTAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
    exec > >(tee -a "$BEETSDIR/logs/$TIMESTAMP-runner.log") 2>&1
  '';

  mkImportRunner =
    targetPath:
    mkRunnerBin "beets-runner-import"
      (
        sharedEnv
        + ''
          TARGET="''${1:-${targetPath}}"
          ${mkMediaCheck targetPath}
          ${mkSettleCheck targetPath}
          beet -c "$CONFIG" import -q -C "$TARGET"
          ${mkDemote targetPath}
          find "$BEETSDIR/logs" -type f -name '*-runner.log' -mtime +30 -delete 2>/dev/null || true
        ''
      )
      [
        beets
        pkgs.coreutils
        pkgs.findutils
      ];

  mkSimpleRunner =
    name: cmd: runtimeInputs:
    mkRunnerBin name (sharedEnv + cmd) runtimeInputs;
in

{
  import = mkImportRunner mediaPaths.inboxDir;

  quarantine-interactive =
    mkRunnerBin "beets-runner-quarantine-interactive"
      (sharedEnv + ''exec beet -c "$CONFIG" import "''${1:-${mediaPaths.untaggedDir}}"'')
      [
        beets
        pkgs.coreutils
        pkgs.chromaprint
      ];

  reconcile =
    mkSimpleRunner "beets-runner-reconcile"
      ''beet -c "$CONFIG" update -a && beet -c "$CONFIG" convert --yes && beet -c "$CONFIG" duplicates -a && beet -c "$CONFIG" move''
      [
        beets
        pkgs.coreutils
        pkgs.ffmpeg
      ];

  duplicates =
    mkRunnerBin "beets-runner-duplicates"
      (
        sharedEnv
        + ''
          state_dir="$BEETSDIR/state"
          state_file="$state_dir/duplicates.sig"
          dup_output="$(beet -c "$CONFIG" duplicates -a "$@" 2>&1)"
          dup_exit=$?
          if [ -n "$dup_output" ]; then
            dup_sig=$(echo "$dup_output" | sha256sum | cut -d' ' -f1)
            prev_sig="$(cat "$state_file" 2>/dev/null || echo "")"
            if [ "$dup_sig" != "$prev_sig" ]; then
              echo "$dup_output" | notify info "Beets duplicates found - action required" "warning" "music"
              mkdir -p "$state_dir"
              echo "$dup_sig" > "$state_file"
            fi
          fi
          exit $dup_exit
        ''
      )
      [
        beets
        pkgs.coreutils
        notify
      ];

  "permission-reconcile" =
    mkRunnerBin "beets-runner-permission-reconcile"
      (''
        fixup() { local d="$1"; [ -d "$d" ] || return 0
          find "$d" -type d -exec chgrp music-ingest {} + -exec chmod 2775 {} +
          find "$d" -type f -exec chgrp music-ingest {} + -exec chmod 0664 {} +
          setfacl -R -m g:music-ingest:rwx "$d"
          find "$d" -type d -exec setfacl -m d:g:music-ingest:rwX {} +
          setfacl -R -m g:media:r-X "$d"
          find "$d" -type d -exec setfacl -m d:g:media:r-X {} +
        }
        fixup "${mediaPaths.libraryDir}"
        fixup "${mediaPaths.quarantineDir}"
        fixup "${mediaPaths.untaggedDir}"
        fixup "${mediaPaths.approvedDir}"
      '')
      [
        pkgs.coreutils
        pkgs.findutils
        pkgs.acl
      ];
}
