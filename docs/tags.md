# Tags

The Tags tab lists the tags of the check-ins: release tags such as
`core-9-0-4`, tags that CI builds, and any others, each with the check-in it
is on and its history.  On request it also lists branch names, tags
cancelled everywhere, and properties.  Tags can be added to check-ins and
cancelled on them; that changes the local repository only, and nothing is
pushed.

A tag in Fossil is a name, sometimes with a value, attached to a check-in.
A tag can **propagate**: then it is also on all the descendants, until it
is cancelled or replaced (this is how branch names work).  Fossil also
keeps **properties** as tags without the `sym-` prefix of symbolic names:
`bgcolor`, `closed`, `hidden`, `comment`, and others.

## The list

At the top: **Find**, which narrows the list to the tags whose names
contain what you type, and three check boxes:

| Check box | Adds to the list |
|---|---|
| Branch names | The names of branches (propagating tags named as a branch is, or was).  Other propagating tags, like `tip-466` set on a branch to say what it is for, are tags |
| Cancelled | Tags cancelled on every check-in they were on |
| Properties | Fossil's raw tags: bgcolor, closed, hidden, comment… |

Without them, only the tags currently on check-ins are listed.  The status
line counts all four kinds, and how many are shown.

### Columns

| Column | What it shows |
|---|---|
| Tag | The name |
| Kind | Tag, Branch, Cancelled or Property |
| Check-in | The newest check-in the tag is on (for a branch: its newest check-in; for a cancelled tag: where it was last) |
| Date, User, Comment | Of that check-in (as edited, if it was) |
| Check-ins | How many check-ins the tag is on, counting those it propagated to (hidden at first) |

Branch names are in blue, cancelled tags in grey, properties in brown.
Click a heading to sort by it, drag it to move the column, and right-click
a heading to choose the columns.

### Buttons and keys

| Button | Does |
|---|---|
| Add… | Add the selected tag (or another) to a check-in; see [Adding and cancelling tags](#adding-and-cancelling-tags) |
| Cancel… | Cancel the selected tag on a check-in it is on (tags and properties) |
| Show in Timeline | The tag's check-in in the [Timeline](timeline.md) (not for branch names); also a double-click |
| Show in Branches | The branch in the [Branches](branches.md) tab (branch names only) |
| Open in browser | The server's timeline of the tag (`/timeline?t=NAME`; not for properties) |

The **Tag** menu has the same Add tag… and Cancel tag… entries, and
**Save as archive…**: the tag's check-in (a release…) as a ZIP, tarball or
SQL archive (see [Archives](timeline.md#archives)); also in the context
menu.  Ctrl+F
goes to Find; F5 (File ▸ Refresh) reads the repository again.  Back and
Forward remember the filter, the check boxes and the selected tag.

### Examples

To see what a release tag is on and when it moved, type part of its name
in Find, for example `core-9-0`, and select the tag: the details show its
history.  To find where a check-in colour was set, check **Properties** and
find `bgcolor`.

## History

Below the list, the details of the selected tag:

- For a tag or a property: each check-in it was added to or cancelled on,
  oldest first, with the date, the check-in's hash, the value (after `=`)
  and the first line of the check-in's comment.  Only the places where the
  tag was set or cancelled are listed, not every check-in it propagated
  to.  A tag with a long history shows its newest 1000 entries.
- For a branch name: how many check-ins are on the branch, and the date and
  user of the newest one.  The [Branches](branches.md) tab has the rest.

A release tag that was moved shows as "added to" one check-in, "cancelled
on" it, and "added to" another.

## Adding and cancelling tags

Both run Fossil's own commands (`fossil tag add`, `fossil tag cancel`),
first as a dry run: a window shows the command and the control artifact
Fossil would record, with **Apply** and **Cancel**.  Only Apply changes the
repository.  The change is a new artifact in the local repository, written
as the repository's default user; it reaches the server with your next
push, made outside Tktaalik.

### Add…

Opens the Add tag dialog, with the selected tag's name filled in (not for
properties):

| Field | Meaning |
|---|---|
| Check-in | Where to put the tag: a hash, a tag or a branch name (its newest check-in), or a date |
| Tag | The name, without spaces; Fossil adds the `sym-` prefix itself, so do not type it |
| Value | An optional value |
| Propagate to the descendants | The tag goes on to all descendants, as a branch name does (`--propagate`) |
| Raw name | A property (bgcolor, closed, …) rather than a symbolic tag (`--raw`) |

Tag names starting with `wiki-`, `tkt-` or `event-` are refused: they are
Fossil's own.  Names and values cannot start with `-`, `<`, `>` or `|`.

Examples: tag a release candidate `core-9-0-4-rc` on the check-in
`a1b2c3d4e5`; give a check-in a timeline colour with the raw tag `bgcolor`
and the value `#ffd0d0`.

The same dialog opens from the [Timeline](timeline.md#tags-on-check-ins)
(right-click a check-in ▸ Add tag…), with the check-in filled in.

### Cancel…

Cancels the selected tag or property.  If it was added to more than one
check-in, a dialog asks on which one (the newest first).  Cancelling a tag
that propagates also ends it on the descendants.  Branch names are not
cancelled here: close, hide or rename branches in the
[Branches](branches.md#managing-branches) tab or with
[Edit check-in](timeline.md#editing-check-ins).
