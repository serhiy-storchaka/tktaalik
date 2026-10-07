#!/bin/sh
# Installs Tktaalik in the desktop's application menu, for the current
# user: tktaalik.desktop (running this checkout's tktaalik) and the icon
# in the hicolor theme, under $XDG_DATA_HOME (~/.local/share).
#
#   tools/install-desktop.sh              install
#   tools/install-desktop.sh --uninstall  remove
set -e
top=$(cd "$(dirname "$0")/.." && pwd)
data=${XDG_DATA_HOME:-$HOME/.local/share}
sizes="16 24 32 48 64 128 256"
if [ "$1" = --uninstall ]; then
    for n in $sizes; do
        rm -f "$data/icons/hicolor/${n}x$n/apps/tktaalik.png"
    done
    rm -f "$data/applications/tktaalik.desktop"
else
    for n in $sizes; do
        mkdir -p "$data/icons/hicolor/${n}x$n/apps"
        cp "$top/icons/tktaalik-$n.png" "$data/icons/hicolor/${n}x$n/apps/tktaalik.png"
    done
    mkdir -p "$data/applications"
    sed "s|@TKTAALIK@|$top/tktaalik|" "$top/tools/tktaalik.desktop" \
        > "$data/applications/tktaalik.desktop"
fi
# Let the menus see the change now.
if command -v update-desktop-database >/dev/null; then
    update-desktop-database -q "$data/applications" || true
fi
if command -v gtk-update-icon-cache >/dev/null && [ -f "$data/icons/hicolor/index.theme" ]; then
    gtk-update-icon-cache -q "$data/icons/hicolor" || true
fi
