# Files

The Files tab shows the files of the repository as they were at any version,
and for one file its history, its blame and its content.
It only reads the repository:
nothing here changes the checkout or the repository.

The tab has three parts: the **Version** and **Find file** boxes at the top,
the tree of files on the left,
and on the right the selected file with four tabs of its own: **History**,
**Blame**, **Content** and **Find in history**.
The status line at the bottom says how many files are shown and at which
check-in.

## Versions

The **Version** box chooses the version of the tree.
Its list offers:

| Choice | What it shows |
|---|---|
| `checkout` | the check-in the checkout is on (only when a checkout is open) |
| `main` or `trunk` | the newest check-in of the main branch |
| a branch name | the newest check-in of that branch |

You can also type into the box and press Return:

- a branch or tag name (for example `core-9-0-branch` or `core-9-0-2`):
  its newest check-in;
- a check-in hash, or a unique prefix of one (at least 4 hex digits).

If the name matches nothing, the status line says `No check-in "…"` in red,
and the tree stays as it was.

The tree shows, for each file,
when it **Last changed** before that version and its **Size**
(as `fossil ls --age -v`); a directory shows the newest change of its files.
Click a heading to sort the tree by name,
by date (newest first) or by size (biggest first), within each directory;
click it again for the other order.

**Find file** narrows the tree to the files whose path contains the text
(upper and lower case are the same).
The tree is filtered as you type; with a filter, the directories are shown open.
Ctrl+F goes to this box.

When the version is `checkout` and the checkout has moved
(an update, a merge, a commit in another tab or outside),
the tree is read again when you come back to the tab.
**File ▸ Refresh** (F5) reads the version and the selected file again at any
time.

Select a file in the tree to show it on the right;
its path is the title above the three tabs.
Right-click a file for its context menu:

| Entry | What it does |
|---|---|
| History of FILE | the History tab of the file |
| Content | the Content tab |
| Blame | the Blame tab |
| Find in its history… | the Find in history tab, see [Find in history](#find-in-history) |
| Open in browser | the file's history page on the remote's web site (only when the repository has a remote) |
| Copy path | the file's path, to the clipboard |

The **File** menu has more for the version and the file:

- **History of the file**, **Find in the file's history…**,
  **Content of the file**, **Blame of the file**, **Open the file in browser**,
  **Copy the file's path**: the entries of the file's context menu;
- **Find a local file in history…**:
  see [A local file in history](#a-local-file-in-history);
- **Save this version as an archive…**: see [Archives](#archives).

## Content

The **Content** tab shows the text of the file, with line numbers,
at the version of the tree.
A binary file shows `(not a text file)`.

From the [History](#file-history) you can show the content of any earlier
version: then the title says which,
for example `README.md at 8922a99ffb` (with the name the file had then).
Selecting another file in the tree, or **History of the file**,
goes back to the version of the tree.

## Blame

The **Blame** tab shows, for each line of the file,
the check-in that last changed it: its hash, its date, the user,
the line number and the line.
Lines of the same check-in share a background shade,
alternating between check-ins, so that runs of lines from one change stand out.

- **Double-click** a line for the diff of the check-in that changed it
  (the file only, side by side; see [Diffs](diffs.md)).
  The check-in is also selected in the History tab.
- **Ignore white space**
  (the check box under the blame) recomputes it ignoring changes in white space
  only (`fossil blame -w`),
  so that a re-indentation does not hide who wrote a line.

The blame needs a checkout:
Fossil's `blame` command only works in one. Without a checkout the tab says so.
For a long history the blame takes a while;
it is computed in the background
(`Finding who changed each line…`) and you can go on working.

Like the content, the blame can be shown for an earlier version of the file from
its History (the title then says which).

Below the blame are its options (as `fossil blame`'s):

| Option | What it does |
|---|---|
| Ignore white space | changes of white space only do not count (`-w`) |
| At line ends only | only changes of white space at the ends of lines do not count (`-Z`) |
| Reverse, towards | a later version (a branch, a tag, a hash, `checkout`): for each line of the version shown, the check-in that changed or removed it *after* it, on the way to that version (`-o`); lines never changed on the way show `unchanged` |
| How far back | `none` (the whole history), a number of versions (`100`), or seconds (`5s`: as far as 5 seconds allow) (`-n`); lines from further back show `older` |

Return, or choosing from a list, computes the blame again.

## Copying lines

Right-click the Content or the Blame for:

- **Copy line N** or **Copy lines N–M**:
  the selected lines (or the line clicked),
  without the line numbers or the blame's columns;
- **Copy link to lines N–M**:
  the address of these lines on the remote's web site,
  as `fossil remote hyperlink` makes it
  (the file of the version shown, `/info/HASH?ln=N,M`);
  only when the repository has a remote;
- in the Blame, **Diff of the check-in of line N**.

## File history

The **History** tab lists the check-ins, on all branches, that changed the file,
newest first.
The tab's label counts them, for example `History (452)`.

| Column | Meaning |
|---|---|
| Date | when the check-in was made |
| Check-in | the check-in's hash (10 digits) |
| User | who made it |
| Branch | the branch it is on |
| (how) | `added`, `changed`, `renamed` or `deleted` |
| File | the hash of the file's content in that version (as `fossil finfo -i`) |
| Name | the file's name in that check-in (only shown if the file was renamed) |
| Comment | the check-in comment |

The history follows the file through renames: when a check-in renamed the file,
the check-ins that changed it under its earlier name, before the rename,
are listed too, back to where the file was added.
The **Name** column appears only when the name changed somewhere in the history.

Double-click a version (or press Return) for its diff:
the changes that check-in made to the file, side by side,
under the name the file had in it.
Right-click a version for its context menu:

| Entry | What it does |
|---|---|
| Diff against the previous version | the same as a double-click |
| Show the check-in in Timeline | the check-in of that version in the [Timeline](timeline.md) |
| Content of this version | the Content tab at that version |
| Blame of this version | the Blame tab at that version |
| Save this version… | saves the file as it was in that check-in to a file you choose (`fossil cat -o`) |
| Open in browser | the file at that check-in on the remote's web site |
| Copy check-in | the full hash, to the clipboard |
| Copy file hash | the hash of the file's content in that version |

Content, Blame and Save are disabled for a version that deletes the file.

**File ▸ History of the file** returns to the history of the selected file,
and to the version of the tree for its content and blame.

**Back** and **Forward**
(Alt+Left, Alt+Right; see [Keys](keys.md)) remember the version of the tree,
the filter, the file,
the tab shown and the version of the file whose content or blame is shown.

## Find in history

The **Find in history** tab searches all the versions of the selected file
(also under its earlier names) for a regular expression
(POSIX extended, as `fossil grep`), newest first.
Type it in **Find** and press Return or **Find**:

| Option | What it does |
|---|---|
| Ignore case | upper and lower case are the same (`-i`) |
| The newest match only | stop at the newest version that matches (`--once`) |
| Versions without it | list the versions that do *not* match (`-v`) |

Each version that matches is listed with its date, check-in and file name,
and under it the lines that match,
with their numbers. Double-click a version for its content;
double-click a line for the content of that version at that line (selected).
The status line counts the lines and the versions.

## A local file in history

**File ▸ Find a local file in history…** asks for a file on your disk and lists
the check-ins that committed exactly its content (`fossil whatis -f`),
with the name the file had in each: the date, the check-in, the user,
the name and the comment.
Double-click one (or **Show it**) for the Files tab at that check-in,
with the file's content.
Its context menu also has **Show in Timeline**,
**Copy check-in** and **Copy file name**.
If the content is in no version of the repository, the window says so.

## Archives

**File ▸ Save this version as an archive…** saves the files of the version of
the tree as an archive (`fossil zip`, `tarball` or `sqlar`):

| Field | What it does |
|---|---|
| Format | ZIP (`.zip`), Tarball (`.tar.gz`) or SQLite archive (`.sqlar`) |
| Top folder | the folder the files are in, inside the archive (`--name`); at first the project's name and the version |
| Only files | patterns of the files to put in, separated by commas, like `doc/*,*.md` (`--include`); empty: all |
| Without files | patterns of the files to leave out (`--exclude`) |

**Save…** then asks where.
Only that file is written; the repository is not changed.
