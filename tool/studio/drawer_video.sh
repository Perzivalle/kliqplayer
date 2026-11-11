#!/usr/bin/env bash
# Assemble les images de drawer_video_test.dart en une image animée (WebP) sur
# fond blanc, pour le site. Une image animée plutôt qu'une vidéo : les
# téléphones la jouent toujours, même là où la lecture automatique des vidéos
# est bloquée (économie d'énergie, économiseur de données). Fondu au blanc au
# début et à la fin : la boucle repart sans saut.
set -euo pipefail
cd "$(dirname "$0")/../.."
in=build/studio/drawer out=site/img/features/drawer-anim.webp
n=$(ls "$in"/f*.png | wc -l)
out_frames=$((n * 20 / 30)) # 30 images/s rendues, 20 gardées
ffmpeg -y -v error -framerate 30 -i "$in/f%04d.png" -filter_complex \
  "color=white:s=1240x1520:r=30[bg];[bg][0]overlay=shortest=1,fps=20,scale=460:-2:flags=lanczos,fade=in:s=0:n=6:color=white,fade=out:s=$((out_frames - 8)):n=8:color=white" \
  -c:v libwebp -lossless 0 -q:v 70 -compression_level 6 -loop 0 -an "$out"
ls -l "$out"
