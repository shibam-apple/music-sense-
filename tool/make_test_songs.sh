#!/usr/bin/env bash
# Builds two tagged MP3 test songs (120 and 124 BPM) with embedded covers.
set -euo pipefail
out="${1:-build/test_songs}"
cd "$(dirname "$0")/.."
dart run tool/make_test_songs.dart "$out"
ffmpeg -loglevel error -y -f lavfi -i "gradients=s=600x600:c0=0x6f56f8:c1=0xff9a5c:duration=1" -frames:v 1 "$out/cover_a.png"
ffmpeg -loglevel error -y -f lavfi -i "gradients=s=600x600:c0=0x1b2440:c1=0xf2b27a:duration=1" -frames:v 1 "$out/cover_b.png"
for spec in "120:Beat Test 120:cover_a" "124:Beat Test 124:cover_b"; do
  IFS=: read -r bpm title cover <<< "$spec"
  ffmpeg -loglevel error -y -i "$out/beat_test_$bpm.wav" -i "$out/$cover.png" \
    -map 0:a -map 1:v -c:a libmp3lame -b:a 192k -c:v mjpeg -disposition:v attached_pic \
    -id3v2_version 3 -metadata title="$title" -metadata artist="Music Sense Lab" \
    -metadata album="Beat Tests" "$out/beat_test_$bpm.mp3"
done
ls -la "$out"/*.mp3
