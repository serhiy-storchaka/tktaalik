#!/bin/sh
# Runs the tests under Xvfb with each Tk in $WISH (default "wish8.6 wish9.0"),
# several at a time:
#
#   TKTAALIK_REPO=~/src/tk.fossil tests/run.sh [-j N] [NAME...]
#
# TKTAALIK_REPO is a copy of the Tk repository: the tests read it (and
# expect its tickets and branches), the ones that write use a scratch copy.
# See tests/common.tcl for the other settings.  Each test gets its own
# FOSSIL_HOME, so ~/.fossil is not touched.  FOSSIL, if set, is the Fossil
# to test with (a path, or a name on PATH): the application uses it, and
# it comes first on PATH for the tests and scratch.sh.
#
# At the end, the slowest tests and their times (seconds).
#
# -j N: N tests at a time (default: the processors, at most 8; each test
# that writes makes a scratch copy of the repository, kept only if the test
# fails).  The results are printed in order when all are done.
set -u
self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
cd "$(dirname "$0")"

# One test (run by the main part below, several at a time): run.sh --one
# WISH TEST DISPLAY.  Its output goes to $TKTAALIK_TMP/out/WISH-TEST.
if [ "${1:-}" = --one ]; then
    w=$2; t=$3; display=$4
    # (Each Tk its own directory: the tests of both run at the same time.)
    export TKTAALIK_TMP=$TKTAALIK_TMP/$w
    mkdir -p "$TKTAALIK_TMP"
    home=$TKTAALIK_TMP/home-$t
    rm -rf "$home"; mkdir -p "$home"
    unset TKTAALIK_SCRATCH
    scratch=""
    log=$TKTAALIK_TMP/../out/$w-$t
    # The tests that write ("need scratch") get a scratch copy.
    if grep -q '^need scratch' "$t.tcl"; then
        opt=""; [ "$t" = stash-search ] && opt=--stashes
        scratch=$TKTAALIK_TMP/scratch-$t
        if ! sh scratch.sh "$scratch" $opt >/dev/null 2>&1; then
            echo "$w $t: the scratch copy could not be made" > "$log.out"
            echo 1 > "$log.rc"
            exit 0
        fi
        export TKTAALIK_SCRATCH=$scratch
        home=$scratch/home
    fi
    start=$(date +%s)
    # (The tests are UTF-8: Tcl 8.6 on Windows would read them as cp1252.)
    out=$(FOSSIL_HOME=$home timeout 600 $dbus xvfb-run -a -n "$display" "$w" -encoding utf-8 "$t.tcl" 2>&1)
    rc=$?
    echo $(( $(date +%s) - start )) > "$log.time"
    {
        echo "$out" | grep -E '^(FAIL|==)' | awk -v p="$w" '{print p, $0}'
        if [ $rc -ne 0 ]; then
            echo "$out" | grep -q '^==' || echo "$out" | tail -5 | awk -v p="$w $t:" '{print p, $0}'
        fi
    } > "$log.out"
    echo $rc > "$log.rc"
    # (A scratch copy is big: kept only to look at a failure.)
    [ $rc -eq 0 ] && [ -n "$scratch" ] && rm -rf "$scratch"
    exit 0
fi

jobs=""
if [ "${1:-}" = -j ]; then jobs=$2; shift 2; fi
: "${TKTAALIK_REPO:?set TKTAALIK_REPO to a copy of the Tk repository}"
TKTAALIK_REPO=$(cd "$(dirname "$TKTAALIK_REPO")" && pwd)/$(basename "$TKTAALIK_REPO")
TKTAALIK_TMP=${TKTAALIK_TMP:-${TMPDIR:-/tmp}/tktaalik-tests}
export TKTAALIK_REPO TKTAALIK_TMP
mkdir -p "$TKTAALIK_TMP"
WISH=${WISH:-wish8.6 wish9.0}
# Another Fossil: first on PATH, as "fossil".
if [ -n "${FOSSIL:-}" ]; then
    exe=$(command -v "$FOSSIL") || { echo "FOSSIL: $FOSSIL not found"; exit 1; }
    case $exe in /*) ;; *) exe=$(pwd)/$exe ;; esac
    mkdir -p "$TKTAALIK_TMP/fossil-bin"
    ln -sf "$exe" "$TKTAALIK_TMP/fossil-bin/fossil"
    PATH=$TKTAALIK_TMP/fossil-bin:$PATH
    export FOSSIL PATH
    echo "With $(fossil version | head -1)"
fi
if [ -z "$jobs" ]; then
    jobs=$(nproc 2>/dev/null || echo 4)
    [ "$jobs" -gt 8 ] && jobs=8
fi
# The XTEST helper, for real mouse buttons (the tests that need it skip
# those checks without it).
if [ -z "${TKTAALIK_XBUTTON:-}" ] && command -v cc >/dev/null 2>&1 &&
        cc -o "$TKTAALIK_TMP/xbutton" xbutton.c -lX11 -lXtst 2>/dev/null; then
    TKTAALIK_XBUTTON=$TKTAALIK_TMP/xbutton
fi
export TKTAALIK_XBUTTON=${TKTAALIK_XBUTTON:-}
# Tk 9.1 with accessibility needs a D-Bus session; a private one.
dbus=""
command -v dbus-run-session >/dev/null 2>&1 && dbus="dbus-run-session --"
export dbus
tests=${*:-$(ls *.tcl | grep -v -x -e common.tcl -e smoke.tcl | sed "s/\.tcl$//")}
rm -rf "$TKTAALIK_TMP/out"; mkdir -p "$TKTAALIK_TMP/out"
# Each test its own X display number (xvfb-run -a starting from it): two
# started at once do not take the same one.
n=0
for w in $WISH; do
    for t in $tests; do
        n=$((n + 1))
        echo "$w $t $((200 + n * 3))"
    done
done | xargs -P "$jobs" -n 3 sh "$self" --one
# The results, in order.
status=0
for w in $WISH; do
    for t in $tests; do
        log=$TKTAALIK_TMP/out/$w-$t
        if [ ! -f "$log.rc" ]; then
            echo "$w $t: did not run"; status=1; continue
        fi
        cat "$log.out"
        [ "$(cat "$log.rc")" -eq 0 ] || status=1
    done
done
echo "Slowest:"
for f in "$TKTAALIK_TMP"/out/*.time; do
    [ -f "$f" ] && echo "$(cat "$f") $(basename "$f" .time)"
done | sort -rn | head -10 | awk '{printf "  %4d s  %s\n", $1, $2}'
exit $status
