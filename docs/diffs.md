# Diffs

Diffs open in Tktaalik's own diff window, from every tab that has them:

- [Timeline](timeline.md): double-click a check-in (or Return),
  or **Diff** in its context menu;
- [Branches](branches.md): the diff of a branch,
  of a branch against a merge target, of a check-in,
  the changes between two releases;
- [Files](files.md): a version of a file against the one before it;
- [Commit](commit.md):
  the changes of a file (double-click it) or of the whole checkout,
  the changes since the last undoable command, a patch file;
- [Stash](stash.md): a stash, and a stash against the checkout;
- [Wiki](wiki.md): what a version of a page changed (**Changes**, **Since**);
- [Tickets](tickets.md): a patch attached to a ticket.

The same window also shows plain texts that are not diffs:
text attachments of tickets and wiki pages,
and unversioned files ([View](repository.md#unversioned-files)).

## The diff window

Each diff opens a window of its own, titled with what it compares;
open as many as you like.
It has:

- at the top, the title, **Unified** and **Side by side**, **External diff**,
  the **Options** menu (see [Diff options](#diff-options)), and **Close**;
- under it, for the diffs of `fossil diff`, which versions are compared:
  "From HASH DATE → to HASH DATE",
  or "to the checkout's files" for the changes not committed (`fossil diff -h`);
- on the left, the files changed,
  each with the number of lines added (+) and removed (−);
- on the right, the diff;
- at the bottom, a status line: how many files, and lines added and removed.

**Unified** shows each file's changes as one text: removed lines in red,
added lines in green, the `@@` lines that say where a change is in blue,
and the lines around the changes unmarked.
**Side by side** shows the old version on the left and the new one on the right,
with line numbers; a changed block is a row of removed lines next to the added
ones, the shorter side filled with grey.
Both sides scroll together.
Switching between the two keeps the diff;
the choice is the window's own
(the diff of a single file from the Commit and Files tabs opens side by side,
the others unified).

Select a file in the list to jump to it.
A big diff (more than 20 000 lines) is shown one file at a time:
then selecting a file shows that file, and the status line says "big:
one file at a time".

A patch (a ticket attachment,
a patch file) may begin with a description before its first file:
it is listed as "(description)".
A plain text is listed the same way.

While a diff is being computed the status line says "Comparing…";
the window can be used, or closed, at once.
Escape or **Close** closes the window.

Text can be selected and copied (Ctrl+C) from the diff.

**External diff** shows the same diff, with the same options,
in your graphical diff program:
the one the `gdiff-command` setting names
(see [Settings](repository.md#settings)),
or without it Fossil's own
(`fossil gdiff`; for a stash `stash gshow`/`gdiff`,
for a patch `patch gdiff`). Its tooltip says which.
The windows that show a fixed text have no such button.

## Diff options

The **Options** menu of a diff window has the options of `fossil diff` that
change what is compared.
Changing one computes the diff again, in the same window,
and keeps the file shown.

| Option | Fossil option | What it does |
|---|---|---|
| Ignore all white space | `-w` | lines that differ only in spaces and tabs are the same |
| Ignore white space at line ends | `-Z` | spaces and tabs at the ends of lines do not count |
| Ignore carriage returns | `--strip-trailing-cr` | CRLF and LF line ends are the same |
| Invert: the other way round | `--invert` | the new version as the old one: what was added is shown removed |
| Lines of context | `-c N` | how many unchanged lines are shown around each change: **Default (5)** (Fossil's, no `-c`), 0, 1, 3, 10, 25, 100, or Whole files |

The options belong to the window: a new diff window starts with none of them.
The diff windows that show a fixed text
(a wiki page's changes, a ticket's patch attachment,
an unversioned file) have no Options menu.

The [Commit](commit.md) and [Stash](stash.md) tabs also have a **Diff options**
submenu in their menus,
with the same options (and "Whole files" for the context).
Those apply to the diffs the tab shows and to the diff windows it opens,
and stay set until you change them or quit.
