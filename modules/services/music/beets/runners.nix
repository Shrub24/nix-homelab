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

  mkDemote = sourceDir: destDir: ''
    mkdir -p "${destDir}"
    count=0
    renamed=0
    while IFS= read -r -d $'\0' f; do
      base="$(basename "$f")"
      dest="${destDir}/$base"
      if [ -e "$dest" ]; then
        stem="''${base%.*}"
        ext=""
        if [ "$stem" != "$base" ]; then
          ext=".''${base##*.}"
        fi
        n=1
        while [ -e "${destDir}/''${stem}.demoted-''${n}''${ext}" ]; do
          n=$((n + 1))
        done
        dest="${destDir}/''${stem}.demoted-''${n}''${ext}"
        renamed=$((renamed + 1))
      fi
      mv "$f" "$dest"
      count=$((count+1))
    done < <(find "${sourceDir}" -type f \( -iname '*.mp3' -o -iname '*.flac' -o -iname '*.m4a' \
      -o -iname '*.aac' -o -iname '*.ogg' -o -iname '*.opus' -o -iname '*.wav' -o -iname '*.aiff' \
      -o -iname '*.aif' \
    \) -print0)
    echo "demoted $count from ${sourceDir} to ${destDir} (renamed=$renamed)"
    find "${sourceDir}" -mindepth 1 -type d -empty -delete 2>/dev/null || true
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
          ${mkDemote targetPath mediaPaths.untaggedDir}
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
      (
        ''
          export BEETSDIR="${dataDir}"
          export HOME="$BEETSDIR"
          mkdir -p "$BEETSDIR/state" "$BEETSDIR/logs"
          CONFIG="''${BEETS_CONFIG_SOURCE:?BEETS_CONFIG_SOURCE must be set}"
          TIMESTAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
          exec > >(tee -a "$BEETSDIR/logs/$TIMESTAMP-runner.log" >(systemd-cat --identifier="beets-interactive")) 2>&1
        ''
        + ''
          TARGET="''${1:-${mediaPaths.untaggedDir}}"
          ${mkMediaCheck "$TARGET"}
          ${mkSettleCheck "$TARGET"}
          beet -c "$CONFIG" import "$TARGET"
          if [ "$TARGET" != "${mediaPaths.untaggedDir}" ]; then
            ${mkDemote "$TARGET" mediaPaths.untaggedDir}
          fi
          find "$BEETSDIR/logs" -type f -name '*-runner.log' -mtime +30 -delete 2>/dev/null || true
        ''
      )
      [
        beets
        pkgs.coreutils
        pkgs.findutils
        pkgs.chromaprint
        pkgs.systemd
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

}
