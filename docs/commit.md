# Commit

The Commit tab shows what changed in the checkout, the diff of each
changed file, and commits the files you choose.  It also does the other
things one does to a checkout before committing: adding, renaming and
removing files, deleting unmanaged ones, reverting, undoing, looking at a
merge in progress, and saving or applying patches.

The tab needs a checkout.  When only a repository file is open, the tab
is disabled; open a checkout with **File ▸ Open checkout…**.

**Nothing is ever pushed.**  Commits are made with `--nosync`, whatever
the `autosync` setting says: the new check-in stays in the local
repository until you push it yourself.  The line at the top of the tab
shows the checkout's directory, its branch, the check-in it is on and the
autosync setting (as written, for example `on,commit=off`), with the
reminder that it is never used here; and, with ⚠, if the check-in was
moved to its branch later (see [Committing](#committing)).

Every operation that changes the checkout asks first.  Where Fossil has a
dry run for it, the dialog shows that dry run ("What it does (dry run):")
and runs it again as you change the options, so you see exactly what will
happen before you press the button.

## Changed files

The list on the left shows the changed files of the checkout, as `fossil
changes` classifies them:

| Status | Meaning |
|---|---|
| EDITED | the file's content changed |
| ADDED | added, committed with the next commit |
| DELETED | removed, gone from the next commit on |
| RENAMED | renamed (the list shows the new name) |
| MISSING | managed, but not on disk (in red) |
| CONFLICT | a merge left conflict marks in it (in red) |
| UPDATED_BY_MERGE, ADDED_BY_MERGE, … | changed by a merge in progress |
| EXTRA | not managed by Fossil (only with "Show unmanaged files", in grey) |
| UNCHANGED | not changed (only with "Show unchanged files") |

The first column is a check box: the checked files are committed.  Click
it, or select files and press Space, to check or uncheck them.  Several
files can be selected (Shift-click, Control-click): Remove, Revert, Undo
and Redo for files, Add, Rename (moving them into a directory) and Update
files to a version then act on all of them.  Files that
can be committed start checked; EXTRA, MISSING and UNCHANGED files start
unchecked and are never committed (EXTRA ones can be added first; see
[File operations](#file-operations)).  Your choices are kept when the
list is read again, as long as a file's status stays the same.  The
status line counts the checked files.

Two check boxes under the comment change what is listed:

- **Show unmanaged files**: also the files Fossil does not manage, as
  `fossil extras` lists them: not those of the ignore-glob setting, nor
  dot files unless the dotfiles setting is on, or **with dot files** is
  checked beside it (`--dotfiles`).  (The fields of the Add new and Delete
  unmanaged files dialogs do not change this list.)  Selecting one shows
  the start of its text instead of a diff.
- **Show unchanged files**: also the managed files that did not change,
  so that you can rename or remove them here too.

Select a file to see its diff on the right.  Double-click it for a
side-by-side diff in a window of its own.  Right-click it for:

| Entry | What it does |
|---|---|
| Side-by-side diff | the diff of the file in the diff window |
| Add | adds the checked unmanaged files, or this one |
| Rename or move… | see [File operations](#file-operations) |
| Remove… | see [File operations](#file-operations) |
| Revert… | see [File operations](#file-operations) |
| Update to a version… | see [Updating](#updating) |
| Undo for these files…, Redo for these files… | see [Undo and redo](#undo-and-redo) |
| Copy names | the selected files' paths, to the clipboard |

The list is read again when you come back to the tab, after every
operation, and with **Refresh** (F5).

## Committing

Type the check-in comment in the box at the bottom, check the files, and
press **Commit** (or Ctrl+Return).  The comment is required.

- **New branch**: a branch name to commit to a new branch, starting with
  this check-in (`--branch`).  Leave it empty to commit to the branch the
  checkout is on.  The name cannot contain spaces or start with `-`, `<`,
  `>` or `|`.
- **Ignore warnings**: no warnings about the files' contents (CR/LF line
  endings, binary data, …) and no check of the comment (`--no-warnings
  --no-verify-comment`).
- **More options**: the rest of Fossil's commit options; see
  [Commit options](#commit-options).

**Dry run** shows what the commit would do (`fossil commit --dry-run`)
without committing: the output appears in a window.

A commit goes to the branch of the check-in the checkout is on.  If that
check-in was moved to its branch by a later tag change — someone ran
`fossil amend --branch` on it, as reverting a merge may do — the checkout
follows it there, and a commit would land on a branch you did not expect.
The line at the top of the tab then says where it was moved from, by whom
and when, and **Commit** asks first ("This commit goes to the branch …",
No by default).  To commit to the old branch instead, update to it first
([Branches](branches.md)), or give a new branch.  **Update…** asks too,
since it would follow the check-in's new branch: Yes updates to the
newest check-in of the old branch instead, No along the new one.

Tktaalik also remembers the branch each checkout was on when you last
updated or committed in it here.  If the checkout went on to another
branch since by plain updates (`fossil update` follows a branch along
its history, also across a check-in moved to another branch further
back), the line at the top says "on … since an update: it was on …"
and **Commit** asks the same way.  Switching to another branch, and
starting a new one, are not taken for such a change.

Fossil sometimes asks a question during a commit (about line endings,
binary files, a fork, a comment that looks wrong).  Here such a question
cancels the commit (`--no-prompt`), and Fossil's message is shown in a
window, so that you can decide: fix the cause, or check **Ignore
warnings** or the matching option under **More options** and commit
again.

After a successful commit the window shows Fossil's output, the status
line says `Committed` and the new check-in's hash, the comment box, the
New branch box and the one-shot options are cleared, and the list is read
again.

While a merge is in progress (see [Merges](#merges)), Fossil commits all
changed files: the check boxes cannot be changed, and a note in red says
what is being merged.

## Commit options

**More options** opens a panel with the rest of Fossil's commit options
(the button then reads **Fewer options**).  Hover over a field for a
short explanation.

| Field | Fossil option | Meaning |
|---|---|---|
| Tags | `--tag` | tags of the new check-in, separated by spaces or commas |
| Branch colour | `--branchcolor` | the colour of the new branch (with the **…** button: a colour chooser) |
| Check-in colour | `--bgcolor` | the colour of this check-in only in the timeline |
| Date | `--date-override` | the time of the check-in instead of now (`YYYY-MM-DD HH:MM:SS`, UTC) |
| As user | `--user-override` | record this user as the one who made the check-in |
| Close the branch | `--close` | close the branch committed to: no more check-ins on it |
| Close merged branches | `--integrate` | close the branches merged in |
| Private | `--private` | never sync the check-in, and make its descendants private |
| Don't sign | `--nosign` | do not sign the check-in with gpg |
| Allow a fork | `--allow-fork` | commit although it forks the branch |
| Allow no changes | `--allow-empty` | commit although no file changed (with Close the branch, to close a branch) |
| Allow conflicts | `--allow-conflict` | commit although files have unresolved merge conflicts |
| Allow older | `--allow-older` | commit although it is older than its parent |
| Allow big files | `--ignore-oversize` | no warning about oversized files |
| Ignore clock skew | `--ignore-clock-skew` | commit although the clock differs from the server's |
| Override a lock | `--override-lock` | commit although the parent is locked by another checkout |
| Check by hashing | `--hash` | find changed files by their hashes, not their times (the list of changed files too: a file edited without changing its size within the same second shows up) |
| Skip hooks | `--no-verify` | do not run the before-commit hooks |

The values typed are checked first: a tag cannot have spaces or
`<>|"'&`, a colour is `#RRGGBB` (or a colour name), a date is `YYYY-MM-DD
HH:MM:SS`, and nothing starts with `-`; a value that cannot be passed is
named, and nothing is committed.

Most of these are **one-shot**: they are cleared after a successful
commit, so that a tag, a colour, a date or an "allow" does not end up on
the next check-in by accident.  The ones that are preferences rather than
choices for one check-in stay set: **Allow big files**, **Ignore clock
skew**, **Check by hashing**, **Don't sign** and **Skip hooks**.

## Diffs

The right side of the tab shows the diff of the selected file: added
lines in green, removed ones in red, the hunk headers in blue.  An
unmanaged file shows the start of its text, a missing one a note.

The **Commit** menu has more diffs, each in the diff window (see
[Diffs](diffs.md)):

| Entry | What it shows |
|---|---|
| Side-by-side diff | the selected file, side by side (also a double-click, or the button) |
| Diff of all changes | every change of the checkout |
| Compare with version… | sets the version the diffs compare against |
| Compare two versions… | the diff between any two versions, or a directory and a version |
| Diff since before the last undoable command | the changes since the state before the last update, merge, revert, stash or clean (`fossil diff --undo`) |
| Diff options | the submenu below |

**Compare with version…** asks for a check-in, branch or tag: from then
on all the diffs of the tab (the pane, Side-by-side, Diff of all changes)
show the files against that version instead of the check-in the checkout
is on (`fossil diff --from`).  The line at the top says `diffs against
…` while it is set.  Leave the field empty to compare with the checkout's
check-in again.

**Compare two versions…** asks for **From** and **To**: check-ins,
branches or tags (`fossil diff --from --to`).  **To** left empty compares
with the files of the checkout as they are now.  **From** can also be a
directory (**Directory…** chooses one): a tree of files elsewhere, for
example an unpacked release, compared with the checkout or the version
To.

**Commit ▸ Diff options** changes how all diffs of the Commit and Stash
tabs compare; the diff pane is shown again at once:

| Entry | Fossil option | Meaning |
|---|---|---|
| Ignore white space | `-w` | lines that differ only in white space are the same |
| Ignore white space at line ends | `-Z` | trailing white space does not count |
| Ignore CR at line ends | `--strip-trailing-cr` | CR/LF and LF line endings are the same |
| Inverted (new to old) | `--invert` | the diff the other way round |
| Default context, No context, 3 lines of context, 10 lines of context, Whole files | `-c N` | how many unchanged lines around each change |

## File operations

All of these are in the **Commit** menu; the ones for a single file also
in the file's context menu.  They change the checkout only; nothing is
committed until you commit.

**Add** adds the checked unmanaged files to Fossil, or if none are
checked, the selected unmanaged file.  (Check **Show unmanaged files**
to see them.)  If some of them match the ignore-glob setting, Tktaalik
asks whether to add them anyway (`fossil add -f`).  If some names are
reserved on Windows (`aux`, `con`, `nul`, …), it warns that such files
cannot be checked out on Windows and asks whether to add them anyway
(`--allow-reserved`).

**Rename or move…** asks for the new name of the selected file, or a
directory to move it into.  With several files selected it asks for the
directory to move them all into (made if needed).  **Also rename the file on disk** (on by
default) renames the file itself too (`fossil mv --hard`); unchecked,
Fossil only records the new name and the file on disk stays as it is
(`--soft`).  The dry run shows what will happen as you type.

**Rename or move a directory…** and **Remove a directory…** do the same
for a whole directory of the checkout and all the files in it (the
directory of the selected file to start with).

**Remove…** removes the selected files from the repository: from the next
commit on, Fossil no longer has it.  An added file is only no longer
added.  **Also delete the file on disk** (off by default) deletes the
file too (`fossil rm --hard`); otherwise the file stays on disk and is
only forgotten (`--soft`, the same as `fossil forget`).

**Add new and remove missing…** adds all unmanaged files (except those of
the ignore-glob setting) and removes all missing ones
(`fossil addremove`).  Its options:

- **Include files whose names begin with a dot** (`--dotfiles`);
- **Also ignore**: more glob patterns of files not to add (`--ignore`);
- **And these**: more glob patterns of the clean-glob kind (`--clean`).

The patterns are comma-separated, and are added to those of the settings
(the versioned `.fossil-settings` file, or the setting): Fossil's
`--ignore` and `--clean` replace the settings, so the app passes both.

**Reset adds and removes…** undoes the adds and removes not committed
yet: files added are no longer added, files removed no longer removed.
The files on disk stay as they are (`fossil addremove --reset`).
**Reset adds…** undoes only the adds (`fossil add --reset`), **Reset
removes…** only the removes (`fossil rm --reset`); each shows its dry run.

**Set the times of files…** sets the modification times of the selected
files, or of all managed files when none is selected, to now, to the time
of the check-in that last changed each, or to the time of the checked-out
version (`fossil touch`, after its dry run).  The files are not changed;
build tools may then see them as new or old.

**Switch the version, keep the files…** makes the checkout a checkout of
another version without changing any file on disk (`fossil checkout
--keep`): what differs from that version then shows as changes, for
example to commit a tree made elsewhere onto it.  Fossil has no dry run
for this, and refuses when files are edited; Undo cannot take it back
(switch again to the version shown in the dialog).

**Revert…** throws away the changes of the selected files.  **To the
version** reverts it to another check-in, branch or tag instead of the
check-in the checkout is on (`fossil revert -r`).  **Revert all…** throws
away all changes of the checkout; the dialog lists the files it reverts.
A revert can be undone (see [Undo and redo](#undo-and-redo)) until the
next update or commit.

## Delete unmanaged files

**Commit ▸ Delete unmanaged files…** deletes files that Fossil does not
manage: build products, editor backups, leftovers of merges.  It is the
most destructive operation of the tab, so it goes in two steps.

The first dialog lists what would be deleted (Fossil's dry run, `fossil
clean -n`), each file or directory with a check box: uncheck the ones to
keep (click the box, or select and press Space).  The options change
which files are listed, and the list is made again as you change them:

| Option | Fossil option | Meaning |
|---|---|---|
| Include files whose names begin with a dot | `--dotfiles` | also dot files |
| Also delete empty directories | `--emptydirs` | also the directories left empty |
| Only empty directories | `--dirsonly` | only the empty directories, no files |
| Only Fossil's temporary files | `--temp` | only the leftovers of merges and conflicts |
| Everything not managed | `-x` | ignore the ignore-glob and keep-glob settings too; nothing can be undone |
| Also in nested checkouts | `--allckouts` | also inside checkouts nested in this one, whose own settings are not taken into account |
| Also ignore | `--ignore` | glob patterns of files not to delete, added to the ignore-glob setting's |
| Also keep | `--keep` | glob patterns of files to keep, added to the keep-glob setting's |

Files of the ignore-glob and keep-glob settings are never listed (except
with **Everything not managed**), also with patterns typed in **Also
ignore** and **Also keep**.

**Delete…** then shows a second confirmation that names every file and
directory to be deleted, with Cancel as the default button; with **Also
delete empty directories**, also the directories that become empty when
those files go.  The files are deleted by `fossil clean`; the empty
directories by Tktaalik, each only if it is empty: an unchecked directory
stays.  It also says what can be
brought back: Fossil's undo restores deleted files smaller than 10 MiB,
except the ones of the clean-glob setting, which Fossil deletes without
undo; the confirmation names the files that cannot be restored and
why.  With **Everything not managed** nothing can be brought back,
and the confirmation says so.  Only the files still checked are deleted.

## Undo and redo

Fossil remembers the state of the checkout before the last **update,
merge, revert, stash apply, stash drop, stash goto or clean**, and can go
back to it.

- **Commit ▸ Undo…** undoes the last such command.
- **Commit ▸ Redo…** undoes the undo.
- **Undo for these files…** (in a file's context menu) restores only the
  selected files to their state before the last undoable command, and
  leaves the rest of the update or merge in effect.  **Redo for these
  files…** redoes it for them only.  (Fossil's dry run lists the whole
  undo even then: the confirmation names the files that are undone.)

Each first runs Fossil's dry run (`fossil undo -n`) and shows what it
would do in the confirmation.  If there is nothing to undo (or redo), it
says so and does nothing.

Commits cannot be undone this way, and the undo state is lost after a
commit or another undoable command.  **Commit ▸ Diff since before the
last undoable command** shows what the last undoable command (and
anything since) changed; see [Diffs](#diffs).

## Updating

**Commit ▸ Update…** updates the checkout to the newest check-in of its
branch (`fossil update --nosync`: nothing is pulled first).  Uncommitted
changes are merged into the new version.  The dialog shows the dry run,
with three options:

| Option | Fossil option | Meaning |
|---|---|---|
| To the newest check-in of any branch | `--latest` | not only of the checkout's branch |
| Set the times of the files to their check-ins' | `--setmtime` | for build systems that go by file times |
| On a merge conflict, keep the files of the three versions | `-K` | the baseline, local and merged-in versions stay beside the file |

**Update files to a version…** (also **Update to a version…** in the
file's context menu) updates only the selected files to another
check-in, branch or tag; their changes are merged into it, and the rest
of the checkout stays (`fossil update VERSION FILE…`; only **-K** of the
options above applies).  Unlike **Revert** with a version, local changes
are kept.

To update to another branch or check-in, see
[Update and merge](branches.md#update-and-merge).

## Merges

Merges are made in the [Branches](branches.md) tab.  While a merge (or a
cherry-pick, a back-out or an integrating merge) is in progress in the
checkout, the Commit tab:

- says so in red under the comment, naming what is merged, for example
  `A merge is in progress (merge of 3b1e0d5a2c): Fossil commits all
  changed files.`;
- checks all files that can be committed, and does not let you uncheck
  them: a merge is committed whole;
- shows the **Merge details** button (also in the Commit menu).

**Merge details** opens a window with what the merge did to each file
(`fossil merge-info`, in Fossil 2.26 or newer), conflicts in red.  **All files the merge changed**
(`-a`) also lists the files the merge changed without conflicts.  Click a
file's line and **Three-way view** (or double-click it): four columns of
the file, the baseline (the common ancestor), the checkout's version
(local), the version merged in, and the result (`fossil merge-info
--tcl`, shown as Fossil's own `--tk` view shows it): lines changed
locally in yellow, lines from the merged-in version in green, lines
removed in red, an empty grey line where a version has no line, and
"… N lines …" for unchanged lines left out.  Its buttons compare two of
the versions whole in the diff window: **Baseline → local**, **Baseline →
merged in**, **Local → merged in**.

**Commit ▸ Merge fork…** is enabled when the checkout's branch has more
than one leaf (the line at the top says how many): it merges the other
leaf into the checkout (`fossil merge` without a version, after its dry
run, with `-K` as an option), and committing then joins the branch
again.

Files with conflicts have the status CONFLICT.  Resolve the conflict
marks in them, then commit; **Allow conflicts** under **More options**
commits although some remain.  To abandon the merge, use **Undo…** or
**Revert all…**.

## Patches

A Fossil patch file holds the uncommitted changes of a checkout, with the
check-in they were made on, so that they can be applied to another
checkout (`fossil patch`).

- **Commit ▸ Save changes as a patch…** saves all changes of the
  checkout to a file you choose (`fossil patch create`).  The checkout
  keeps its changes.
- **Commit ▸ Apply a patch…** applies a patch file to the checkout:
  Fossil updates the checkout to the check-in the patch was made on, then
  makes its changes.  Fossil's update there syncs when autosync is on for
  updates, so Tktaalik refuses then (the setting can name commands:
  `on,update=off` lets patches be applied; turn it off to apply patches
  here).  The dialog shows the patch's
  header (`fossil patch view -v`: its baseline, who made it, on which
  host, when, from which checkout).  The dialog shows the dry run (`fossil patch apply
  -n`).  If the checkout has uncommitted changes, Fossil refuses unless
  **Discard the uncommitted changes of the checkout first** is checked:
  then those changes are lost.  Fossil's output is shown afterwards.
- **Commit ▸ View a patch…** shows the changes of a patch file in a diff
  window (`fossil patch diff`), who made it and when in its title,
  without applying it; its Options and **External diff** work there.  It
  works also when the repository does not have the patch's check-in.
