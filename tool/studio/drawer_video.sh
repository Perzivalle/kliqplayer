#!/usr/bin/env bash
# Assemble les images de drawer_video_test.dart en vidéos sur fond blanc,
# pour le site (MP4 lu partout, WebM plus léger). Fondu au blanc au début et à
# la fin : la boucle repart sans saut.
set -euo pipefail
cd "$(dirname "$0")/../.."
in=build/studio/drawer out=site/img/features
n=$(ls "$in"/f*.png | wc -l)
fade="fade=in:s=0:n=9:color=white,fade=out:s=$((n - 12)):n=12:color=white" # 0.3 s in, 0.4 s out, in frames
common=(-y -v error -framerate 30 -i "$in/f%04d.png" -filter_complex
  "color=white:s=1240x1520:r=30[bg];[bg][0]overlay=shortest=1,scale=620:-2,$fade" -an)
ffmpeg "${common[@]}" -c:v libx264 -pix_fmt yuv420p -crf 24 -preset slow -movflags +faststart "$out/drawer.mp4"
ffmpeg "${common[@]}" -c:v libvpx-vp9 -pix_fmt yuv420p -b:v 0 -crf 38 "$out/drawer.webm"
ls -l "$out"/drawer.mp4 "$out"/drawer.webm
