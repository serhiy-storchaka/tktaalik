# Go to

**Go to** opens anything in the repository that has a name: a hash, a
ticket id, a tag, a branch.  It works out what the name is and shows it in
the tab where it belongs.

Open it with **Ctrl+G**, or File ▸ **Go to…** in any tab.  Type the name and
press Return (or click **Go**).  If the name means one thing, the window
closes and that thing is shown; **Back** (Alt+Left) returns to where you
were.  The box remembers the last 30 names (its drop-down list).  Escape
closes the window.

## What it accepts

| You type | It shows |
|---|---|
| the hash of a check-in, or a prefix of it (at least 4 hex digits) | the check-in in the [Timeline](timeline.md) |
| a tag name, such as `core-9-0-2` | the newest check-in with that tag, in the Timeline |
| a branch name, such as `core-8-6-branch` | the branch in the [Branches](branches.md) tab |
| a ticket id or a prefix of it | the ticket in the [Tickets](tickets.md) tab |
| the hash of a ticket change | its ticket |
| the hash of a version of a wiki page or technote | that version in the [Wiki](wiki.md) tab |
| the hash of a forum post | its thread in the [Forum](forum.md) tab |
| the hash of a file's content | the file in the [Files](files.md) tab, in the first check-in that has that content |
| the hash of an attachment | the ticket, page or technote it is attached to |
| the hash of another event (a tag change, for example) | it in the Timeline |

The name can also be written as it appears in texts and links:

- in square brackets: `[4fd81d7dcd]`;
- as `tkt:HASH` or `info:HASH`;
- as a link copied from the web interface:
  `https://core.tcl-lang.org/tk/info/4fd81d7dcd`, `…/tktview/HASH`,
  `…/forumpost/HASH`, `…/timeline?c=HASH`.

Names that are none of the above are given to Fossil (`fossil whatis`),
which knows its other names of check-ins and dates:

| Name | The check-in |
|---|---|
| `tip` | the newest check-in |
| `current` | the one the checkout is at (in a checkout) |
| `prev`, `next` | its parent, its child (in a checkout) |
| a date, `2026-09-01`, or a date and time, `2026-09-01 12:00` | the newest event at or before then (to the end of the day for a date alone), shown as what it is: usually a check-in, but it can be a ticket change or a wiki edit |
| `root:BRANCH` | the check-in the branch was started from |
| `start:BRANCH` | the first check-in on the branch |
| `merge-in:BRANCH` | the check-in of the parent branch most recently merged into the branch |
| `tag:NAME` | the newest check-in with the tag, also when NAME looks like a hash |

In the list of [several matches](#several-matches) these show with the
hash they mean, as "tip (2641646046)".

If nothing has the name, the window stays open and says so, and you can
correct it.

## Several matches

A short hash prefix can match several things, and a name can be both a
branch and a tag, for example.  Then the window lists them all instead of
choosing:

| Column | What it shows |
|---|---|
| Kind | Check-in, Ticket, Ticket change, Wiki page, Technote, Forum post, File, Attachment, Tag, Branch, Event, Artifact |
| Name | the name or the start of the hash |
| (description) | the date, user and comment, the title, the file name and check-in… |

Double-click one, or choose it with the arrow keys (Down from the box goes to
the list) and press Return.  An "Artifact" without anything to show (a
control artifact or a cluster, Fossil's own records) is listed in grey and
cannot be opened.

A longer prefix narrows the list; with the full hash there is only one.
