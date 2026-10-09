# Settings files and columns

## Settings files

Tktaalik keeps its own settings — not the repository's — in
`~/.config/tktaalik/`, or `$XDG_CONFIG_HOME/tktaalik/` if that variable is
set.  They are written when you quit (File ▸ Quit, Ctrl+Q, or closing the
window), one file for the application and one for each tab that has
something to remember:

| File | What it keeps |
|---|---|
| `tktaalik.conf` | the repository or checkout used last, the tab, the window's size and place |
| `timeline.conf` | the search, the earlier searches, the view, the columns |
| `tickets.conf` | the search, the saved searches, the columns |
| `branches.conf` | the search, the earlier searches, the view, "show hidden", the columns, the merge targets of each repository |
| `tags.conf` | the filter, which kinds of tags are shown, the columns |
| `stash.conf` | the search, the earlier searches, the columns, where **Go back** returns to for each checkout |
| `wiki.conf` | the view, the filter, "show deleted", the columns |
| `forum.conf` | the filter, the columns |
| `search.conf` | the kinds searched, the earlier searches |

(Before, the application's settings were in `~/.config/tktaalik.conf`;
that file is still read if the new one does not exist yet.)

Each file is a Tcl dict: one key and its value per line, nested values
indented.  They can be edited by hand while Tktaalik is not running (it
would write its own settings over them when it quits).  For example
`tickets.conf`:

```tcl
query {is:open type:patch}
table {
    shown {type status priority subsystem}
    order {title type status priority subsystem}
    sort {priority desc}
}
saved {
    Mine involves:@me
    {Open bugs} {is:open type:bug}
}
```

A file that cannot be read is ignored (the defaults are used).  Deleting a
file resets that tab.

Fossil's own settings — of the repository, and the global ones in
`~/.fossil` — are changed in the [Settings](repository.md#settings) window,
not here.

## Columns and sorting

The lists of the Timeline, Tickets, Branches, Tags, Stash, Wiki and Forum
tabs, and of the Users and Settings windows, are tables whose columns you
can arrange.  In the tabs, the arrangement is saved.

- **Sort:** click a column heading to sort the rows by it; click it again
  to reverse the order.  The heading shows ▲ or ▼.  Dates sort as dates and
  numbers as numbers.
- **Move:** drag a heading sideways; a mark shows where the column will go.
  A click without dragging still sorts.
- **Choose:** right-click a heading.  A pop-up lists the columns with a
  check box each: check or uncheck them and the table changes at once (the
  pop-up stays open).  A column checked appears after the column whose
  heading was right-clicked.  The columns fill the window: the wide one
  (such as a comment or a title) gives up or takes the space, down to a
  readable width; if that is not enough, the table scrolls to show the new
  column.  Some columns, such as a ticket's title, are always
  shown.  Below the check boxes are "Sort by COLUMN, ascending" and
  "descending" for the column right-clicked, and for the Tickets' Status
  column also by the resolution.  **Default columns** goes back to the columns and order
  the table started with.  Escape or a click outside closes the pop-up.
- **Tooltips:** some columns show icons instead of words — the kind in the
  Timeline, the status, priority and severity of tickets: their headings
  are icons too.  Hover over an icon heading or cell for its name or value.
  (With Tk 8.6, which cannot show images in table cells, these cells show
  emoji instead.)

On macOS, Control-click opens the pop-up too.

## Running Tktaalik

Requirements:

- Tcl/Tk 8.6 or 9.0 (the `wish` program);
- the `fossil` executable on the `PATH`, or the one `FOSSIL` names (see
  [Environment variables](#environment-variables)); a recent version: the
  full-text search uses Fossil's own search functions;
- for opening links in the web browser: `xdg-open` on Linux and other
  Unix desktops (Windows and macOS have their own).

Nothing needs to be built or installed: run the `tktaalik` script from its
directory, with `wish` (it starts with `#!/usr/bin/env wish`):

```sh
./tktaalik                     # the checkout in the current directory,
                               # else the repository used last
./tktaalik ~/src/tk            # a checkout
./tktaalik ~/src/tk.fossil     # a repository file
./tktaalik ~/src/tk 'is:open type:bug'
                               # and in the Tickets tab, this search
wish9.0 tktaalik ~/src/tk      # with a particular Tk
```

On Windows, start it with Wish: `wish90 tktaalik C:\src\tk` (or a
shortcut, see [In the application menu](#in-the-application-menu)).
Git for Windows provides `patch.exe` for applying ticket patches, and
`curl.exe` comes with Windows 11.

Without an argument, and outside a checkout, it opens the repository or
checkout used last; the first time it asks for a repository file.  If what
it should open cannot be opened, it says why and asks.  It starts on the
tab used last (the Tickets tab the first time, or if the last one needs a
checkout and there is none).

### Environment variables

| Variable | What it does |
|---|---|
| `FOSSIL` | The Fossil to run: a path, or a name on the `PATH` (default `fossil`).  For trying another version: `FOSSIL=~/src/fossil-trunk/fossil ./tktaalik`.  The tests (`tests/run.sh`) use it too, for everything they run |
| `WISH` | The Tk shells `tests/run.sh` and `tests/smoke.sh` run with, one or more (default `wish8.6 wish9.0`): `WISH=wish9.0 tests/run.sh`.  Tktaalik itself runs with the `wish` on the `PATH`, or the one it is started with (`wish9.0 tktaalik`); `install.sh --wish` chooses it for an installed copy |

It also reads the usual ones: `XDG_CONFIG_HOME` (else `HOME`) for where
its settings go, `FOSSIL_HOME` to find Fossil's global settings as Fossil
does, and `TMPDIR` (or `TEMP`, `TMP`) for temporary files.  Fossil, run by
Tktaalik, reads its own (`FOSSIL_USER`, `FOSSIL_HOME`, …) as usual.

### Installed

`install.sh` (in the top directory) installs a copy: the application in
`PREFIX/share/tktaalik`, the command `PREFIX/bin/tktaalik`, and the
launcher and icon of the application menu.  PREFIX is `~/.local` (for root
`/usr/local`) unless given with `--prefix`; `--wish` chooses the Tk shell
(`wish` by default), `--uninstall` removes it all again, and `--destdir`
is for building packages.  Run it again after an update: it replaces the
old copy.

### In the application menu

On Linux and other desktops with application menus,
`tools/install-desktop.sh` adds Tktaalik, running from this directory
without installing it, to the menu of the current user:
a launcher (`~/.local/share/applications/tktaalik.desktop`, running the
`tktaalik` of this directory) and its icon in several sizes.
`tools/install-desktop.sh --uninstall` removes them.  The launcher can
also be given a checkout or a repository file to open.

On Windows, make a shortcut to Wish (`wish90.exe`, `wish86t.exe`, …) with
the path of `tktaalik` as its argument, and choose `icons\tktaalik.ico` as
its icon.  The window sets its own icon on every system.

Tktaalik runs `fossil` in the checkout's directory, and changes its current
directory there, so relative file names mean the same as in a shell in the
checkout.
