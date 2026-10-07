#!/bin/sh
# The smoke test on any repositories (only read): every tab and window, with
# each Tk in $WISH (default "wish8.6 wish9.0"), under Xvfb:
#
#   tests/smoke.sh ~/src/tcl.fossil ~/src/fossil.fossil ...
#
# Prints the timings, row counts and status lines; fails on an error.
set -u
cd "$(dirname "$0")"
if [ $# -eq 0 ]; then
    echo "usage: tests/smoke.sh REPOSITORY..." >&2
    exit 2
fi
TKTAALIK_TMP=${TKTAALIK_TMP:-${TMPDIR:-/tmp}/tktaalik-tests}
export TKTAALIK_TMP
mkdir -p "$TKTAALIK_TMP"
WISH=${WISH:-wish8.6 wish9.0}
dbus=""
command -v dbus-run-session >/dev/null 2>&1 && dbus="dbus-run-session --"
status=0
for w in $WISH; do
    for repo in "$@"; do
        if [ ! -f "$repo" ]; then
            echo "== $w $repo: no such repository"
            status=1
            continue
        fi
        repo=$(cd "$(dirname "$repo")" && pwd)/$(basename "$repo")
        home=$TKTAALIK_TMP/home-smoke
        rm -rf "$home"; mkdir -p "$home"
        echo "== $w $(basename "$repo")"
        out=$(TKTAALIK_REPO=$repo FOSSIL_HOME=$home timeout 600 $dbus xvfb-run -a "$w" smoke.tcl 2>&1)
        rc=$?
        echo "$out" | grep -v -e WARNING -e 'accessibility bus' -e 'SpiRegistry'
        [ $rc -eq 0 ] || status=1
    done
done
exit $status
