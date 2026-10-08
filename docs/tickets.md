# Tickets

The Tickets tab finds tickets with a search like GitHub's, shows one
ticket at a time with its description, comments, the check-ins that
mention it, its attachments and its history, and lets you comment on
tickets, edit them and create new ones.

Everything you write here goes into the local repository only, as the
repository's default user, with `fossil ticket`.  Nothing is pushed:
sending the changes to the server stays a separate step (`fossil push`
or `fossil sync` on the command line).

## The search box

The box at the top takes a search (see [Search syntax](#search-syntax)).
Press Return, or click the magnifier, to search.  The other buttons:

| Button | What it does |
|---|---|
| **Searches** | built-in and saved searches (see below) |
| magnifier | search (Return) |
| save | save the search under a name |
| clear | clear the search (Escape) |
| help | this page, at [Search syntax](#search-syntax) |

Under the box, **Open**, **Pending**, **Closed** and **All** switch the
state quickly: they replace the `is:` term of the search (All removes
it).  The search box remembers your earlier searches in its drop-down.

Ctrl+F goes to the search box from anywhere in the tab; F5 searches
again.

### Built-in and saved searches

The **Searches** button lists ready searches, each only if the tickets of
the repository have the fields it needs:

| Search | Query |
|---|---|
| Assigned to me | `is:open assignee:@me` |
| Involving me | `is:open involves:@me` |
| Open bugs | `is:open type:bug` |
| Open patches | `is:open type:patch` |
| Open RFEs | `is:open type:rfe` |
| Unassigned | `is:open no:assignee` |
| High priority | `is:open priority:>=7` |
| Critical | `is:open severity:critical,severe` |
| Never answered | `is:open no:comments` |
| In progress | `is:open has:checkins` |

"Assigned to me" and "Involving me" appear only when the repository has a
default user.  Your own searches, saved with the save button, follow
them; **Remove saved search** deletes one.  Saved searches are kept in
the settings file `tickets.conf` (see [Configuration](configuration.md)).

## Search syntax

Terms are combined with AND: a ticket must match all of them.  A term is
`key:value`, or a word.

| Term | Finds |
|---|---|
| `is:open`, `is:closed`, `is:pending`, `is:deleted` | tickets in that state |
| `state:open,pending` | any of these states |
| `type:bug`, `is:bug`, `is:rfe`, `is:patch`, `is:support` | the type |
| `subsystem:name`, `subsystem:12` | the subsystem, case-insensitive, with or without the "NN." numbering and brackets |
| `resolution:`, `priority:`, `severity:` | those fields |
| `version:8.6`, `version:>=8.6.10`, `version:8.6.10..8.6.13` | the Found in version, compared as versions (see below) |
| `author:`, `assignee:`, `closer:` | the submitter, assignee, closer |
| `involves:user` | the submitter, assignee or closer is the user |
| `@me` | you: `assignee:@me`, `involves:@me` (the default user) |
| `no:assignee`, `has:assignee` | the field is empty ("", "None", "nobody") or not |
| `created:2025`, `updated:<2020`, `closed:2025-01..2025-06` | dates |
| `comments:>5`, `checkins:0`, `attachments:>0`, `comments:1..3` | counts |
| `has:checkins`, `no:comments`, `has:attachments` | counts other than 0, or 0 |
| `id:1a2b3c` | a ticket id prefix |
| `tip:512`, `tip:>=700` | the TIP number (in the TIPs repository) |
| `in:title` | words match the title only |
| `is:private` | private tickets (when the repository has them) |

States: Fossil's own ticket setup has more statuses than open, pending
and closed.  Verified and Review count as open, Deferred as pending,
Fixed and Tested as closed.

Values:

- A comma means OR: `type:bug,rfe`.
- A leading minus excludes: `-type:rfe`, `-resolution:none`, also
  `-word`.
- `*` is a wildcard: `version:8.6*`.
- Versions (`version:`, the "Found in" field) are matched as versions:
  `version:8.6` finds the whole 8.6 line: 8.6, 8.6.10, 8.6b1, "obsolete:
  8.6b1.1" (words before the number are ignored) and core-8-6-branch.
  The parts given must be equal, so `version:8.6.1` finds 8.6.1 and its
  betas, not 8.6.18.  Versions are compared as numbers:
  `version:>=8.6.10`, `version:8.6.10..8.6.13`; a beta comes before its
  release, a line's branch (core-8-6-branch) after its releases, and trunk
  and main after everything.  Other values (`version:revised_text`,
  `version:None`) and patterns with `*` are matched as text.  Clicking a
  Found in value in the details searches its version number.
- Numbers can be compared: `priority:>=7`, `comments:>5`; ranges with
  `..`: `comments:1..3`.  `priority:high` works too.
- Dates are `YYYY`, `YYYY-MM` or `YYYY-MM-DD`, compared with `<`, `<=`,
  `>`, `>=`, or a range `2025-01..2025-06`.
- Field names have aliases: `kind:` is `type:`, `component:` and
  `label:` are `subsystem:`, `reason:` is `resolution:`, `foundin:` is
  `version:`, `submitter:` is `author:`.
- `status:` and `state:` match the status field as written
  (`status:Verified`); `state:` with only the states open, pending,
  closed and deleted matches those groups, as `is:` does.

Words must appear in the title or the description (only the title with
`in:title`); `"an exact phrase"` in quotes.  A word that looks like a
ticket id also finds the ticket: 6 or 7 digits (an old SourceForge
number), 10 hexadecimal digits (an abbreviated id), the full id, also in
brackets like `[3131699cb4]`.  A `key:value` with an unknown key is
searched as text.

A key the tickets of the repository do not have (for example `tip:`
outside the TIPs repository) is an error, shown in the status line.

Examples:

```
is:open type:bug,rfe -resolution:none crash
is:open assignee:@me
involves:jan.nijtmans updated:>=2026-09
is:closed closed:2025 subsystem:menus
comments:0 is:open created:<2020
220849
"native menu" in:title
is:open version:8.6 -version:>=8.6.13
```

## The list

One row per ticket found, newest change first by default; the status line
counts them.  Tickets that are not open (pending, closed, deleted) are
shown in grey.

Columns (which ones exist depends on the fields of the repository's
tickets): Ticket id, Title, TIP, Type, Status, Subsystem, Priority,
Severity, Found in, Assignee, Submitter, Closer, Created, Updated, Closed,
Comments, Check-ins, Attachments.  The defaults are TIP, Type, Status,
Subsystem, Priority, Severity, Found in, Assignee and Updated, besides the
title and id.

- Click a heading to sort by it, again to reverse.  Drag a heading to move
  the column (any column, also Title and Ticket id).
- Right-click a heading to choose the columns and their order.
- Status, Priority and Severity are shown as icons, with icon headings;
  hover over a heading or a cell for its name or value.  The status icon
  tells the resolution of a closed ticket: fixed, duplicate, invalid,
  works for me, rejected, out of date, postponed; open, pending and
  deleted have icons of their own.  Priorities are chevrons, severities go
  from critical to cosmetic.  (With Tk 8.6, which cannot show images in
  table cells, the list shows emoji instead.)
- Status also sorts by the resolution.
- Comments, Check-ins and Attachments are counts, blank for none.

Double-click a ticket (or press Return) to edit it: see
[Editing tickets](#editing-tickets).  Its web page is in the context menu
(Open in browser).  Right-click a ticket for:

| Entry | What it does |
|---|---|
| Filter *term* / Exclude *term* | add `key:value` (or `-key:value`) of the cell you clicked to the search |
| Open in browser | the ticket on the server |
| Copy ticket id | to the clipboard |
| Edit ticket… | see [Editing tickets](#editing-tickets) |
| Copy title | to the clipboard |

## Details

The ticket selected is shown below the list.  Its header has the title,
the fields with their icons (TIP, Type, Status with the resolution,
Subsystem, Priority, Severity, Found in, Assignee) and an **Edit…** button,
then the short id, when it was opened and by whom, updated, and closed
and by whom.

The values are links (in blue): click one to search the tickets with that
value, for example **Bug** searches `type:bug`, the submitter `author:NAME`,
the closer `closer:NAME`; the status and the resolution are links each.
Ctrl+click adds the value to the search instead.  Back returns to the
search before.

Below are four tabs; Alt+C, Alt+I, Alt+A and Alt+H switch between them.
Tabs with nothing in them are disabled, and their labels count the items.

- **Comments**: the description and the comments, see [Comments](#comments).
- **Check-ins**: the check-ins whose comments mention the ticket (any
  prefix of its id): date, check-in, user and comment.  Double-click or
  Return shows the check-in in the [Timeline](timeline.md) (its files and
  diff are there); right-click for Show in Timeline, Diff of this
  check-in, Open in browser and Copy check-in.
- **Attachments**: see [Attachments](#attachments).
- **History**: see [History](#history).

## Comments

The description comes first, then each comment, each in a panel with who
wrote it and when.  Fossil wiki, Markdown and HTML text is shown formatted, as
Fossil renders it; plain text as written.  Links can be clicked: links to
tickets open them here; `[hash]` references and links to check-ins and
other artifacts open them in Tktaalik (a check-in in the
[Timeline](timeline.md), as [Go to](goto.md) does), links to a branch
(`/timeline?r=BRANCH`) in the [Branches](branches.md) tab, links to a diff
(`/vdiff?…`) in the diff window; other links open in the browser, and end
with a small ↗.

At the end is the **Add a comment…** button.  It opens a window with the
ticket's title and the editor of the comment:

- the **Format**: Fossil wiki, Markdown, Plain text or HTML;
- the **Write** and **Preview** tabs (Alt+W, Alt+P, or Ctrl+Shift+P to go
  from one to the other): the preview shows the comment as it will be
  shown, rendered by Fossil.

**Post** (or Ctrl+Return) asks first, showing the comment; once written it
cannot be changed or taken back, and it is not pushed.  **Cancel** (or
Escape) keeps what you wrote as a draft of the ticket: the button's note
says "a draft is waiting", and the draft comes back when you open the
window again.

Comments need a default user in the repository (see
[Users](repository.md#users)); without one the button is disabled and its
note says so.

Old ticket setups have no separate comments: there a comment is appended
to the description, after a line saying who added it and when, as
Fossil's ticket pages did then (`fossil ticket set ID +comment ...`).  The
format is then Fossil wiki, and cannot be chosen.

## Editing tickets

**Ticket ▸ Edit ticket…** (Ctrl+E), the **Edit…** button of the details, or
**Edit ticket…** in the list's context menu opens a form with the fields of
the ticket: Title, Type, Status, Resolution, Subsystem, Priority, Severity,
Found in, Assignee and TIP, those the repository's tickets have, and the
repository's own fields (a ticket setup can add columns, like `fix_version`:
they are also columns of the list, in the details, and search keys by their
name, `fix_version:9.0.4`).  Status, Resolution, Priority and Severity are
menus with their icons; fields with choices in the repository's ticket setup
offer them in a drop-down.  An optional comment can be added in the same
change, in the same editor as in the comment window (format, Write,
Preview).

**Save** shows what changes (each field old → new, and the comment) and
asks before writing it with `fossil ticket set`.  As the web pages do,
closing a ticket also records you as the closer and the date, and
reopening it clears the closer.  A field cannot be emptied from here:
Fossil's command line cannot set an empty value.

**Ticket ▸ New ticket…** (Ctrl+N) asks for the title, type, found in,
subsystem and severity, the repository's own fields (those of its ticket
setup that Tktaalik does not know, empty ones left out), and a description,
written in the same editor (format, Write, Preview: see
[Comments](#comments)).  **Create** is enabled when there are a title and a
description.  The new ticket also gets what the web form sets: status Open,
resolution None, priority "5 Medium", nobody assigned, you as the submitter.
After a confirmation it is written with `fossil ticket add` and shown.

Changes are recorded as the default user of the repository; without one,
Tktaalik says so and changes nothing.

## Closing tickets

**Ticket ▸ Close ticket…**, the **Close…** button of the details (shown
while the ticket is not closed), or **Close ticket…** in the list's
context menu opens a window with the ticket's **Resolution** — **Fixed**
for a bug, **Accepted** for other types, any of the repository's
resolutions to choose — and an optional closing comment, written in the
same editor as other comments (format, Write, Preview).  **Close** (or
Ctrl+Return in the comment) shows the change and asks before writing it:
the status Closed, the resolution and the comment go in one ticket change,
which also records you as the closer and the date, as the web pages do.

## Attachments

The Attachments tab lists the newest version of each file attached to the
ticket: file, size, user, date and comment.  An attachment whose content
is not in the local repository is greyed out.

- Double-click (or Return) views a text attachment, a patch as a diff, in
  Tktaalik's diff viewer (see [Diffs](diffs.md)); an attachment that is
  not here opens on the server.
- Right-click: **View**, **Save…**, **Apply to the checkout…** (for
  `.patch` and `.diff` files), **Open in browser**, **Copy file name**.

**Apply to the checkout…** needs an open checkout and the `patch` program.
It finds whether the patch applies with `-p0` or `-p1`, shows the dry run
and asks first; afterwards it offers to show the Commit tab.  The files
of the checkout change; nothing is committed.

Tickets cannot get new attachments here: Fossil has no command for that.

## History

The History tab lists every change of the ticket, newest first, as
`fossil ticket history` tells it: who and when, then each field the
change set (`change status: Closed`, ...).  Comments are shown by their
first words only (they are in the Comments tab).  The history is read
when the tab is shown.

## Reports

**Ticket ▸ Reports…** opens a window with the ticket reports stored in the
repository (the reports of the web pages' Tickets menu).  Choose one on
the left to run it.

- The results are a table with the report's columns.  Rows are coloured
  as on the web pages (the report's `bgcolor` column).  Columns whose
  name starts with `_` are shown under the table, for the row selected.
- `$login` in a report is the default user, as the web pages use the user
  logged in, so reports like "All Open Assigned To Me" work.
- **Filter**: an SQL condition on the report's columns, for example
  `"Status" = 'Open'` or `"Type" = 'Patch'`; Return or **Run** runs the
  report again with it.  An error is shown in the status line.
- Double-click a row of a report with a `#` column to show that ticket in
  the Tickets tab.
- **Open in browser** opens the report on the server.  F5 runs it again.
- **Save as…** writes the results (all the columns, the hidden ones too)
  to a file: tab-separated (`.tsv`, as `fossil ticket show` writes them)
  or CSV (`.csv`).

The reports are run read-only; they are not changed here.  The status
line tells the number of rows and who wrote the report.
