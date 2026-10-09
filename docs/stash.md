# Stash

A stash keeps uncommitted changes of a checkout aside,
so that you can work on something else and bring them back later
(`fossil stash`).
The Stash tab lists the stashes of the checkout, searches them,
shows their files and diffs, applies them, drops them,
goes to the check-in they were made on, and stashes the current changes.

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
date and check-in (with "the check-in of the checkout" if the checkout is on it
now), its comment, and its files, each marked `added`, `deleted`,
`renamed` (with its old name) or `changed`.
Only the files the stash really changes are counted and listed:
Fossil sometimes records every file of the checkout in a stash (after a rename),
most of them unchanged.

The context menu of a stash has the entries of the **Stash** menu,
which also has **Copy comment**.
To stash only some files, or some changes of a file,
use Commit ▸ Stash the checked changes… in the
[Commit](commit.md#stashing-part-of-the-changes) tab.

Double-click a stash, or press **Show diff**,
for its diff in the diff window ([Diffs](diffs.md)).
**Stash ▸ Diff against checkout** shows instead how the files of the checkout
would change if the stash were applied now (`fossil stash diff`).
The **Stash ▸ Diff options** submenu
(the same as in the [Commit](commit.md#diffs) tab) applies to both: white space,
carriage returns, inverted, lines of context.

## Search syntax

The box at the top searches the stashes as you type.
Return (or the search button) also remembers the search in the box's list;
Escape (or the clear button) clears it.
Ctrl+F goes to the box.

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
and the matching files in bold in the details;
**Show diff** opens at the first of them.
A mistake in the search is shown in red in the status line.

The status line counts the stashes shown,
and names the checkout. **Help ▸ Search syntax**
(or the help button by the search box) opens this page at
[Search syntax](#search-syntax).

## Applying stashes

Every action asks first; the confirmation says what it does.

**Apply…** merges the stash's changes into the files of the checkout as they are
now (`fossil stash apply`).
If the checkout has uncommitted changes,
the confirmation warns that they can conflict.
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
  stash them (Stash changes) or commit them first.
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

## Stashing changes

**Stash changes…** saves the checkout's changes as a new stash,
then reverts them, so that the checkout is clean (`fossil stash save`).
The dialog asks for:

- **Comment**: what the stash is about (empty: `(no comment)`);
- **the files**: every changed file, checked;
  uncheck the ones not to stash (click the box, or select it and press Space).
  The unchecked ones stay changed in the checkout;
- **Keep the changes in the checkout too**:
  make a snapshot instead (`fossil stash snapshot`): the stash is made,
  but nothing is reverted.

If the checkout has no changes, it says so.
Stashing itself cannot be undone with Fossil's undo, but nothing is lost:
the changes are in the stash, and **Apply** brings them back.
