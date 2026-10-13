# Stash

A stash keeps uncommitted changes of a checkout aside,
so that you can work on something else and bring them back later
(`fossil stash`).
The Stash tab lists the stashes of the checkout, searches them,
shows their files and diffs, applies them, drops them,
and goes to the check-in they were made on.
The current changes are stashed in the [Commit](commit.md#stashing-part-of-the-changes) tab.

Stashes belong to a checkout:
the tab is disabled when only a repository file is open.
They are stored in the checkout, not in the repository,
so they are never synced or pushed.

## The list

The top half of the tab lists the stashes, newest first:

| Column | Meaning |
|---|---|
| Stash | the stash's number (as `fossil stash` numbers them) |
| Date | when it was made |
| Made on | the check-in it was made on, and its branch |
| Files | how many files it changes |
| Comment | its comment |

Click a heading to sort by it.
The Stash and Comment columns are always shown;
the others can be hidden and moved like the columns of the other tabs.

Select a stash to see its details below: its number,
date and check-in (with a button that copies its whole hash,
and "the check-in of the checkout" if the checkout is on it now),
its comment, and the files it renamed, with their old names.
Under them is its diff (`fossil stash show`),
as in the [diff window](diffs.md#the-diff-window):
the files on the left, with lines added and removed,
the diff on the right, unified or side by side.
Only the files the stash really changes are counted and shown:
Fossil sometimes records every file of the checkout in a stash (after a rename),
most of them unchanged.

**Against the checkout**, above the diff, shows instead
each file of the stash compared with the checkout's file (`fossil stash diff`):
the lines removed are the checkout's, the lines added the stash's.
This is not what applying would do:
applying merges the stash's changes into the checkout's,
while this diff shows the checkout's own changes to the file as lines removed,
and an added file whole, whatever the checkout has of that name.
It is kept for the next stashes, and after a restart.

The last line of the details says whether the stash applies
to the checkout as it is now:
"Applies to the checkout without conflicts", or which of its files

- **conflict** with the changes in the checkout (in red, also in the list of files):
  the checkout changed them too, and merging both leaves conflict marks,
  or cannot be done (a binary file, a symbolic link, a missing file);
- **would overwrite** a file of the checkout (in orange):
  the stash adds a file, and the checkout has another one of that name;
- **would be deleted with the changes** the checkout made to them (in orange):
  the stash deletes a file the checkout has changed.

It is found as `fossil stash apply` would do it, without applying:
the files the checkout has not changed simply take the stash's version;
the others are merged by Fossil (`fossil 3-way-merge`)
on copies of the stash's versions.
It is checked when a stash is selected, and again after the list is read again
(F5, or coming back to the tab).

The context menu of a stash has the entries of the **Stash** menu.
Ctrl+C in the list copies the comment of the stash selected.
To stash the checkout's changes, all of them, some files,
or some changes of a file, use **Stash…** in the
[Commit](commit.md#stashing-part-of-the-changes) tab.

Above the diff are the buttons of the stash selected:
**Apply…**, **Apply and drop…**, **Go to…** and **Drop…**
(see [Applying stashes](#applying-stashes)),
and **Go back…** after **Go to…**, enabled while there is somewhere to go back to;
then **Against the checkout** (see above).

The **Stash ▸ Diff options** submenu
(the same as in the [Commit](commit.md#diffs) tab) applies to the diff: white space,
carriage returns, inverted, lines of context.

## Search syntax

The box at the top searches the stashes as you type.
Return (or the search button) also remembers the search in the box's list;
Escape (or the clear button) clears it.
Ctrl+F or Ctrl+/ goes to the box.
A list below the box completes the keys and their values as you type
(see [Completion](keys.md#completion-in-the-search-boxes)).

Words match a part of the comment or of a stashed file's name; a word with `*`,
`?` or `[…]` is a glob pattern for the file names.
All terms must match.
`-` before a term excludes, `a,b` after a key means a or b,
and "quotes" keep spaces.

| Term | Matches stashes |
|---|---|
| `comment:TEXT` | with the text in the comment |
| `file:PART` or `file:GLOB` | with a stashed file of that name (its new or old name) |
| `added:PART` or `added:GLOB` | that add such a file (`added:*`: any) |
| `deleted:PART` or `deleted:GLOB` | that delete such a file |
| `renamed:PART` or `renamed:GLOB` | that rename such a file (the old or the new name) |
| `diff:TEXT` | with the text in their changed lines |
| `branch:NAME` or `branch:GLOB` | made on a check-in of that branch |
| `on:HASH` | made on that check-in (a hash prefix) |
| `date:DATE` | made then: `2026`, `2026-09`, `2026-09-23`, `>=2026-09`, `A..B` |
| `files:N` | changing that many files: `1`, `>3`, `2..5` |
| `is:current` | made on the check-in the checkout is on now: they apply without merging |

Examples:

```
postponed -diff:TODO
added:*.test branch:main
file:tkFont date:>=2026-10
```

Stashes whose files matched are shown in bold in the list,
and the matching files in bold in the diff below;
it shows the first of them.
A mistake in the search is shown in red in the status line.

The status line counts the stashes shown,
and names the checkout. **Help ▸ Search syntax**
(or the help button by the search box) opens this page at
[Search syntax](#search-syntax).

## Applying stashes

Every action asks first; the confirmation says what it does.

**Apply…** merges the stash's changes into the files of the checkout as they are
now (`fossil stash apply`).
The confirmation checks the conflicts again and names the files
that would conflict, be overwritten, or be deleted with their changes
(see [The list](#the-list)).
The stash is kept.

**Apply and drop…** applies the stash,
then deletes it (like `fossil stash pop`, but for any stash,
not only the newest).

**Drop…** deletes the selected stash; its changes are lost.
Fossil can undo a single drop:
**Commit ▸ Undo…** right afterwards brings the stash back.
(After **Apply and drop**,
an undo brings back the stash but keeps the applied changes.)

**Stash ▸ Drop all…** deletes every stash of the checkout
(`fossil stash drop --all`).
Unlike dropping one, this cannot be undone; the confirmation warns so.

An applied stash can be taken back with **Commit ▸ Undo…**
(the apply is Fossil's last undoable command),
or by reverting the files in the [Commit](commit.md) tab.
After a successful apply, Tktaalik offers to show the Commit tab,
where the applied changes now are.

## Go to and Go back

A stash made on another check-in may not apply cleanly to the checkout as it is
now.
**Go to…** (**Stash ▸ Go to its check-in and apply…**) first updates the
checkout to the check-in the stash was made on, then applies the stash there,
exactly (`fossil stash goto`).
The stash is kept.
Commits made afterwards go to that check-in.

- Go to needs a checkout without uncommitted changes:
  stash them (**Stash…** in the Commit tab) or commit them first.
  Otherwise it says so and does nothing.
- If the checkout is already on that check-in, Go to is the same as Apply.
- The confirmation names the check-in
  (and branch) the checkout moves from and to.

Tktaalik remembers where the checkout was, for each checkout,
also after it is restarted.
**Go back…** then returns there:
it discards the changes in the checkout
(`fossil revert`; the stash still has them) and updates the checkout back to
that check-in (`fossil update --nosync`). The confirmation lists the changes
that will be discarded: the applied stash, and anything you changed since.
**Go back** is disabled when there is nowhere to return to;
its tooltip says where it goes.

Fossil's own undo does not do this reliably:
after `stash goto` it restores the check-in but not its files.
Use **Go back**.
