#!/usr/bin/env bash
# Assemble les images de drawer_video_test.dart en une image animée (WebP) sur
# fond transparent, pour le site : elle prend la couleur de la page, claire ou
# assombrie par le navigateur. Une image animée plutôt qu'une vidéo : les
# téléphones la jouent toujours, même là où la lecture automatique des vidéos
# est bloquée (économie d'énergie, économiseur de données). Fondu au
# transparent au début et à la fin : la boucle repart sans saut.
# (Lent : une dizaine de minutes, à cause de la transparence.)
set -euo pipefail
cd "$(dirname "$0")/../.."
in=build/studio/drawer out=site/img/features/drawer-anim.webp
n=$(ls "$in"/f*.png | wc -l)
out_frames=$((n * 20 / 30)) # 30 images/s rendues, 20 gardées
ffmpeg -y -v error -framerate 30 -i "$in/f%04d.png" -vf \
  "fps=20,scale=460:-2:flags=lanczos,format=rgba,fade=in:s=0:n=6:alpha=1,fade=out:s=$((out_frames - 8)):n=8:alpha=1" \
  -c:v libwebp -lossless 0 -q:v 70 -compression_level 6 -loop 0 -an "$out"
# ffmpeg demande au navigateur de peindre chaque image par-dessus la
# précédente : à travers le fond transparent, on verrait les anciennes. Chaque
# image couvre tout : on lui dit de remplacer (drapeau « sans mélange »).
python3 - "$out" <<'PY'
import struct, sys
d = bytearray(open(sys.argv[1], 'rb').read())
i = 12
while i < len(d):
    n = struct.unpack('<I', d[i + 4:i + 8])[0]
    if d[i:i + 4] == b'ANMF': d[i + 8 + 15] |= 2
    i += 8 + n + (n & 1)
open(sys.argv[1], 'wb').write(d)
PY
ls -l "$out"
