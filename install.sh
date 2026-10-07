#!/bin/sh
# Installs Tktaalik: the application in PREFIX/share/tktaalik, the command
# PREFIX/bin/tktaalik, and its launcher and icon for the application menu.
#
#   ./install.sh [--prefix DIR] [--wish PROGRAM] [--destdir DIR]
#   ./install.sh [--prefix DIR] [--destdir DIR] --uninstall
#
#   --prefix DIR      where to install: ~/.local by default (/usr/local
#                     for root)
#   --wish PROGRAM    the Tk shell the command runs: "wish" on the PATH by
#                     default (wish9.0, /usr/bin/wish8.6, ...)
#   --destdir DIR     for packages: the files written under DIR, to work
#                     once moved to PREFIX
#   --uninstall       remove what an install put there
set -e
src=$(cd "$(dirname "$0")" && pwd)
prefix=""
wish=wish
destdir=""
uninstall=0
need() {
    [ $# -ge 2 ] || { echo "install.sh: $1 needs a value" >&2; exit 2; }
}
while [ $# -gt 0 ]; do
    case $1 in
        --prefix) need "$@"; prefix=$2; shift 2 ;;
        --prefix=*) prefix=${1#*=}; shift ;;
        --wish) need "$@"; wish=$2; shift 2 ;;
        --wish=*) wish=${1#*=}; shift ;;
        --destdir) need "$@"; destdir=$2; shift 2 ;;
        --destdir=*) destdir=${1#*=}; shift ;;
        --uninstall) uninstall=1; shift ;;
        -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "install.sh: unknown argument: $1 (see --help)" >&2; exit 2 ;;
    esac
done
if [ -z "$prefix" ]; then
    if [ "$(id -u)" = 0 ]; then prefix=/usr/local; else prefix=$HOME/.local; fi
fi
case $prefix in
    /*) prefix=${prefix%/} ;;
    *) echo "install.sh: --prefix must be an absolute path" >&2; exit 2 ;;
esac
app=$prefix/share/tktaalik      # where it runs from
root=$destdir$prefix            # where the files are written
sizes="16 24 32 48 64 128 256"

if [ $uninstall = 1 ]; then
    rm -rf "$root/share/tktaalik"
    rm -f "$root/bin/tktaalik" "$root/share/applications/tktaalik.desktop"
    for n in $sizes; do
        rm -f "$root/share/icons/hicolor/${n}x$n/apps/tktaalik.png"
    done
    echo "Tktaalik removed from $prefix."
else
    # The application: what it reads when it runs.  (A new install
    # replaces the old one whole: no files of an older version left.)
    rm -rf "$root/share/tktaalik"
    mkdir -p "$root/share/tktaalik/lib" "$root/share/tktaalik/icons" \
        "$root/share/tktaalik/docs" "$root/bin"
    cp "$src/tktaalik" "$src/LICENSE" "$src/README.md" "$root/share/tktaalik/"
    cp "$src"/lib/*.tcl "$root/share/tktaalik/lib/"
    cp "$src"/icons/*.png "$src"/icons/*.ico "$root/share/tktaalik/icons/"
    cp "$src"/docs/*.md "$root/share/tktaalik/docs/"
    chmod 755 "$root/share/tktaalik/tktaalik"
    # The command: a script, not a link (the application finds lib/ next to
    # itself).
    rm -f "$root/bin/tktaalik"
    printf '#!/bin/sh\nexec "%s" "%s" "$@"\n' "$wish" "$app/tktaalik" > "$root/bin/tktaalik"
    chmod 755 "$root/bin/tktaalik"
    # The application menu: the launcher and the icon.
    for n in $sizes; do
        mkdir -p "$root/share/icons/hicolor/${n}x$n/apps"
        cp "$src/icons/tktaalik-$n.png" "$root/share/icons/hicolor/${n}x$n/apps/tktaalik.png"
    done
    mkdir -p "$root/share/applications"
    sed "s|@TKTAALIK@|$prefix/bin/tktaalik|" "$src/tools/tktaalik.desktop" \
        > "$root/share/applications/tktaalik.desktop"
    echo "Tktaalik installed in $prefix: run $prefix/bin/tktaalik."
    if [ -z "$destdir" ]; then
        command -v "$wish" >/dev/null 2>&1 ||
            echo "Note: $wish is not found; give the Tk shell with --wish." >&2
        command -v fossil >/dev/null 2>&1 ||
            echo "Note: fossil is not on the PATH; Tktaalik needs it." >&2
        case :$PATH: in
            *:"$prefix/bin":*) ;;
            *) echo "Note: $prefix/bin is not on the PATH." >&2 ;;
        esac
    fi
fi

# Let the menus see the change now (not for a package: its own scripts do).
if [ -z "$destdir" ]; then
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database -q "$prefix/share/applications" 2>/dev/null || true
    fi
    if command -v gtk-update-icon-cache >/dev/null 2>&1 &&
            [ -f "$prefix/share/icons/hicolor/index.theme" ]; then
        gtk-update-icon-cache -q "$prefix/share/icons/hicolor" 2>/dev/null || true
    fi
fi
