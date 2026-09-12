#!/usr/bin/env bash
set -euo pipefail

STAGING="${1:?usage: ffmpeg-preprocess <staging-dir>}"
echo "ffmpeg-preprocess: scanning $STAGING..."
count=0
fresh=0

  while IFS= read -r -d $'\0' src; do
    if [ "$(( $(date +%s) - $(stat -c %Y "$src") ))" -lt 45 ]; then
      # Younger than the 60s settle window: still being written, take it next pass.
      echo "SKIP (still settling): $src"
      (( ++fresh )) || true
      continue
    fi
    case "$src" in
      *.flac|*.FLAC|*.wav|*.WAV) dest="${src%.*}.aiff"; args=(-c:a pcm_s16be) ;;
      *) dest="${src%.*}.mp3"; args=(-c:a libmp3lame -b:a 320k) ;;
    esac
    if [[ -f "$dest" ]]; then
      continue
    fi
    if ffmpeg -nostdin -n -i "$src" "${args[@]}" "$dest" 2>/dev/null && [ -s "$dest" ]; then
      echo "ffmpeg-preprocess: $src -> $dest"
      # Source is redundant post-conversion; leaving it would import both copies as duplicates.
      rm -f "$src"
      (( ++count )) || true
    else
      echo "ffmpeg-preprocess: FAILED $src" >&2
    fi
  done < <(find "$STAGING" -type f \( -iname '*.flac' -o -iname '*.wav' -o -iname '*.opus' -o -iname '*.ogg' \) -print0)

echo "ffmpeg-preprocess: done ($count files processed)"
if (( fresh > 0 )); then
  # Guarantee that next pass: synthesize one dropbox event (self-cleaning kick).
  # Terminates: files age, so the next pass processes them and does not re-arm.
  touch "$STAGING/dropbox/.rearm" && rm -f "$STAGING/dropbox/.rearm"
fi
if [ -n "${STATE_DIRECTORY:-}" ]; then
  any_new=$(find "$STAGING" -type f \( -iname '*.mp3' -o -iname '*.aiff' -o -iname '*.aif' -o -iname '*.flac' -o -iname '*.wav' -o -iname '*.opus' -o -iname '*.ogg' -o -iname '*.m4a' \) -print -quit)
  if (( count > 0 )) || { (( fresh == 0 )) && [ -n "$any_new" ]; }; then
    # Signal beets-inbox to run; its ConditionPathExists skips empty passes before the scan chain.
    touch "$STATE_DIRECTORY/inbox-ready"
  fi
fi
