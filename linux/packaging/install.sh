#!/bin/sh
# KliqPlayer for Linux: adds it to your applications menu (with its icon) and checks that
# libmpv, which plays the music, is installed. Nothing is copied: the app runs from this
# folder, so keep it where it is (or move it, then run this again).
#
#   ./install.sh              add to the menu
#   ./install.sh --uninstall  remove it from the menu (then delete this folder)
set -eu

dir=$(cd "$(dirname "$0")" && pwd)
apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
icons="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"
desktop="$apps/kliqplayer.desktop"

refresh() {
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$apps" 2>/dev/null || true
  command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q "${icons%/scalable/apps}" 2>/dev/null || true
}

if [ "${1:-}" = "--uninstall" ]; then
  rm -f "$desktop" "$icons/kliqplayer.svg"
  refresh
  echo "KliqPlayer removed from the menu. You can now delete $dir"
  exit 0
fi

[ -x "$dir/kliqplayer" ] || { echo "kliqplayer not found next to this script ($dir)." >&2; exit 1; }

mkdir -p "$apps" "$icons"
cp "$dir/kliqplayer.svg" "$icons/kliqplayer.svg"
cat >"$desktop" <<EOF
[Desktop Entry]
Type=Application
Name=KliqPlayer
GenericName=Music Player
Comment=A click-wheel music player that floats on your desktop
Exec="$dir/kliqplayer"
Path=$dir
Icon=kliqplayer
Terminal=false
Categories=AudioVideo;Audio;Player;
Keywords=ipod;music;player;spotify;
StartupWMClass=dev.paulux.lecteur
EOF
refresh
echo "KliqPlayer is in your applications menu."

# libmpv is loaded at start-up; without it there is no sound.
if ! { command -v ldconfig >/dev/null 2>&1 && ldconfig -p 2>/dev/null | grep -q 'libmpv\.so'; } \
   && ! ls /usr/lib*/libmpv.so* /usr/lib/*/libmpv.so* >/dev/null 2>&1; then
  id="" version=""
  [ -r /etc/os-release ] && . /etc/os-release && id="$ID ${ID_LIKE:-}" && version="${VERSION_ID:-}"
  case "$id" in
    *ubuntu*|*debian*) pkg=libmpv2; [ "$version" = "22.04" ] && pkg=libmpv1; cmd="sudo apt install $pkg" ;;
    *fedora*) cmd="sudo dnf install mpv-libs" ;;
    *suse*) cmd="sudo zypper install libmpv2" ;;
    *arch*) cmd="sudo pacman -S mpv" ;;
    *) cmd="install your distribution's libmpv package" ;;
  esac
  echo
  echo "One more step: KliqPlayer needs libmpv to play music, and it isn't installed."
  echo "  $cmd"
fi
