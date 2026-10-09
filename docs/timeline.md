# Timeline

The Timeline tab shows everything that happened in the repository, newest
first: check-ins, ticket changes, tag changes (closed and hidden branches,
release tags), wiki edits, forum posts and technote edits.  It reads the
repository file directly, so it works the same on a checkout and on a
repository opened without one.

From here you can also edit check-ins, add and cancel tags, bisect a
regression in the checkout and pull from a remote.  All of these change the
local repository only: **nothing is ever pushed**.

## The window

From top to bottom:

- **The search box**, with the Search, Clear and Help buttons at its right.
  See [Search syntax](#search-syntax).
- **The views**: All, Last pull, Outgoing, Private, each with the number of
  events that match the search.  See [Views](#views).
- **The list** of events.
- **The details** of the selected event, with buttons above them.  See
  [Details](#details).
- **The status line**: how many events are shown (the newest 1000 of N,
  with a **More** button that shows twice as many), when the last pull was,
  how many artifacts are not pushed yet, how many are private, the state of
  a bisect, and the repository file.

### Columns

| Column | What it shows |
|---|---|
| Date | When it happened, in UTC (as Fossil records it) |
| Kind | Check-in, ticket change, tag change, wiki, forum or technote edit; an icon in Tk 9 (the word in its tooltip), the word in Tk 8.6 |
| User | Who made it |
| Branch | The branch of a check-in |
| Ticket | The ticket of a ticket change |
| Hash | The first ten digits of the artifact's hash; for a check-in, its tooltip is `fossil describe` of it (see [Tags on check-ins](#tags-on-check-ins)) |
| Comment | The comment, with Fossil's link markup removed |

Ticket and Hash are hidden at first.  Click a heading to sort by it, drag
it to move the column, and right-click a heading to choose the columns.
Date and Comment are always shown.

### Colours

| Look | Meaning |
|---|---|
| Brown text | Not pushed yet (an unsent artifact) |
| Purple italics | Private: never pushed |
| Bold | The check-in the checkout is on |
| Green background | Marked good in a bisect |
| Red background | Marked bad in a bisect |
| Grey background | Skipped in a bisect |

### Mouse and keys

| Action | Does |
|---|---|
| Double-click, or Return | A check-in: its diff in the [diff viewer](diffs.md).  A ticket change: the ticket in the [Tickets](tickets.md) tab.  A wiki or technote edit: the page or technote in the [Wiki](wiki.md) tab; a forum post: its thread in the [Forum](forum.md) tab (also the Show in Wiki / Show in Forum button of the details, and the context menu) |
| Right-click a row | The context menu (below) |
| Ctrl+F | Go to the search box |
| Escape in the search box | Clear the search |
| F5, File ▸ Refresh | Read the repository again |

### The context menu

Right-click an event for:

| Entry | Does |
|---|---|
| Diff | (check-ins) The diff of the check-in |
| Show branch NAME | (check-ins) The branch in the [Branches](branches.md) tab |
| Edit check-in… | (check-ins) See [Editing check-ins](#editing-check-ins) |
| Add tag… | (check-ins) See [Tags on check-ins](#tags-on-check-ins) |
| Cancel tag ▸ | (check-ins) Its own tags, to cancel one |
| Bisect ▸ Good, Bad, Skip | (check-ins, in a checkout) Mark it for a [bisect](#bisect) |
| Advanced ▸ Reparent… | (check-ins) See [Reparenting](#reparenting) |
| Advanced ▸ Switch checkout here without merging… | (check-ins, in a checkout) See [Switching without merging](#switching-without-merging) |
| Advanced ▸ Purge this check-in and its descendants…, Purge graveyard… | (check-ins) See [Purging](#purging) |
| Update checkout to this check-in… | (check-ins, in a checkout) `fossil update --nosync` to it, after its dry run is shown; uncommitted changes are merged into the new files |
| Merge into checkout…, Cherry-pick into checkout…, Back out in checkout… | (check-ins, in a checkout) The merge dialog of the [Branches](branches.md#update-and-merge) tab: its dry run and options first |
| Save as archive… | (check-ins) See [Archives](#archives) |
| Make public… | (private check-ins) See [Private check-ins](#private-check-ins) |
| Show ticket | (ticket changes) The ticket in the Tickets tab |
| Open in browser | The event's page on the server (`/info/HASH`) |
| Search user:NAME, Exclude user:NAME | Add the term to the search |
| Search branch:NAME, Search kind:KIND | Add the term to the search |
| Copy hash, Copy comment | To the clipboard |
| Show artifact | The event's artifact as Fossil stores it (the manifest of a check-in, the control artifact of a tag change, …) in a window |
| Save artifact… | The same, saved to a file, as `fossil artifact HASH FILE` |

The menu bar has **File** (with Pull… and Refresh), **Bisect** and
**Help** (Search syntax: this page at [Search syntax](#search-syntax), as
the help button by the search box).  Back and
Forward (Alt+Left, Alt+Right, or the mouse side buttons) go through the
searches, views and selected rows you have looked at.

## Views

The buttons under the search box choose which events are listed.  Each
shows how many events match the search in that view.

| View | Shows | Search term |
|---|---|---|
| **All** | Everything | none |
| **Last pull** | What the last pull from a server brought | `pull:1` |
| **Outgoing** | What a push would send: the events among the artifacts not pushed yet.  The files of unpushed check-ins are not events; the status line counts all unpushed artifacts | `is:unsent` |
| **Private** | Private check-ins and branches, which are never pushed (as `fossil unpublished` lists them).  In the other views they are in purple italics | `is:private` |

"Last pull" means the last pull over the network: Fossil records where each
artifact came from, and a pull from a local file has no address.  After
**File ▸ Pull…** the tab switches to this view by itself when something
new came from a server.

A view is a term of the search: a button puts its term in the search box
(in place of another view's), and typing the term selects the button.
Each button counts the events of the rest of the search.

## Search syntax

Type in the search box; the list follows a moment after you stop typing.
Return also searches and remembers the search in the box's drop-down
history (the last 30).

- A plain word matches a part of the comment (upper and lower case are the
  same).
- `key:value` matches by a field.
- All terms must match.
- `-` before a term excludes what it matches: `-user:@me`.
- `key:a,b` means a **or** b: `kind:ticket,wiki`.
- Quotes keep spaces: `"menu bar"`, `comment:"null merge"`.

| Term | Matches |
|---|---|
| `WORD`, `comment:TEXT` | A part of the comment |
| `user:NAME` | Who made it; `user:@me` is the repository's default user |
| `kind:KIND` | `ci` (or `check-in`, `checkin`), `ticket`, `tag`, `wiki`, `forum`, `technote` |
| `branch:NAME` | Check-ins on the branch; a pattern with `*`, `?` or `[...]` matches several; `branch:@current` is the checkout's branch |
| `ticket:ID` | The changes of the ticket and the check-ins whose comments mention it (a prefix of its id) |
| `hash:PREFIX` | The artifact whose hash starts so |
| `date:DATE` | `2026`, `2026-09`, `2026-09-23`; also `>=2026-09`, `<2026`, `>2026-09-01`, `<=2026-09`, and ranges `2026-01..2026-06` |
| `pull:N` | Brought by the last N pulls from a server |
| `in:X` | Check-ins in that release: X and its ancestors |
| `desc:X` | X and its descendants |
| `after:X`, `before:X` | Events after (before) the check-in X |
| `path:FILE`, `path:DIR`, `path:GLOB` | Check-ins that changed the file, a file in the directory, or a file matching the pattern |
| `is:unsent` | Not pushed yet |
| `is:private` | Private |
| `tag:NAME` | Check-ins with the tag, given to them or propagated to them (as `fossil tag find`); a pattern with `*` matches several |
| `is:leaf` | Check-ins without children |
| `is:open`, `is:closed` | Leaves still open, or closed (as `fossil leaves`, `fossil leaves -c`) |
| `is:merge` | Merges (more than one parent) |
| `is:current` | The checkout's check-in |

X is a tag, a branch name (its newest check-in), a hash prefix, or
`current`: the check-in the checkout is on.

A mistake in the search (an unknown key, a bad date) is shown in red in the
status line, and the list stays as it was.

### Examples

What others did to tickets since October 1:

```
kind:ticket date:>=2026-10-01 -user:@me
```

What the last pull brought to the 8.6 branch:

```
branch:core-8-6-branch pull:1
```

The check-ins of a release, without those of the release before it:

```
in:core-9-0-3 -in:core-9-0-2 kind:ci
```

Check-ins that touched the menu code, by two people:

```
path:generic/tkMenu.c user:dkf,jan.nijtmans
```

Everything that mentions a ticket:

```
ticket:4eef1fa86e
```

Merges on your branches in 2026:

```
is:merge user:@me date:2026
```

What happened after the checkout's check-in, on its branch:

```
after:current branch:@current
```

## Details

Below the list, the details of the selected event: its kind, date, user and
hash, its branch, whether it is not pushed yet or private, and its full
comment.  Then, by kind:

- **A check-in**: its tags (its own first, then inherited ones in grey;
  `name=value` for tags with a value); where it is in the history: its
  **Parent** (or Parents), what it was **Merged from**, what it was
  **Cherry-picked from** and what it **Backs out**, its **Child** (or
  Children), what it was **Merged into**, **Cherry-picked into** and
  **Backed out by**, each a link that shows that check-in (Back returns),
  and its **State** (a leaf, open or closed); **Describe**: the nearest tag
  before it and how many check-ins since (`TAG-N-HASH`, as `fossil
  describe`, also without a checkout; the hash as long as the `hash-digits`
  setting says), and the nearest tag matching a pattern (release tags) if
  that is another one; then its files, each marked
  added, changed or deleted.  Buttons: **Diff**, **Show branch**, **Open
  in browser**.
- **A ticket change**: the fields it set, as the change records them (a
  field written `+field` was appended to).  Buttons: **Show ticket**,
  **Open in browser**.
- **A tag change**: each tag it added, cancelled or propagated, with its
  value, and the check-in it is on.  Button: **Open in browser**.
- **Wiki, forum and technote edits**: the comment.  Button: **Open in
  browser**.

Open in browser needs the repository's remote URL (see [Remotes](repository.md#remotes)).

The second description of a check-in matches only some tags: the release
tags by default (`core-*`).  **File ▸ Describe from tags matching…** sets
another pattern (as `fossil describe --match`), or `*` to show only the
nearest tag; it is kept in `timeline.conf` (`describeMatch`, see
[Settings files](configuration.md#settings-files)).  The descriptions are
worked out again after each search, so they follow new tags.

## Editing check-ins

Right-click a check-in ▸ **Edit check-in…** changes what Fossil records
about it, as `fossil amend` does.  The dialog shows the check-in as it is:

| Field | Changes |
|---|---|
| Comment | The check-in comment (written to a file and passed with `-M`, so it can contain anything) |
| Do not check the comment | Skip Fossil's check of links and markup in the comment (`--no-verify-comment`) |
| Author | Who made it (`--author`) |
| Date (UTC) | When (`--date`): `YYYY-MM-DD HH:MM:SS`, optionally with `Z` or an offset `+HH:MM` |
| Branch | Moves this check-in and its descendants to another branch name: the branch is renamed from here on (`--branch`) |
| Colour | The background colour of this check-in in timelines (`--bgcolor`): `#rrggbb` or a colour name; **Choose…** opens a colour chooser |
| Branch colour | The colour of the branch from here on (`--branchcolor`) |
| Add tags | Tags to add, separated by spaces (`--tag`) |
| Cancel tags | A check box for each of its own tags (`--cancel`) |
| Close this leaf | Close the branch here (`--close`); only possible on a leaf that is not closed yet |
| Hide the branch from here on | `--hide` |

Only the fields you change become options of `fossil amend`; if nothing
changed, nothing happens.  Tag names cannot contain spaces, and names
starting with `wiki-`, `tkt-` or `event-` are Fossil's own.

**Apply…** first runs the command as a dry run and shows the command and
the control artifact Fossil would record.  **Apply** in that window makes
the change; **Cancel** leaves the repository as it was.  The change is a
new artifact in the local repository; it reaches the server with your next
push, made outside Tktaalik.

## Tags on check-ins

### Adding a tag

Right-click a check-in ▸ **Add tag…** (or **Add…** in the
[Tags](tags.md) tab):

| Field | Meaning |
|---|---|
| Check-in | A hash, a tag or a branch name (its newest check-in), or a date; filled in with the check-in you clicked |
| Tag | The name, without spaces |
| Value | An optional value |
| Propagate to the descendants | The tag goes on to all descendants, as a branch name does (`--propagate`) |
| Raw name | A property such as `bgcolor` or `closed` rather than a symbolic tag (`--raw`); without it Fossil adds the `sym-` prefix itself, so do not type it |

**Add…** shows the dry run (`fossil tag add … --dry-run`): the command and
what it would record.  **Apply** adds the tag.

### Cancelling a tag

Right-click a check-in ▸ **Cancel tag ▸** lists the check-in's own tags
with their values, propagating ones too (cancelled there, they end on the
descendants as well), and the propagating tags it inherited, as "*name*
(from here on)": cancelled on this check-in, they stop here and on its
descendants.  Choosing one shows the dry run of `fossil tag cancel`;
**Apply** cancels it.  Branch names and branch colours are not listed:
change those with [Edit check-in](#editing-check-ins) or in the
[Branches](branches.md) tab.

The details of a check-in list all its tags, and the tooltip of its Hash
cell shows its description, as `fossil describe` (also without a
checkout): the nearest tag before it and how many check-ins since (show
the Hash column first: right-click a heading).

### Switching without merging

Right-click a check-in ▸ **Advanced ▸ Switch checkout here without
merging…** runs `fossil checkout --keep`: the files of the checkout stay as
they are, only the version it is at changes, so where they differ from that
check-in they show as changes.  Fossil has no dry run for it and Undo does
not take it back; the confirmation says so.  Uncommitted changes stay
(`--force`).  The [Branches](branches.md#managing-branches) tab has the
same for the last check-in of a branch.

### Reparenting

Right-click a check-in ▸ **Advanced ▸ Reparent…** gives it other parents,
as `fossil reparent` does.  It is for experts: to patch up a history
damaged by shunning, or pieced together from separate repositories.  Enter
the parents' hashes, the primary parent first, then the merged ones.  The
dry run is shown before anything is changed.  Reparenting is a tag
(`parent`) on the check-in: cancelling that tag undoes it.

## Bisect

Bisecting finds the check-in that introduced a bug, by testing check-ins
between one known to be good and one known to be bad.  It works in a
checkout, with `fossil bisect`; without a checkout the Bisect menu and the
context menu's Bisect entries are disabled.

1. Update the checkout to a check-in where the bug is, and choose
   **Bisect ▸ Checkout is bad**.
2. Mark an older check-in without the bug: right-click it ▸ **Bisect ▸
   Good** (or update to it and choose **Bisect ▸ Checkout is good**).
3. Fossil updates the checkout to a check-in in between (with the
   auto-next option, which is on by default).  Build and test it, then mark
   it with **Checkout is good**, **Checkout is bad** or **Skip the
   checkout** (when it cannot be tested).
4. Repeat until Fossil names the first bad check-in.

The marked check-ins are coloured in the list (green good, red bad, grey
skipped), the checkout's check-in is bold, and the status line says how far
the bisect is: `bisect: 2 good, 1 bad, 14 in between`.

If the checkout has uncommitted changes, Tktaalik asks before a step that
updates it: Fossil merges the changes into the next check-in.

### The Bisect menu

| Entry | Does |
|---|---|
| Checkout is good, Checkout is bad, Skip the checkout | Mark the checkout (`bisect good/bad/skip`) |
| Next | Update the checkout to the next check-in to test |
| Undo | Undo the last mark |
| Reset… | Forget the bisect (asks first) |
| Status | The check-ins between good and bad (`bisect status`) |
| Log | The marks so far |
| Chart | The marks as a chart |
| Run a command… | Test automatically (below) |
| Next after each mark (auto-next) | Update to the next check-in after each mark |
| Primary parents only (direct-only) | Follow only primary parents, not merges |
| Linear scan (linear) | Test the check-ins one after the other, not by halving |
| After next, show ▸ | What to show after Next: chart, log, status or none |

The options are Fossil's (`fossil bisect options`), kept in the checkout.

### The Bisect window

Each bisect command shows its output in the Bisect window, with buttons
**Good**, **Bad**, **Skip**, **Next**, **Undo**, **Status**, **Log** and
**Chart**.  Status lists the check-ins between the innermost good and bad
ones; with **All** it lists them all, not shortened.

### Run a command

**Bisect ▸ Run a command…** runs `fossil bisect run COMMAND`: the command
is run in the checkout for each check-in to test, and its exit status marks
it: 0 good, 125 skip, anything else bad.  The output appears in the Bisect
window as it comes; **Stop** stops it (the step under way finishes).  It
needs the auto-next option (without it Fossil would test the same check-in
again and again): if it is off, Tktaalik offers to turn it on.  Uncommitted
changes are merged into every check-in tested: it asks first.

```
make -C unix && make -C unix test TESTFLAGS="-file menu.test"
```

## Archives

**Save as archive…** (check-ins; also in the [Branches](branches.md) and
[Tags](tags.md) tabs) saves the files of a check-in as an archive, as
`fossil zip`, `fossil tarball` or `fossil sqlar`:

| Field | Does |
|---|---|
| Format | ZIP (`.zip`), tarball (`.tar.gz`) or SQL archive (`.sqlar`) |
| Top folder | The folder everything is in (`--name`); the project name and the check-in by default |
| Only files | Globs, comma-separated (`--include`): `generic/*,doc/*.n` |
| Except files | Globs to leave out (`--exclude`) |

The window counts the files the archive will have as you type.
**Save…** asks where.  Only that file is written.

## Private check-ins

Private check-ins and branches are never pushed (the Private view, purple
italics).  **Make public…** (context menu of a private check-in; in
Branches, the branch menu of a private branch) runs `fossil publish` after
a confirmation that shows what would become public (its dry run,
`--test`): the check-ins (for a branch, all of them), their files and tags
become public in the local repository.  Nothing is pushed now: they go to
the server with the next push or sync.  It cannot be undone.

## Purging

In a checkout (Fossil purges check-ins only there), right-click a
check-in ▸ **Advanced ▸ Purge this check-in and its descendants…** (in
Branches: the branch menu ▸ Advanced ▸ Purge the branch…) runs `fossil
purge checkins`; not the check-in of the checkout: they leave the repository (the
timeline, branches, tags) and go to the graveyard.  The confirmation shows
the dry run (`--explain`): every artifact that would go.  Only the local
repository changes; check-ins pushed before stay on the server.  Fossil
warns that purging can leave a repository in an odd state: make a backup
(**Repository ▸ Back up repository…**) if in doubt.

**Purge graveyard…** (Advanced, and the Branches File menu) lists what was
purged, newest first, each purge with its artifacts (`fossil purge list
-l`): **Undo…** brings a purge back (`fossil purge undo`), **Obliterate…**
removes it for good (`fossil purge obliterate`), after a confirmation.

## Pull

**File ▸ Pull…** brings new artifacts from a remote into the local
repository, as `fossil pull`.  It never pushes and never syncs.

| Option | Meaning |
|---|---|
| Pull from | The remote: the default one first, then the named ones (see [Remotes](repository.md#remotes)); its URL is shown below.  Pulling from a named remote does not make it the default (`--once`) |
| Private branches too | Also private branches, if the server lets you (`--private`) |
| From all the remotes | Every remote in turn (`--all`) |
| IPv4 only | `--ipv4` |
| Verily | Make sure nothing is overlooked; slower (`--verily`) |
| Verbose output | More output (`-v`) |
| HTTP authentication | `user:password`, if the web server itself asks for it (`--httpauth`) |

**Pull** runs it in the background and shows Fossil's output in the
dialog; **Stop** stops it (also quitting Tktaalik does).  When it ends, the Timeline shows the [Last pull](#views) view if
something new came from a server (else All), and the other tabs read the
repository again when you open them.  Back returns to where you were.

If the pull brought a tag change that moved the check-in of the checkout
to another branch (`fossil amend --branch`, as reverting a merge may do),
the next commit or update would go there.  Tktaalik then says so, with
who moved it and when, and offers to update the checkout to the newest
check-in of the branch it was on (the Commit tab's
[Update](commit.md#updating), with its dry run).

Without a remote, Pull tells you to add one in
**Repository ▸ Remotes**.
