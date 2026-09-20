# beets-prune-empty: delete audio-free directories under the library root.
#
# Covers empty dirs and junk-only husks (cover-only, cue/log-only). Preview by
# default; --apply deletes. Skips .stfolder trees and never follows symlinks.
# Runs as the beets user with BEETSDIR/BEETS_PRUNE_ROOT set (see wrapper).

ROOT="${BEETS_PRUNE_ROOT:?BEETS_PRUNE_ROOT must be set}"
TIMESTAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
mkdir -p "$BEETSDIR/logs"
exec > >(tee -a "$BEETSDIR/logs/$TIMESTAMP-prune-empty.log") 2>&1

APPLY=0
if [ "${1:-}" = "--apply" ]; then APPLY=1; fi
removed=0
while IFS= read -r -d '' d; do
  if [ -e "$d/.stfolder" ]; then continue; fi
  if find "$d" -type f \( -iname '*.mp3' -o -iname '*.flac' -o -iname '*.m4a' -o -iname '*.aac' -o -iname '*.ogg' -o -iname '*.opus' -o -iname '*.wav' -o -iname '*.aiff' -o -iname '*.aif' \) -print -quit 2>/dev/null | grep -q .; then
    continue
  fi
  if [ "$APPLY" = 1 ]; then
    rm -rf "$d" && removed=$((removed + 1)) || echo "!! failed: $d"
  else
    echo "$d"
  fi
done < <(find "$ROOT" -mindepth 1 -depth -type d -print0)
if [ "$APPLY" = 1 ]; then echo "pruned $removed dirs under $ROOT"; else echo "(preview; rerun with --apply to delete)"; fi
