#!/bin/bash
# beets-merge-splits: fuse beets album entities that are pure import-session splits.
#
# A group is 2+ album rows sharing artist+album. AUTO-MERGE applies only when
# year+catalognum+label are identical across the group (beets then has no basis
# to treat them as different releases). Anything differing is listed REVIEW and
# never touched. Preview by default; --apply executes with an optional filter.
#
# Runs as the beets user with BEETSDIR/BEETS_CONFIG_SOURCE set (see the
# beets-merge-splits wrapper). Files are only relocated, never deleted.

shopt -s nocasematch
APPLY=0
if [ "${1:-}" = "--apply" ]; then
  APPLY=1
  shift
fi
FILT="${1:-}"
CONFIG="${BEETS_CONFIG_SOURCE:?BEETS_CONFIG_SOURCE must be set}"
TIMESTAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
mkdir -p "$BEETSDIR/logs" "$BEETSDIR/state"
exec > >(tee -a "$BEETSDIR/logs/$TIMESTAMP-merge-splits.log") 2>&1

AUDIO_RE='.*\.(mp3|flac|m4a|aac|ogg|opus|wav|aiff|aif)$'
ALBUMS="$BEETSDIR/state/merge-splits-albums.txt"
FAIL=0

beet -c "$CONFIG" ls -a -f "\$id|\$albumartist|\$album|\$year|\$catalognum|\$label|\$path" 2>/dev/null >"$ALBUMS"

declare -A G=()
while IFS='|' read -r id artist album year cat label path; do
  if [ -z "$id" ]; then continue; fi
  G["$artist|$album"]+="${id}|${year}|${cat}|${label}|${path}"$'\n'
done <"$ALBUMS"

for key in "${!G[@]}"; do
  if [[ "$key" != *"$FILT"* ]]; then continue; fi
  mapfile -t M < <(printf '%s' "${G[$key]}" | grep .)
  if [ "${#M[@]}" -le 1 ]; then continue; fi
  echo "== $key (${#M[@]} entities)"
  same=1
  ref=""
  for m in "${M[@]}"; do
    IFS='|' read -r id year cat label path <<<"$m"
    n=$(beet -c "$CONFIG" ls -f "\$path" "album_id:$id" 2>/dev/null | grep -c . || true)
    echo "   id=$id tracks=$n yr=$year cat=$cat label=$label :: $path"
    sig="$year|$cat|$label"
    if [ -z "$ref" ]; then ref="$sig"; fi
    if [ "$sig" != "$ref" ]; then same=0; fi
  done
  if [ "$same" = 0 ]; then
    echo "   -> REVIEW (metadata differs, not touching)"
    continue
  fi
  canon=""
  rest=()
  for m in "${M[@]}"; do
    IFS='|' read -r id year cat label path <<<"$m"
    if [ -z "$canon" ] && [[ "$(basename "$path")" != *" ["*"]" ]]; then
      canon="$m"
    else
      rest+=("$m")
    fi
  done
  if [ -z "$canon" ]; then
    canon="${M[0]}"
    rest=("${M[@]:1}")
  fi
  IFS='|' read -r cid _ _ _ cpath <<<"$canon"
  echo "   -> MERGE into: $cpath"
  if [ "$APPLY" = 0 ]; then continue; fi
  ids="$cid"
  ok=1
  for m in "${rest[@]}"; do
    IFS='|' read -r id year cat label path <<<"$m"
    ids="$ids,$id"
    if [ "$path" = "$cpath" ]; then continue; fi
    if [ ! -d "$path" ]; then continue; fi # consolidated by an earlier run
    if [ -n "$(find "$path" -mindepth 1 -type d -print -quit)" ]; then
      echo "   !! subdirs in $path, skipping group"
      ok=0
      break
    fi
    while IFS= read -r -d '' f; do
      bn="$(basename "$f")"
      if [ "$bn" = ".stfolder" ]; then continue; fi
      if [[ "$bn" =~ $AUDIO_RE ]]; then
        mv -n "$f" "$cpath"/ || ok=0
      elif [ -e "$cpath/$bn" ]; then
        if cmp -s "$f" "$cpath/$bn"; then
          rm "$f" || ok=0
        else
          mv -n "$f" "$cpath/${bn%.*}.${id}.${bn##*.}" || ok=0
        fi
      else
        mv "$f" "$cpath"/ || ok=0
      fi
    done < <(find "$path" -maxdepth 1 -type f -print0)
    if [ -n "$(ls -A "$path")" ]; then
      echo "   !! leftovers in $path (name collision?) - resolve manually, group aborted"
      ok=0
    fi
  done
  if [ "$ok" = 0 ]; then
    echo "   !! fix leftovers and rerun (already-moved files are safe to leave)"
    FAIL=1
    continue
  fi
  for rid in ${ids//,/ }; do
    beet -c "$CONFIG" remove "album_id:$rid" || {
      echo "   !! remove failed"
      FAIL=1
      continue 2
    }
  done
  if ! beet -c "$CONFIG" import -A -C -W -q "$cpath"; then
    echo "   !! import failed, rerun by hand: beet import -A -C -W '$cpath'"
    FAIL=1
    continue
  fi
  if [ "$(beet -c "$CONFIG" ls -a -f "\$id" "album:${cpath##*/}" 2>/dev/null | grep -c . || true)" = 1 ]; then
    echo "   merged OK"
  else
    echo "   !! expected 1 entity after import - inspect manually"
    FAIL=1
  fi
done
exit "$FAIL"
