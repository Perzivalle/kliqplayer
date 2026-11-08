#!/usr/bin/env bash
# Lance l'appli sous un autre gestionnaire de fenêtres, ouvert dans une
# fenêtre du bureau actuel (compositeur imbriqué). Les compositeurs sont
# installés dans un conteneur Arch (distrobox + podman), pas sur la machine.
#
#   tool/envs/wm.sh sway          Wayland, en tuiles (l'appli est pavée)
#   tool/envs/wm.sh sway-float    Wayland, sway avec l'appli flottante
#   tool/envs/wm.sh labwc         Wayland, flottant (genre Openbox)
#   tool/envs/wm.sh weston        Wayland, le compositeur de référence
#   tool/envs/wm.sh kde           Wayland, KWin (après --with-kde)
#   tool/envs/wm.sh openbox       X11 sans compositeur (pas de transparence)
#   tool/envs/wm.sh openbox-picom X11 avec compositeur (picom)
#   tool/envs/wm.sh i3            X11, en tuiles
#   tool/envs/wm.sh --with-kde    ajoute KWin au conteneur (lourd, ~1 Go)
#   tool/envs/wm.sh --create      prépare seulement le conteneur
#   tool/envs/wm.sh --shell       terminal dans le conteneur
#   tool/envs/wm.sh --rm          supprime le conteneur et son dossier
#
# Fermer la fenêtre du compositeur (ou Ctrl+C ici) pour arrêter.
# Taille de l'écran imbriqué : WM_SIZE=1280x800 (défaut).
#
# Capture sans rien afficher : WM_SHOT=capture.png tool/envs/wm.sh sway
# (compositeur sans fenêtre, capture après WM_WAIT=12 s, puis arrêt ;
# sway, sway-float, labwc, openbox, openbox-picom, i3).
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
bundle="$root/build/linux/x64/release/bundle"
music="${LECTEUR_MUSIC:-$HOME/Music/Musique Ipod}"
home="$HOME/.local/share/lecteur-envs/wm"
box=lecteur-wm
size=${WM_SIZE:-1280x800}
w=${size%x*} h=${size#*x}
app="env LECTEUR_MUSIC=/music /opt/tinypod/lecteur"

pkgs="sway swaybg labwc weston xorg-server-xephyr xorg-server-xvfb xorg-xwayland openbox i3-wm picom
      foot xorg-xauth xorg-xsetroot grim xorg-xwd imagemagick gtk3 mpv libpulse alsa-lib mesa noto-fonts"

need() { command -v "$1" >/dev/null || { echo "Il manque $1 : sudo pacman -S --needed distrobox podman" >&2; exit 1; }; }

create() {
  podman container exists $box 2>/dev/null && return
  [[ -d $bundle ]] || { echo "Pas de paquet : flutter build linux --release" >&2; exit 1; }
  mkdir -p "$home"
  local vols=(--volume "$bundle:/opt/tinypod:ro")
  [[ -d $music ]] && vols+=(--volume "$music:/music:ro")
  distrobox create --yes --name $box --image docker.io/library/archlinux:latest \
    --home "$home" "${vols[@]}" --additional-packages "$(echo $pkgs)"
}

# Exécute un script dans le conteneur.
inside() { distrobox enter $box -- bash -c "$1"; }

case ${1:-} in
  --rm) distrobox rm --force $box || true; rm -rf "${home:?}"; exit ;;
  --create) need distrobox; need podman; create; exit ;;
  --shell) need distrobox; need podman; create; distrobox enter $box; exit ;;
  --with-kde) need distrobox; need podman; create; inside "sudo pacman -S --needed --noconfirm kwin"; exit ;;
  "" | -h | --help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit ;;
esac
need distrobox
need podman
create

# Le conteneur partage les processus de la machine : quitter ce script ne
# les arrête pas. On arrête nous-mêmes ce qu'on a lancé (l'appli de test,
# jamais celle installée) ; le gestionnaire de fenêtres X11 suit son serveur.
cleanup() {
  pkill -f '^/opt/tinypod/lecteur' 2>/dev/null || true
  pkill -f '^(Xephyr|Xvfb) :7 ' 2>/dev/null || true
  pkill -f '^sway -c /tmp/' 2>/dev/null || true
  pkill -f '^labwc -s ' 2>/dev/null || true
  pkill -f -- '--socket=lecteur-weston' 2>/dev/null || true
  pkill -f -- '--socket lecteur-kwin' 2>/dev/null || true
  true
}
trap cleanup EXIT INT TERM

shot=${WM_SHOT:-}
[[ -n $shot ]] && shot=$(realpath -m "$shot")
# Sans fenêtre pour une capture.
headless=""
[[ -n $shot ]] && headless="WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman"
# Où le compositeur Wayland note son socket (dossier personnel du conteneur).
# (Un petit script, lancé par le compositeur : il voit son socket à lui.)
sockfile="$home/.wm-socket"
rm -f "$sockfile"
note="$home/.wm-note.sh"
cat >"$note" <<'NOTE'
#!/bin/sh
echo "$WAYLAND_DISPLAY" > "$HOME/.wm-socket"
exec "$@"
NOTE
chmod +x "$note"

case $1 in
  sway | sway-float)
    float=""
    [[ $1 == sway-float ]] && float='for_window [app_id="dev.paulux.lecteur"] floating enable'
    kind=wayland
    script="
      cfg=\$(mktemp)
      printf '%s\n' 'output * bg #2b3a4a solid_color' 'output * mode ${w}x${h}' \
        'bindsym Mod1+Shift+e exit' '$float' 'exec $note $app' > \$cfg
      env $headless sway -c \$cfg"
    ;;
  labwc)
    kind=wayland
    script="env $headless labwc -s '$note $app'"
    ;;
  weston)
    [[ -n $shot ]] && { echo "Pas de capture sous weston" >&2; exit 1; }
    kind=none
    script="
      weston --width $w --height $h --socket=lecteur-weston & pid=\$!
      sleep 1.5
      WAYLAND_DISPLAY=lecteur-weston $app &
      wait \$pid"
    ;;
  kde)
    [[ -n $shot ]] && { echo "Pas de capture sous KDE" >&2; exit 1; }
    kind=none
    script="
      command -v kwin_wayland >/dev/null || { echo 'KWin absent : tool/envs/wm.sh --with-kde'; exit 1; }
      kwin_wayland --width $w --height $h --socket lecteur-kwin --xwayland & pid=\$!
      sleep 3
      WAYLAND_DISPLAY=lecteur-kwin $app &
      wait \$pid"
    ;;
  openbox | openbox-picom | i3)
    wm=openbox
    if [[ $1 == i3 ]]; then
      # Configuration minimale (sinon l'assistant de premier lancement
      # s'ouvre par-dessus).
      mkdir -p "$home/.config/i3"
      printf '%s\n' 'font pango:monospace 9' 'bindsym Mod1+Shift+e exit' >"$home/.config/i3/config"
      wm="i3 -c $home/.config/i3/config"
    fi
    comp=""
    [[ $1 == openbox-picom ]] && comp="picom --backend xrender &"
    server="Xephyr :7 -screen $size -resizeable -no-host-grab"
    [[ -n $shot ]] && server="Xvfb :7 -screen 0 ${size}x24"
    kind=x11
    # L'appli forcée en X11, sur un fond coloré : sans compositeur, sa
    # fenêtre transparente devient noire, c'est ce qu'on veut voir.
    script="
      $server & x=\$!
      sleep 1
      export DISPLAY=:7
      unset WAYLAND_DISPLAY
      xsetroot -solid '#2b3a4a'
      $wm & wmpid=\$!
      $comp
      sleep 0.5
      GDK_BACKEND=x11 $app &
      wait \$x; kill \$wmpid 2>/dev/null"
    ;;
  *) echo "Inconnu : $1 (tool/envs/wm.sh --help)" >&2; exit 1 ;;
esac

if [[ -z $shot ]]; then
  inside "$script"
  exit
fi

# Capture : le compositeur tourne sans fenêtre, on photographie son écran.
inside "$script" >/dev/null 2>&1 &
sleep "${WM_WAIT:-12}"
if [[ $kind == x11 ]]; then
  inside "xwd -root -display :7 | magick xwd:- png:-" >"$shot"
else
  sock=$(cat "$sockfile" 2>/dev/null || true)
  # Jamais le bureau de la machine : ce serait une capture de l'écran réel.
  if [[ -z $sock || $sock == "${WAYLAND_DISPLAY:-}" ]]; then
    echo "Le compositeur n'a pas démarré (socket : '${sock}')" >&2
    exit 1
  fi
  inside "WAYLAND_DISPLAY=$sock grim -" >"$shot"
fi
echo "Capture : $shot"
