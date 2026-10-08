# Branches

The Branches tab lists the branches of the repository and shows, for each,
whether it is merged into the main branches.  Below the list are the
check-ins, the changed files and the tickets of the selected branch.

With a checkout, a branch or a single check-in can be checked out or merged
into it (always after a dry run).  Branches can be closed, reopened,
hidden, unhidden and created.  Merges are not committed here (the
[Commit](commit.md) tab does that), and nothing is pushed.

## The window

From top to bottom: the search box (see [Search syntax](#search-syntax)),
the views and two check boxes (see [Views](#views)), the list, the details
(see [Details](#details)), and the status line: how many branches are
shown, the checkout's branch and how many files it has changed, how many
artifacts are not pushed yet, and the repository file.

### Columns

| Column | What it shows |
|---|---|
| Branch | The name; ★ and bold for the checkout's branch |
| Updated | The time of the last check-in |
| Created | The time of the first check-in (hidden at first) |
| Check-ins | How many check-ins it has |
| Users | Who has check-ins on it (hidden at first) |
| Base | The branch it was made from |
| main, 9.0, 8.6, … | Its [merge state](#merge-state) into each target branch |
| Forks | ⚠ and the number of open leaves, if more than one |
| Tickets | Tickets whose ids appear in its check-in comments |
| CI | Whether a `core-*` tag (which the GitHub mirror of Tcl/Tk builds) is on its last check-in ✓ or only on an earlier one ◐ |
| State | closed, hidden, private (hidden at first) |
| Tip | The last check-in (hidden at first) |
| Last comment | The comment of the last check-in |

Closed and hidden branches are in grey.  Hover over a heading for what it
means, and over a merge, CI or Forks cell for its state in words.  Click a
heading to sort by it, drag it to move the column, and right-click a
heading to choose the columns.  The Branch column is always shown.

### Mouse and keys

| Action | Does |
|---|---|
| Click, Shift+click, Ctrl+click | Select one or several branches (closing and hiding work on all of them) |
| Double-click | The diff of the branch in the [diff viewer](diffs.md) |
| Right-click | The branch menu (also the **Branch** menu in the menu bar) |
| Ctrl+F | Go to the search box |
| Escape in the search box | Clear the search |
| F5, File ▸ Refresh | Read the repository again |

### The branch menu

| Entry | Does |
|---|---|
| Update checkout to NAME | See [Update and merge](#update-and-merge) (needs a checkout) |
| Merge into checkout… | See [Update and merge](#update-and-merge) (needs a checkout) |
| Diff of the branch | Everything the branch changed, from where it started |
| Diff against main | The branch's last check-in against the first target's (named after it) |
| Timeline in browser | The server's timeline of the branch |
| Close, Reopen, Hide, Unhide | See [Managing branches](#managing-branches) |
| New branch from here… | A new branch from its last check-in |
| Make public… | (private branches) All its check-ins public: `fossil publish`; see [Private check-ins](timeline.md#private-check-ins) |
| Common ancestor with NAME | The check-in from which both descend (the pivot of a merge, `fossil merge-base`): of the two branches selected, else with the first merge target; it can be shown in the Timeline, or diffed against either; **Ignore merges** follows only the first parents (`--ignore-merges`) |
| Save as archive… | Its last check-in as a ZIP, tarball or SQL archive; see [Archives](timeline.md#archives) |
| Export as bundle… | See [Bundles](#bundles) |
| Advanced ▸ Switch checkout to NAME without merging… | `fossil checkout --keep` to its last check-in: the files stay, only the version changes; see [Switching without merging](timeline.md#switching-without-merging) |
| Advanced ▸ Purge the branch… | `fossil purge checkins NAME`, after its dry run; see [Purging](timeline.md#purging) |
| Search base:NAME, Search user:NAME | Add the term to the search |
| Copy name, Copy last check-in | To the clipboard |

**File** has Merge targets… (see [Merge state](#merge-state)), Changes
between releases… (see [Changes between releases](#changes-between-releases))
the [bundles](#bundles): Import bundle…, Remove an imported bundle…, and
Purge graveyard… (see [Purging](timeline.md#purging)).
**Help ▸ Search syntax** (or the help button by the search box) opens this
page at [Search syntax](#search-syntax).
Back and Forward (Alt+Left, Alt+Right) go through the searches, views and
selected branches you have looked at.

## Views

| View | Shows | Search term |
|---|---|---|
| **Open** | The branches that are not closed | `is:open` |
| **Unmerged** | Open branches whose last check-in is not in the first target branch (usually main) | `is:open -merged:main` (the first target) |
| **Mine** | Open branches you (the repository's default user) have check-ins on | `is:open user:@me` |
| **Closed** | Closed branches | `is:closed` |
| **All** | All of them | none |

A view is a term of the search: a button puts its terms in the search box
(in place of those of the view shown), and typing them selects the button.
Each view shows how many branches it has with the rest of the search.

| Check box | Effect |
|---|---|
| Show hidden | Also hidden branches; without it they are shown only when the search asks for them with `is:hidden` |
| Private only | Only private branches, which are never pushed: the term `is:private` in the search (checking the box adds it, typing it checks the box) |

## Search syntax

Type in the search box; the list follows a moment after you stop typing.
Return also searches and remembers the search in the drop-down history.

- A plain word matches a part of the branch name **or** of any check-in
  comment on the branch.  A word with `*`, `?` or `[...]` is a pattern for
  the name.
- All terms must match; `-` before a term excludes; `key:a,b` means a or
  b; quotes keep spaces.

| Term | Matches |
|---|---|
| `name:PART`, `name:GLOB` | The name only |
| `comment:TEXT` | The check-in comments only |
| `user:NAME` | Someone with check-ins on it; `user:@me` is the default user |
| `base:BRANCH` | Made from that branch (a pattern is allowed) |
| `merged:TARGET` | Its last check-in is merged into the target: `merged:main`, `merged:9.0` or `merged:core-9-0-branch`; `-merged:main` is not (yet) merged.  The target counts as merged into itself |
| `is:open`, `is:closed` | Open or closed |
| `is:hidden`, `is:private` | Hidden, private |
| `is:current` | The checkout's branch |
| `is:forked` | More than one open leaf |
| `is:leaf` | Has an open leaf: a check-in without children on the branch, not closed |
| `has:tickets` | Mentions tickets |
| `has:ci` | A `core-*` tag is on one of its check-ins |
| `has:forks` | More than one open leaf |
| `ticket:ID` | Mentions the ticket (a prefix of its id) |
| `descendant:X` | Has check-ins descended from X (a hash prefix, a tag, or a branch: its last check-in), through merges too |
| `updated:DATE`, `created:DATE` | The last (first) check-in: `2026`, `2026-09`, `2026-09-23`, `>=2026-09`, `<2026`, `2026-01..2026-06` |
| `checkins:N` | `5`, `>5`, `<=2`, `2..10` |

`merged:@current` takes the branch of the checkout as the target, a merge
target or not: branches whose last check-in is an ancestor of its newest
check-in, through merges into other branches too (`-merged:@current`: the
others).  That is close to `fossil branch list -m`/`-M`, which count only
direct merges into the checkout's branch.  Otherwise
`merged:` takes only the merge targets (see [Merge state](#merge-state)); a
branch merged only earlier (◐) does not count as merged.

### Examples

My branches not merged into main yet:

```
user:@me -merged:main
```

Closed branches that mention a revert:

```
is:closed comment:revert
```

Merged into main this year, but not into 8.6: candidates to backport:

```
merged:main -merged:8.6 updated:2026
```

Open branches started since the 9.0.2 release:

```
descendant:core-9-0-2 is:open
```

Branches of one person with a lot of work, or forked:

```
user:jan.nijtmans checkins:>20
is:forked
```

Branches whose check-in comments mention a ticket:

```
ticket:4eef1fa86e
```

## Merge state

The target columns (main, 9.0, 8.6, …) show whether each branch is merged
into that branch:

| Mark | Meaning |
|---|---|
| ✓ | Its last check-in is merged into the target |
| ◐ | Only earlier check-ins are: it has check-ins after the last merge |
| (empty) | Not merged |

Merges through other branches count: what matters is whether the branch's
check-ins are ancestors of the target's last check-in.  A merge whose
changes were later backed out still counts ("null merges").

The targets are chosen in **File ▸ Merge targets…**: the branch names, one
per line, in the order of the columns.  The first one also decides the
Unmerged view.  They are kept for each repository.  If none are set, the
usual ones that the repository has open are used: main (or trunk),
core-9-0-branch, core-8-branch, core-8-6-branch.  A target named
`core-X-Y-branch` gets the short heading `X.Y`.

## Details

Above the details, a summary line: the name and state, the base branch and
when it started, how many check-ins by whom, the merge state into each
target, the CI tags, a warning if it has several open leaves, and the first
releases of each line whose check-ins contain the branch's last check-in
(release tags like `core-9-0-3`), or "not released".

Then three tabs:

| Tab | Shows |
|---|---|
| Check-ins | The check-ins of the branch, newest first (the newest 1000 of a big branch): date, hash, user, the branches each was merged into, and the comment; leaves in bold |
| Files | The files the branch changed, with lines added and deleted and a total (`fossil diff --numstat --branch`), read when the tab is opened |
| Tickets | The tickets mentioned in its comments: id, status, type, title; double-click opens the ticket in the [Tickets](tickets.md) tab |

In the Check-ins tab, double-click a check-in for its diff; right-click it
for:

| Entry | Does |
|---|---|
| Show in Timeline | The check-in in the [Timeline](timeline.md) |
| Diff of this check-in | Its diff |
| Open in browser | Its page on the server |
| Update checkout to this check-in… | See [Update and merge](#update-and-merge) |
| Merge into checkout… | Merge this check-in |
| Cherry-pick into checkout… | Only this check-in's changes |
| Back out in checkout… | Undo this check-in's changes |
| New branch from here… | A new branch from this check-in |
| Releases with this check-in | The first release of each line that contains it, and all of them |
| Save as archive… | The check-in as an archive; see [Archives](timeline.md#archives) |
| Show artifact | Its manifest as Fossil stores it, in a window |
| Branches descended from it | Searches `descendant:HASH` |
| Copy check-in | Its hash to the clipboard |

## Update and merge

These change only the files of the checkout; they need one (open it with
File ▸ Open checkout…).  Each first runs Fossil's dry run (`-n`) and shows
it; only the button in that window does it.  Neither pulls first
(`--nosync`).

- **Update checkout to NAME** (or to a check-in) updates the checkout to
  the branch's last check-in, as `fossil update`.  If the checkout has
  uncommitted changes, they are merged into the new files and can
  conflict; the dialog warns about it.
- **Merge into checkout…** merges the branch (or a check-in) into the
  checkout, as `fossil merge`.  Its window shows the dry run with what is
  merged from, the baseline and the pivot (`-n -v`), and the options:
  **Integrate** (a branch: close it with the commit, `--integrate`),
  **Keep the merge files of conflicts** (`-K`), **Force** (`-f`, even if
  there is nothing to merge), **Baseline** (merge only the changes since
  that check-in, `--baseline`) and **Binary files** (globs, `--binary`).
  **Dry run again** shows the dry run with the options changed; the merge
  button runs it with them (after a dry run of the same options).
- **Cherry-pick into checkout…** and **Back out in checkout…** (check-in
  menu) apply or undo one check-in's changes (`--cherrypick`,
  `--backout`).

After a merge, Tktaalik offers to open the [Commit](commit.md) tab, where
you review and commit it.  Nothing is committed here.

## Managing branches

These write into the local repository, as the default user, after a
confirmation.  They are refused while Fossil's autosync setting is on
(Fossil would push the change; turn it off with `fossil settings autosync
off`, or set it to `pullonly`), and without a default user.  Nothing is
pushed.

- **Close**, **Reopen**, **Hide**, **Unhide** work on all the selected
  branches that can be (`fossil branch close`, …).  The confirmation shows
  Fossil's dry run: the control artifact it would add (`-n -v`).  A closed branch is no longer in the Open view; a hidden one is
  shown only with Show hidden.
- **New branch from here…** (branch menu: from its last check-in;
  check-in menu: from that check-in) asks for the name (no spaces), whether
  it is private (never synced), and its colour in timelines (Choose…, or
  Automatic).  **Create**, then a confirmation, runs `fossil branch new`.
  The new branch has no check-ins of its own until you commit to it.

To rename a branch from a check-in on, or to close a single leaf, use
[Edit check-in](timeline.md#editing-check-ins) in the Timeline.

## Backports

**Backport to another checkout…** (branch menu) brings the branch into
another checkout of the same repository — the one you keep on
`core-8-6-branch` while this one is on main — without touching the
checkout shown (Fossil's way: a checkout per line of work).  It lists the
other checkouts that are at the tip of a merge target (with how many files
they have changed); **Other checkout** takes any folder that is a checkout
of this repository.  The one preselected is on a target the branch is not
merged into yet.  How:

- **Cherry-pick its check-ins** (`fossil merge --cherrypick`), oldest
  first: the default when that checkout is on another branch than the one
  the branch was made from, as for a fix made on main and backported to
  8.6, where merging would bring the rest of main too.  Check-ins that
  merged something into the branch are listed unchecked: cherry-picked,
  what they merged would come too;
- **Merge the branch** (`fossil merge`, with the options and the dry run of
  [Update and merge](#update-and-merge)): the default when that checkout
  is on the branch it was made from.

**Backport…** shows Fossil's dry runs and asks (each cherry-pick's dry run
is on the files as they are, before the others); then the files of that
checkout change, nothing is committed, and you are asked whether to show
that checkout, to review and commit there.

## Finishing a branch

**Finish branch…** (branch menu, or the **Finish…** button by the branch's
details; disabled when there is nothing to do: for main and the other
merge targets, and for a closed branch with no CI tags or tickets it fixes
left) does in one go what is left after a branch
is merged, as in the Tcl/Tk workflow (TIP 710: a branch per fix, reviewed,
tested by the CI, merged).  It lists, each with a check box:

- the CI tags (`core-…`, not release tags like `core-9-0-2`) given to the
  branch's check-ins, to cancel (`fossil tag cancel`);
- the open tickets the branch's comments link to, to close — as **Fixed**
  for a bug, **Accepted** for other types, recording you as the closer.
  Those named as fixed ("Fix [id]…") are checked; those only mentioned are
  not;
- closing the branch itself (`fossil branch close`).

If the branch's last check-in is not merged into the first merge target
yet, it says so in red (it does not stop you).  **Finish** shows Fossil's
dry runs of the tag and branch changes and the ticket changes, and asks
once; then they are written in this order, stopping at the first that
fails.  Like the other changes here, it is refused while autosync is on,
and nothing is pushed.

## Bundles

A bundle is a file with check-ins, to give to someone without pushing
(`fossil bundle`).

- **Export as bundle…** (branch menu) writes the check-ins of the branch,
  of a range (From, To), or one check-in to a file you choose; **Self-
  contained** makes it larger but importable where the artifacts it
  builds on are missing (`--standalone`).  The repository is not changed.
- **File ▸ Import bundle…** shows what the bundle has (`fossil bundle ls`)
  and imports it: private (never pushed), unless **Make them public too**
  is checked (`--publish`).  [Make public…](timeline.md#private-check-ins)
  can publish them later.  A bundle of another project is refused, unless
  **Even from another project** is checked (`--force`, asked again).
- **File ▸ Remove an imported bundle…** removes from the repository what a
  bundle brought (`fossil bundle purge`), after a confirmation that shows
  its dry run.  The artifacts do not go to the purge graveyard: importing
  the bundle again brings them back, so keep the file.

(`fossil bundle extend` is not offered: Fossil 2.26 does not implement it.)

## Changes between releases

**File ▸ Changes between releases…** compares two releases: the check-ins
tagged as Tcl/Tk tags them (`core-9-0-3` is 9.0.3, `core-8-7-a1` is 8.7a1).
Choose **From** and **To**: at first the newest release and the one before
it on the same line.

- **Check-ins** shows the check-ins in To but not in From in the
  [Timeline](timeline.md), with the search
  `in:core-9-0-3 -in:core-9-0-2 kind:ci`.
- **Diff** shows the difference between the two in the
  [diff viewer](diffs.md).

Repositories without such tags have no releases to compare; the Timeline
search `in:TAG -in:OTHER` works with any tags.
