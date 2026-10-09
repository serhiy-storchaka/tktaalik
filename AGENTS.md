# Notes for coding agents

Tktaalik is a Tk desktop application for Fossil repositories (see
README.md for what it does, `docs/` for how).  It is plain Tcl/Tk: no build step, no
dependencies beyond Tcl/Tk and the `fossil` executable.

## Layout

- `tktaalik`: the application: the window, the tabs, menus, shortcuts,
  settings.  Sourcing it with `::tktaalik_test` set does not start it.
- `lib/tk*.tcl`: one file per tab (`tktimeline`, `tktsearch` for Tickets,
  `tkbranches`, `tktags`, `tkfiles`, `tkcommit`, `tkstash`, `tkwiki`,
  `tkforum`, `tkfulltext` for Search), each in its own namespace with `build` (called when the tab is first shown),
  `setRepository` and `activate` procs, and `saveConfig` if the tab keeps
  settings (called on quit); `here` and `goTo` for Back and Forward
  (`tktaalik::location`, `tktaalik::navigate`).
- `lib/tkinfo.tcl`, `lib/tksettings.tcl`, `lib/tkusers.tcl`,
  `lib/tkremotes.tcl`, `lib/tkuv.tcl`: the windows of the Repository menu (listed in
  `tktaalik::dialogs`): `window` opens one (made by `tktaalik::dialogWindow`
  the first time), `setRepository` follows the repository shown.
- `lib/tablecols.tcl`: sortable, movable, hideable `ttk::treeview` columns
  with heading and cell tooltips; use it for any new table.
- `lib/diffview.tcl`, `lib/htmltext.tcl` (HTML into a text widget, for
  rendered ticket comments), `lib/searchterms.tcl` (the search syntax),
  `lib/ticketquery.tcl`, `lib/ticketwrite.tcl` and `lib/ticketreports.tcl`
  (tickets), the parts of the large tabs (sourced at the end of the tab's
  file, in its namespace): `lib/ticketdialogs.tcl`, `lib/ticketdetails.tcl`,
  `lib/ticketattach.tcl` (Tickets), `lib/branchops.tcl` (Branches),
  `lib/bisect.tcl`, `lib/pull.tcl` (Timeline),
  `lib/goto.tcl` (Go to: what a hash or name is, and the tab for it),
  `lib/formattext.tcl` (a text in a chosen format with its preview: use it
  wherever text can be written in more than one format),
  `lib/tagwrite.tcl` (tag, amend and reparent dialogs: `tagwrite::apply`
  runs the dry run, confirms, then runs), `lib/commitops.tcl` and
  `lib/diffopts.tcl` (the Commit tab's operations and diff options),
  `lib/config.tcl` (settings files),
  `lib/web.tcl` (a server's web forms and single sync requests through
  curl, for what has no command: forum posts),
  `lib/icons.tcl` (icons and tooltips).
- `lib/fossil.tcl` and `lib/ui.tcl`: the layer every window uses.  New
  code runs Fossil only through `fossil::` (`run ?-dir? ?-input?`,
  `runIn`, `start`/`stop`/`stopAll` for the background, `runWindow` for a
  long command with its output shown, `valueProblem`, `argOk`, `opt`,
  `mask`, `autosync`, `urlquery`, `urlDecode`; no `exec fossil`, `cd` or
  `open |fossil` of its own) and makes its dialogs only through `ui::`
  (`confirm`, `ask`, `askCancel`, `errorBox`, `infoBox`, `copy`, `openServer`, `dialog`,
  `buttons`, `form` with `-preview` and `-help`, `later`, `setText`,
  `textWindow`, `busy` and `busyHold`/`busyRelease` while waiting; no
  `tk_messageBox`, `clipboard`, modal loop or `. configure -cursor watch`
  of its own).  The API is listed at the top of each file.  The tabs' short
  procs that call it with their own context (`inCheckout` with the tab's
  checkout, `sql` with its repository, `openUrl`, a `confirm` with the
  tab's title) are fine; a proc that only passes its arguments on is not:
  call the layer.
- `icons/`: PNG icons in 16, 24 and 32 pixels (the application icon up to
  256), drawn by `tools/make-icons.py` (Pillow).  Change the script and
  regenerate; do not edit the PNGs by hand.
- `install.sh`: installs a copy (`PREFIX/share/tktaalik`, the command
  `PREFIX/bin/tktaalik`, the menu launcher and icons); a new file the
  application reads at run time must be copied there too (tested by
  `tests/install.tcl`).
- `tools/`: the icon generator and the desktop launcher.

## Rules

- **Tk 8.6 and 9.0 both.**  Every change must work on both; test both.
  Where they differ, branch on `package vsatisfies [package provide Tk] 9`
  (examples: images in table cells are Tk 9 only, Tk 8.6 shows emoji; the
  mouse side buttons are bound differently, see `tktaalik::sideButtons`).
- **ASCII-only sources.**  Write non-ASCII characters as \u escapes
  (\u00b7); Tcl 8.6 on Windows reads sources in the system code page.
  Characters beyond the BMP go through `tktsearch::emoji`.  Escapes are not
  processed in braced text: help texts in braces go through
  `subst -nocommands -novariables` when shown.  Check with
  `grep -nP '[^\x00-\x7F]' tktaalik lib/*.tcl`.
- **Never write to the repository behind the user's back.**  Everything that
  changes a repository or checkout is confirmed first, and nothing syncs:
  `--nosync` on commit, update, merge, branch commands (merge and branch
  through `fossil::nosync`: Fossil 2.25 and older refuse it there); refuse
  while autosync is on.  Pushing is the user's step.
- **Tcl 9 namespaces.**  Refer to namespace variables as `::ns::var` or
  through `variable`; relative names resolve differently in Tcl 9
  (`info commands icons::x` inside another namespace finds nothing: use
  `::icons::x`).  Do not name procs after core commands (`open`, `load`,
  `update`, `read`, `source`, `info`, `error`, `text`, `apply`, `place`):
  inside the namespace they shadow the command, also in trace and binding
  scripts that run there.  Write `::apply` in such scripts.
- **`text insert` takes text and tags in pairs**: pass `""` for a chunk
  without tags, or the next chunk becomes a tag list.
- **Settings** live in `config::path NAME` (`~/.config/tktaalik/NAME.conf`,
  or under `$XDG_CONFIG_HOME`), a Tcl dict with one key per line written by
  `config::put`.  Keep old keys readable when changing the format.
- **Match the surrounding code**: comments in sentences that say why, not
  what; namespaced procs; no new dependencies.
- **Keep the manual (`docs/`) in step** with visible changes (tabs, keys,
  search terms, dialogs, options).  README.md is only a general overview
  (what the application is, requirements, running, where the manual is),
  with no details of the interface: they go into the manual.  The manual
  is for users, one page per tab or topic; F1 opens it through
  `help::contexts` in `lib/helpview.tcl` (a widget path prefix ->
  `page#anchor`; an anchor is the heading lowercased, other characters
  runs as "-").  A new dialog or window gets an entry there and a section
  to point at; `tests/help.tcl` checks that every page, required section,
  link and F1 target exists.
- **Fossil's options**: a feature that runs a Fossil command should offer
  what its options do where that makes sense in a window, and say why not
  otherwise.  Anything that writes asks first, with Fossil's dry run (`-n`)
  in the question where the command has one; nothing is ever pushed or
  synced.

## Testing

The tests are in `tests/`, one script per area, run under Xvfb with each
Tk in `$WISH` (default `wish8.6 wish9.0`):

    TKTAALIK_REPO=~/src/tk.fossil tests/run.sh [-j N] [NAME...]

They run N at a time (default: the processors, at most 8), each with its
own X display, directory and scratch copy; the results come in order at
the end, then the slowest tests with their times.  The whole suite takes a
few minutes.  Keep tests fast: never clone or rebuild the Tk repository in
a test (a clone takes a minute: clone a small repository made in the
test), avoid queries that join every comment with every check-in, and
let a stopped command take its children with it (`fossil::kill`).

`TKTAALIK_REPO` is a copy of the Tk repository: the tests check its
tickets, branches and comments, and only read it.  The tests that write
(Settings, Stash, applying attachments) get a scratch copy made by
`tests/scratch.sh`, and every test has its own `FOSSIL_HOME`.  Optional:
`TKTAALIK_REPO2` (a repository with another ticket schema),
`TKTAALIK_FORUM` (a copy of the Fossil forum, for `forum`) and the XTEST
helper `tests/xbutton.c`, which `run.sh` compiles if it can.  See
`tests/common.tcl`.  `FOSSIL` runs them with another Fossil (the
application uses it, and `run.sh` puts it first on the `PATH` for the
tests): check a change with an old and a new Fossil too
(docs/configuration.md, Environment variables).

- `tests/smoke.sh REPOSITORY...` opens every tab and window on any
  repositories (only read) and fails on an error; worth running on a few
  unlike ones (old ticket schemas, many tags, Fossil's own repository).
- A new test sources `common.tcl` and uses `check LABEL CONDITION` and
  `done`; a line `need scratch` makes `run.sh` give it a scratch copy (and
  skips it without one).  Settings files of every namespace with a
  `configFile` go to the test's temporary directory.  The test files
  are UTF-8 (`run.sh` runs them with `-encoding utf-8`).
- Use the kit of `common.tcl` (listed at its end), not copies of your own:
  the message boxes, file dialogs and browser are faked for every test
  (answers set with `::answer`/`::answers`, what was shown in `::boxes`,
  `::boxArgs`, `::browsed`); `start TAB ?PATH? ?SIZE?` opens the
  application; `waitUntil COND` instead of a loop of `after`/`vwait` (it
  fails with a message instead of hanging); `whenOpen W SCRIPT` instead of
  `after N SCRIPT` to answer a modal dialog; `sql`, `labels`, `fossilIn`.
  Define your own only for something else.
- Never run Tk tests on the user's display: their mouse and keyboard
  disturb them, and synthetic input on a real (Xwayland) display can
  trigger system prompts.  `run.sh` uses `xvfb-run`.
- Read real repositories only with read-only commands (`fossil sql
  --readonly`, `fossil cat`, `fossil diff`).  Anything that writes is
  tested on a scratch copy.
- `event generate` is not always the same as real input (the mouse side
  buttons in Tk 9 are an example); for input handling, test with real
  events (XTEST on Xvfb) as well.
- Quirks met so far: `fossil sql` reports an SQL error on its output and
  exits 0; since Fossil 2.28 `-q` is the global `--quiet` (use long
  options: `--quote`, not `-q`, for `fossil ticket`), `fossil sql -R` has no
  search functions (`fossil::hasSearch`; the Search tab warns), and the
  default output mode of `fossil sql` is no longer `-quote` (always set
  `.mode`); the SQLite shell of newer Fossils (2.29) escapes control
  characters such as the `char(2)` list separators unless told not to,
  which older ones refuse (`fossil::sqlMode` finds which).  Fossil 2.21 is
  the oldest supported (Debian LTS; 2.23 in Ubuntu 24.04): check what an
  option needs with `fossil::helpMatches` or `fossil::hasCommand` rather
  than the version.  Met so far: `--NAME=VALUE` is 2.22 and newer
  (`fossil::command` splits it), `merge-info` and `user default -v`/`""`
  2.26, `cat -o` and `settings --value` 2.23, `whatis -q` 2.23; 2.23
  ignores `diff -c 0` and takes minutes for `describe` on the Tk
  repository; before 2.26 `title()` of wiki pages and technotes is empty
  and `fossil settings` writes a multi-line value unindented; `fossil::run` (exec) turns CRLF into LF and drops the trailing
  newline, so byte-exact checks export to a file and read it in binary;
  unversioned names cannot contain white space, `uv rm` leaves a row with a
  NULL hash, and `unversioned.mtime` is in Unix seconds; attachment targets
  are the page name, the technote ID or the ticket UUID.
- In Tk 8.6 a treeview lays out rows after `see`: wait until `bbox` is not
  empty before using a row's position.  To stub a namespaced proc but keep
  calling it, rename it within its namespace (`rename ns::p ns::realP`).
- Fossil commands that ask a question read the empty stdin of
  `fossil::run` as "No": after the application's own confirmation, use the
  command's force option, or feed "y" (as `tkstash::dropAll` does).
- Modal dialogs in tests: answer them with a chain of `after` steps that
  wait for the dialog (see `tests/commit-ops.tcl`, the `steps` helper of
  `tests/timeline-edit.tcl`), so a late dialog does not miss its answer.
- Full-text search uses Fossil's SQL functions in `fossil sql`
  (`search_init`, then `search_match`, `search_score`, `search_snippet`,
  `title`, `body`); `search_match` before `search_init` crashes Fossil.
