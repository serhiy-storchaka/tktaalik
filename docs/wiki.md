# Wiki

The Wiki tab shows the repository's wiki pages, technotes, and the notes
Fossil keeps as wiki pages for branches, check-ins, tags and tickets.
Each is shown rendered, with all its earlier versions and what each
version changed.  Pages and technotes can be edited and created, and
files attached to them.

Every change is written to the local repository as the default user,
after a confirmation; nothing is pushed, even with autosync on.

## Pages and technotes

The list at the top has one row per page or technote:

| Column | What it is |
|---|---|
| Page | the name of a wiki page, the comment (title) of a technote |
| Kind | Wiki, Technote, Branch note, Check-in note, Tag note, Ticket note |
| Date | the newest version (a technote: its own date) |
| User | who wrote the newest version |
| Versions | how many versions there are |
| Technote ID | the ID of a technote |

Page, Kind, Date and User are shown at first.  Click a heading to sort, drag it to move the column, right-click it to
choose the columns.

Above the list:

- **Find**: shows the pages whose name (or technote title) contains the
  text; Ctrl+F goes there.
- **All**, **Wiki pages**, **Technotes**, **Notes**: which kinds are
  listed.  Notes are the pages Fossil attaches to branches
  (`branch/NAME`), check-ins, tags and tickets.
- **Show deleted**: also the pages deleted (saved empty), marked
  "(deleted)" and shown in grey.  Technotes are never counted as deleted.

The status line counts the pages shown and the deleted ones not shown.
F5 reads the list again.

The page selected is shown below the list: its title, its kind, for a
technote the date it is for, who wrote the version shown and when.  The
text is rendered by Fossil (Fossil wiki, Markdown or plain text, as the
page says).  Links can be clicked:

- links to other wiki pages open them here (Back returns);
- links to tickets open them in the [Tickets](tickets.md) tab;
- `[hash]` references and links to Fossil pages of an artifact (a
  check-in, a technote, a forum post…) open it where it is shown in
  Tktaalik: a check-in in the [Timeline](timeline.md), and so on, as
  [Go to](goto.md) does; links to a branch (`/timeline?r=BRANCH`) open it
  in the [Branches](branches.md) tab, links to a diff (`/vdiff?…`) in the
  diff window;
- other links open in the browser; they end with a small ↗.

**Open in browser** shows the page or technote on the server.  The context
menu of the list, and the **Page** menu for the page selected, have the
page's buttons (Edit…, the changes, Save…, Attach…, Open in browser) and
**Copy name**.  **New
page…** and **New technote…** are described under [Editing](#editing).

## Versions and changes

**Version** is a menu of all the versions of the page, newest first: the
number, the date and the user.  Choose one to show it.

- **Changes** shows what the version chosen changed: a diff of its source
  against the version before (disabled for the first version).
- **Since** shows what changed after it: a diff against the newest version
  (disabled for the newest).

The diffs are of the source text (as `fossil xdiff` makes them), in
Tktaalik's diff viewer (see [Diffs](diffs.md)).  Line ends of pages edited
on the web (CRLF) are not shown as changes.

**Save…** saves the version shown to a file: its source (`.wiki`, `.md`
or `.txt`, after its format), or, with a name ending in `.html`, the page
rendered as a complete HTML document.

## Editing

**Edit…** opens the version shown in the editor.  Whatever version you
start from, saving makes it the newest version.  **New page…** and **New
technote…** (in the File menu and at the bottom of the tab) open the
editor empty.

The editor has:

- for a page, its **Page** name (fixed when editing);
- for a technote, its **Comment** (the title), **Date (UTC)**, **Tags**
  and **Color** (`#RRGGBB`).  A new technote starts with the date now; the
  date of an existing one cannot be changed here, as Fossil finds the
  technote by its date;
- the **Format**: Fossil wiki, Markdown or Plain text;
- **Write** and **Preview** tabs (Alt+W, Alt+P, or Ctrl+Shift+P to go
  from one to the other): the preview renders the text as it will be
  shown.

**Commit** checks the input first: a page needs a name not used yet, a
technote a comment and a date `YYYY-MM-DD HH:MM:SS` that no other
technote has, and a colour like `#3366cc` or none.  Then it asks before
writing; the question says which user the change is recorded as.
Committing an empty page deletes it (the question warns about that).

The change is written with `fossil wiki create` (new) or `fossil wiki
commit` (edited); a technote keeps its tags and colour.  Pages edited on
the web keep their CRLF line ends, so that only the lines you changed
differ.  Escape or **Cancel** closes the editor without writing.

Editing needs a default user in the repository (see
[Users](repository.md#users)).

## Attachments

The files attached to the page or technote shown are listed under it, if
it has any: attachment, size, user, date and comment.  An attachment
whose content is not in the local repository says "not local".

- Double-click (or Return) views a text attachment in the diff viewer; one
  that is not here opens on the server.  A binary file cannot be viewed:
  save it.
- Right-click: **View**, **Save…**, **Open in browser**, **Copy file name**.

**Attach…** (next to Save) adds files to the page or technote shown, with
`fossil attachment add`; you can choose several files at once.  A file
with the name of an existing attachment replaces it (the earlier one
stays in the history); the question names those.  Technotes get their
files by technote ID.  Attaching needs a default user.

Tickets cannot get attachments here (see [Tickets](tickets.md#attachments)).
