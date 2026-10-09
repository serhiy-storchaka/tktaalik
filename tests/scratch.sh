#!/bin/sh
# scratch.sh DIR [--stashes]: a scratch copy of $TKTAALIK_REPO for the tests
# that write: DIR/tk.fossil (no remote, autosync off, a default user),
# DIR/co (a checkout of main) and DIR/home (its FOSSIL_HOME).  With
# --stashes, also four stashes for the Stash tests.
set -e
D=$1
: "${TKTAALIK_REPO:?}"
rm -rf "$D"
mkdir -p "$D/home" "$D/co"
export FOSSIL_HOME="$D/home"
cp "$TKTAALIK_REPO" "$D/tk.fossil"
fossil remote off -R "$D/tk.fossil" >/dev/null
fossil settings autosync off -R "$D/tk.fossil" >/dev/null
# (Without the checkouts of the original: the tests see only their own.)
fossil sql -R "$D/tk.fossil" "DELETE FROM config WHERE name GLOB 'ckout:*'" >/dev/null
user=$(fossil user list -R "$D/tk.fossil" | awk '{print $1}' |
    grep -v -x -e anonymous -e nobody -e developer -e reader | head -1)
fossil user default "$user" -R "$D/tk.fossil" >/dev/null
cd "$D/co"
fossil open ../tk.fossil main >/dev/null 2>&1
[ "$2" = --stashes ] || exit 0
echo "README line" >> README.md
echo "test" > tests/new.test
fossil add tests/new.test >/dev/null
fossil stash save -m "postponed: README and a new test" >/dev/null
fossil rm changes.md >/dev/null 2>&1
echo "/* QUUXMARKER */" >> generic/tkFont.c
fossil stash save -m "font fix" >/dev/null
fossil mv doc/wish.1 doc/wish2.1 >/dev/null
mv doc/wish.1 doc/wish2.1
fossil stash save -m "rename the wish manual" >/dev/null
fossil update --nosync core-8-6-branch >/dev/null 2>&1
echo "on 8.6" >> README.md
fossil stash save -m "postponed: on 8.6" >/dev/null
fossil update --nosync main >/dev/null 2>&1
