# Tktaalik manual

Tktaalik shows a Fossil repository in one window: its history, tickets,
branches, tags, files, wiki and forum, the changes in your checkout, and
the repository's settings and users.  It runs the `fossil` program for
everything it shows or changes, so the repository stays an ordinary Fossil
repository that you can keep using from the command line and the web
interface at the same time.

The name comes from *Tiktaalik*, the fossil fish that came out of the
water on its fins: Fossil, brought out of the command line.

## Getting started

You need Tcl/Tk 8.6 or 9.0 and the `fossil` executable on your `PATH`.
Start Tktaalik from a checkout:

```sh
cd ~/src/tk
~/tcltk/tktaalik/tktaalik
```

It opens the checkout of the current directory.  Outside a checkout it
opens the repository or checkout you used last, and the first time it asks
for a repository file.  See [Running Tktaalik](configuration.md#running-tktaalik)
for the other ways to start it, and the desktop launcher.

Then:

- The **Tickets** tab opens first (later: the tab you used last).  Type a
  search such as `is:open type:bug crash` and press Return; see
  [Tickets](tickets.md).
- **Ctrl+1** … **Ctrl+9** and **Ctrl+0** switch to the ten tabs.
- **Ctrl+G** goes to anything with a name: a hash, a ticket id, a tag, a
  branch ([Go to](goto.md)).
- **Ctrl+Shift+F** searches everything at once ([Search](search.md)).
- **F1** opens this manual at the page about what you are looking at.
- **Alt+Left** and **Alt+Right** (or the mouse's side buttons) go back and
  forward.

## The window

The window has a menu bar, a row of tabs, and the tab shown.  The window
title names the tab and the project, for example "Wiki — Tk Source Code".

| Tab | What it shows |
|---|---|
| [Timeline](timeline.md) | everything that happened: check-ins, ticket changes, tag changes, wiki, forum and technote edits; bisect; pull |
| [Tickets](tickets.md) | a search over the tickets, their details, comments, attachments and history; new tickets and edits; ticket reports |
| [Branches](branches.md) | all branches with their merge state; update, merge, close, new branch |
| [Tags](tags.md) | the tags of check-ins and their history; adding and cancelling tags |
| [Files](files.md) | the files at any version, a file's history, blame and content |
| [Commit](commit.md) | the changes in the checkout: diffs, commit, revert, undo, patches |
| [Stash](stash.md) | the stashes of the checkout |
| [Wiki](wiki.md) | wiki pages, technotes, their versions; editing and attachments |
| [Forum](forum.md) | the threads of the forum and their posts |
| [Search](search.md) | full-text search over check-ins, tickets, wiki, technotes and forum |

The **Commit** and **Stash** tabs need a checkout.  When you open a
repository file without a checkout they are greyed out, and so are the
actions that change a checkout (update, merge, bisect, and the like).

The menu bar shows the menus of the tab shown, and some that are always
there.  In every tab:

- **File** — open a checkout or a repository, Back, Forward, Go to, Quit;
- **View** — right after File: the tabs Timeline, Tickets, Branches, Tags,
  Files, Wiki, Forum and Search, with their keys; the tab shown is marked;
- then the tab's own menus (Ticket, Branch, Bisect, Commit…);
- **Checkout** — the tabs of the checkout, Commit and Stash (greyed out
  without a checkout);
- **Repository**, then **Help** — the manual (F1), the tab's own help,
  and **About Tktaalik**: the version, the Tcl/Tk and Fossil it runs with,
  the license and the project's page.

The **Repository** menu opens windows that stay open beside the tabs and
follow the repository shown (see [Repository windows](repository.md)):

- **Information** — what `fossil info` says, and how much the repository
  holds;
- **Settings** — Fossil's settings, where each value comes from, changing
  them;
- **Users** — the users and their capabilities, the default user;
- **Remotes** — the remote repositories pull and push use;
- **Unversioned files** — the files Fossil keeps outside the check-ins.

A tab is built the first time it is shown.  When you come back to a tab
after the repository has changed (a commit, a pull, a change made from the
command line), the tab reads the repository again; **F5** (File ▸ Refresh)
does it at any time.

Most lists are tables: click a column heading to sort by it, drag a
heading to move the column, right-click a heading to choose the columns
(see [Columns and sorting](configuration.md#columns-and-sorting)).
Right-click a row for what you can do with it.  Hover over icons and
headings for tooltips.

## Opening a repository

- **File ▸ Open checkout…** opens a directory that is a Fossil checkout:
  its repository, with the Commit and Stash tabs.
- **File ▸ Open repository…** (**Ctrl+O**) opens a repository file
  (`*.fossil`) without a checkout.
- **File ▸ Known repositories** and **Known checkouts** list the
  repositories and checkouts this computer knows (`fossil all list`), to
  open one; **Clone repository…** and **New repository…** make
  one, and **Checkout ▸ New checkout…** a checkout of the one shown (see
  [Repository operations](repository.md#repository-operations)).

All tabs switch to the new repository, and so do the open windows of the
Repository menu.  Back and Forward start afresh: they go to places of the
repository shown.  Tktaalik remembers the repository (or checkout), the tab
and the window size for the next start.

A directory that is not a checkout, a file that is not a repository, or one
that Fossil cannot read is refused with a message; the repository shown
stays.

## Back and Forward

Tktaalik remembers where you have been, like a web browser: the tab, and in
the tab what it showed — the search or filter, the view, the selected item,
the version, how far a page was scrolled.

- **Alt+Left** or File ▸ **Back**, the mouse's back side button, or the
  keyboard's Back key go back.
- **Alt+Right** or File ▸ **Forward**, the forward side button, or the
  Forward key go forward again.

A new place is recorded when you switch tabs, follow a link, open
something from another tab (a ticket from the Timeline, a check-in from Go
to, a search result), run a search with Return, or change a view or
filter.  Typing in a search box that searches as you type is one place, not
one per key.  Going back and then somewhere new drops the places ahead, as
in a browser.  The last 100 places are kept; opening another repository
forgets them.

## What Tktaalik changes

Most of Tktaalik only reads.  When it does change something, it is because
you asked, and it asks first: a confirmation names what will change.  Where
Fossil can run a command as a dry run (`-n`, `--dry-run`), the
confirmation shows what Fossil would do or record before anything is done.

**It never pushes or syncs.**  Everything goes into the local repository or
the checkout; sending it to a server stays a separate step for you
(`fossil push` or `fossil sync`).  Commits, updates, merges and new branches
are run with `--nosync`, so they do not sync even when Fossil's `autosync`
setting is on.  **Pull** (Timeline, File ▸ Pull…) is the one command that
talks to a server, and it only fetches.

What can be changed, and where:

| Change | Where | Kept in |
|---|---|---|
| commits, adding, removing, renaming files | [Commit](commit.md) | repository and checkout |
| update, merge, cherry-pick, back out, revert, clean | [Commit](commit.md), [Branches](branches.md) | checkout |
| stashes | [Stash](stash.md) | checkout |
| bisect | [Timeline](timeline.md#bisect) | checkout |
| new tickets, ticket edits and comments | [Tickets](tickets.md) | repository |
| wiki pages, technotes, attachments | [Wiki](wiki.md) | repository |
| editing check-ins, tags, reparenting | [Timeline](timeline.md), [Tags](tags.md) | repository |
| new branches, closing, hiding | [Branches](branches.md) | repository |
| settings | [Settings](repository.md#settings) | repository, or `~/.fossil` for global ones |
| users, the default user | [Users](repository.md#users) | repository |
| remotes, saved passwords | [Remotes](repository.md#remotes) | repository |
| unversioned files | [Unversioned files](repository.md#unversioned-files) | repository |
| pulling from a remote | [Timeline](timeline.md#pull) | repository |

Changes to the repository are recorded as the repository's **default user**
(see [Users](repository.md#users)).  The Tickets and Wiki tabs refuse to
write without one, rather than record a change under a name Fossil makes
up.

What can be taken back:

- Changes to the checkout — update, merge, revert, stash apply, clean —
  can be undone with **Undo** in the Commit tab (Fossil's `undo`, one step),
  and redone with **Redo**.
- What is recorded in the repository — a check-in, a ticket change, a tag, a
  wiki edit — stays: Fossil's history only grows.  A later change can
  correct it (cancel a tag, edit a check-in's comment, revert a page to an
  earlier version), but the earlier one remains in the history.
- Unversioned files have no history: a removed or replaced one is gone.
- Users cannot be deleted in Fossil; take away their capabilities instead.

Tktaalik also writes its own settings files (see
[Settings files](configuration.md#settings-files)); they hold nothing of the
repository.

## Contents

- [Tktaalik manual](index.md) — this page
- [Timeline](timeline.md) — the history, editing check-ins, bisect, pull
- [Tickets](tickets.md) — searching, reading and writing tickets, reports
- [Branches](branches.md) — branches, merge state, update and merge
- [Tags](tags.md) — tags and their history
- [Files](files.md) — files at any version, history, blame
- [Commit](commit.md) — the checkout's changes and committing them
- [Stash](stash.md) — stashes
- [Wiki](wiki.md) — wiki pages and technotes
- [Forum](forum.md) — forum threads and posts
- [Search](search.md) — full-text search over everything
- [Repository windows](repository.md) — information, settings, users,
  remotes, unversioned files
- [Go to](goto.md) — going to a hash, ticket, tag or branch
- [Diffs](diffs.md) — the diff window
- [Keys and mouse](keys.md) — all keys
- [Settings files and columns](configuration.md) — Tktaalik's own
  settings, tables, running it
