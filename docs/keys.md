# Keys and mouse

## Global keys

These work in every tab.

| Key | Action |
|---|---|
| F1 | this manual, at the page about what has the focus: the tab, its search box, the window or dialog |
| Ctrl+1 … Ctrl+9, Ctrl+0 | the Timeline, Tickets, Branches, Tags, Files, Commit, Stash, Wiki, Forum and Search tabs (also in the View and Checkout menus) |
| Ctrl+Tab, Ctrl+Shift+Tab | the next tab, the previous tab |
| Alt+Left, Alt+Right | Back, Forward (see [Back and Forward](index.md#back-and-forward)) |
| Back, Forward keys of the keyboard | the same |
| Ctrl+G | [Go to](goto.md) a hash, ticket id, tag or branch |
| Ctrl+Shift+F | the [Search](search.md) tab, with the cursor in its search box |
| Ctrl+O | open a repository file |
| Ctrl+Q | quit (the settings are saved) |

The Commit and Stash tabs need a checkout: without one, their keys only
beep.

## Keys in the tabs

| Key | Where | Action |
|---|---|---|
| F5 | every tab | read the repository again (File ▸ Refresh) |
| Ctrl+F | every tab: Timeline, Tickets, Branches, Tags, Files, Stash, Wiki, Forum, Search | to the search or filter box, its text selected |
| Return | a search box | search (and record a place for Back) |
| Escape | the search box of Tickets, Timeline, Branches | clear the search |
| Down | the Search tab's box | to the results |
| Up, Down, Return | Search results | choose a result, open it |
| Return, double-click | Timeline | the check-in's diff; the ticket of a ticket change; a wiki page, technote or forum post in its tab |
| Return, double-click | Tickets list | edit the ticket |
| double-click | Branches | the branch's diff; in its details, a check-in's diff or a ticket |
| double-click | Commit | the file's diff, side by side |
| Return, double-click | Files history | that version's diff against the one before |
| Return, double-click | Files: Find in history | a version: its content; a line: the content at that line |
| Ctrl+N, Ctrl+E | Tickets | new ticket, edit the ticket shown |
| Alt+C, Alt+I, Alt+A, Alt+H | Tickets details | Comments, Check-ins, Attachments, History |
| Ctrl+Return | Tickets comment window | post the comment |
| Ctrl+Shift+P | text editors (comments, descriptions, wiki pages) | Write ↔ Preview |
| Ctrl+Return | Commit | commit |

The pages of the tabs describe their keys in detail.

In the windows of the Repository menu, and in the Go to and Ticket reports
windows:

| Key | Action |
|---|---|
| F5 | read again (Information, Settings, Users, Remotes, Unversioned files, Ticket reports) |
| Ctrl+F | Settings: to the filter |
| Return, double-click | Unversioned files: view the file; Go to: open the one chosen |
| double-click | Users: edit the user; Remotes: open it in the browser; Ticket reports: the ticket of the row |
| Delete | Unversioned files: remove the selected files |
| Ctrl+A | Unversioned files: select all |
| Escape | close the window (it keeps its state for the next time) |

In the window of an attached image (see [Images](tickets.md#images)):

| Key | Action |
|---|---|
| Ctrl+plus, Ctrl+minus (also on the keypad), Ctrl+Wheel | zoom in, out (the wheel at the pointer) |
| Ctrl+0 | 100% |
| Wheel, Shift+Wheel | scroll down and up, left and right |
| Escape | close the window |

In dialogs, Return is usually the default button and Escape cancels.

## Mouse

| Mouse | Action |
|---|---|
| side buttons (back, forward) | Back, Forward, in every tab |
| click a column heading | sort by the column; again: the other way |
| drag a column heading | move the column |
| right-click a column heading | choose the columns, sort, "Default columns" (see [Columns and sorting](configuration.md#columns-and-sorting)) |
| right-click a row | in every list, a context menu: what can be done with it (the window's buttons for it, Copy…).  On macOS also Control-click |
| right-click the Content or Blame of a file | copy the lines selected, copy a link to them on the server; in Blame, the diff of the line's check-in |
| hover | tooltips: icon headings and cells, check-in hashes, buttons |
| click a link | in rendered texts: tickets, check-ins and other artifacts, branches, wiki pages, forum posts open in their tab (as [Go to](goto.md) does), diffs in the diff window, other links in the web browser.  A link that opens the browser ends with a small ↗ |
| drag the bar between two panes | resize them |

On macOS, Control-click works as a right-click in the tables.
