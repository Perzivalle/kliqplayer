#!/usr/bin/env bash
# Lance l'appli (le paquet release) dans une autre distribution, avec
# distrobox + podman : vérifie qu'elle trouve ses bibliothèques (GTK,
# libmpv, son) ailleurs que sur Arch. Elle s'affiche sur le bureau actuel.
#
#   tool/envs/distro.sh ubuntu22          crée si besoin, vérifie, lance
#   tool/envs/distro.sh ubuntu22 --check  vérifie seulement (ldd)
#   tool/envs/distro.sh ubuntu22 --shell  ouvre un terminal dedans
#   tool/envs/distro.sh ubuntu22 --rm     supprime le conteneur et son dossier
#   tool/envs/distro.sh all --check       toutes les distributions
#
# Distributions : ubuntu22 ubuntu24 debian12 fedora opensuse arch
#
# Chaque conteneur a son propre dossier personnel (dans
# ~/.local/share/lecteur-envs/) : réglages et bibliothèque de l'appli
# restent à part. L'appli est montée en lecture seule dans /opt/tinypod, la
# musique dans /music. Construire d'abord : flutter build linux --release
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
bundle="$root/build/linux/x64/release/bundle"
music="${LECTEUR_MUSIC:-$HOME/Music/Musique Ipod}"
envs="$HOME/.local/share/lecteur-envs"
all=(ubuntu22 ubuntu24 debian12 fedora opensuse arch)

# Image, puis paquets d'exécution : ce qu'un bureau ordinaire a déjà (GTK)
# plus libmpv et le son. Pas d'outils de développement.
image() {
  case $1 in
    ubuntu22) echo docker.io/library/ubuntu:22.04 ;;
    ubuntu24) echo docker.io/library/ubuntu:24.04 ;;
    debian12) echo docker.io/library/debian:12 ;;
    fedora) echo registry.fedoraproject.org/fedora:41 ;;
    opensuse) echo registry.opensuse.org/opensuse/tumbleweed:latest ;;
    arch) echo docker.io/library/archlinux:latest ;;
    *) return 1 ;;
  esac
}
packages() {
  case $1 in
    ubuntu22) echo libgtk-3-0 libmpv1 libpulse0 libasound2 libgles2 libegl1 ;;
    ubuntu24) echo libgtk-3-0t64 libmpv2 libpulse0 libasound2t64 libgles2 libegl1 ;;
    debian12) echo libgtk-3-0 libmpv2 libpulse0 libasound2 libgles2 libegl1 ;;
    fedora) echo gtk3 mpv-libs pulseaudio-libs alsa-lib libglvnd-gles mesa-libEGL ;;
    opensuse) echo libgtk-3-0 libmpv2 libpulse0 libasound2 libglvnd Mesa-libEGL1 ;;
    arch) echo gtk3 mpv libpulse alsa-lib libglvnd mesa ;;
  esac
}

need() { command -v "$1" >/dev/null || { echo "Il manque $1 : sudo pacman -S --needed distrobox podman" >&2; exit 1; }; }

create() {
  local name=lecteur-$1
  if podman container exists "$name" 2>/dev/null; then return; fi
  [[ -d $bundle ]] || { echo "Pas de paquet : flutter build linux --release" >&2; exit 1; }
  mkdir -p "$envs/$1"
  local vols=(--volume "$bundle:/opt/tinypod:ro")
  [[ -d $music ]] && vols+=(--volume "$music:/music:ro")
  echo "== Création de $name ($(image "$1"))"
  distrobox create --yes --name "$name" --image "$(image "$1")" \
    --home "$envs/$1" "${vols[@]}" \
    --additional-packages "$(packages "$1")"
}

check() {
  echo "== $1 : bibliothèques"
  # Celles qui manquent, et libmpv (chargée au lancement, absente des NEEDED).
  distrobox enter "lecteur-$1" -- sh -c '
    missing=$(for f in /opt/tinypod/lecteur /opt/tinypod/lib/*.so*; do
      LD_LIBRARY_PATH=/opt/tinypod/lib ldd "$f" 2>/dev/null | grep "not found"
    done | sort -u | grep -v libjvm)
    if [ -n "$missing" ]; then echo "MANQUANT :"; echo "$missing"; else echo "ok, rien ne manque"; fi
    # Chargées au lancement (absentes des NEEDED).
    for l in libmpv:"pas de musique" libGLESv2:"plante au lancement" libEGL:"plante au lancement"; do
      ldconfig -p 2>/dev/null | grep -q "${l%%:*}\.so" && echo "${l%%:*} : ok" || echo "${l%%:*} : ABSENTE (${l#*:})"
    done
  '
}

run() {
  echo "== $1 : lancement (Ctrl+C pour quitter)"
  # Le conteneur partage les processus de la machine : l'appli survivrait
  # à ce script (on n'arrête que celle de test, pas celle installée).
  trap "pkill -f '^/opt/tinypod/lecteur' 2>/dev/null; true" EXIT INT TERM
  distrobox enter "lecteur-$1" -- env LECTEUR_MUSIC=/music /opt/tinypod/lecteur
}

main() {
  need distrobox
  need podman
  local which=${1:-} action=${2:-run}
  [[ -n $which ]] || { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
  local list=("$which")
  [[ $which == all ]] && list=("${all[@]}")
  for d in "${list[@]}"; do
    image "$d" >/dev/null || { echo "Inconnue : $d (${all[*]})" >&2; exit 1; }
    case $action in
      --rm)
        distrobox rm --force "lecteur-$d" || true
        rm -rf "${envs:?}/$d"
        ;;
      --shell) create "$d"; distrobox enter "lecteur-$d" ;;
      --check) create "$d"; check "$d" ;;
      run | --run) create "$d"; check "$d"; run "$d" ;;
      *) echo "Action inconnue : $action" >&2; exit 1 ;;
    esac
  done
}

main "$@"
