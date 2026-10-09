# Search

The **Search** tab searches check-in comments, tickets, wiki pages, technotes,
forum posts and documents at once, and lists what it finds in one list,
the best matches first, with the matching words marked.
The other tabs search only their own kind; this one searches all of them.

It uses Fossil's own full-text search: the same matching,
ranking and snippets as `fossil search` and the search page of Fossil's web
interface. It only reads the repository.
Fossil's search settings (`fossil fts-config`) do not need to be turned on,
and nothing is indexed: each search reads the texts again.
On a large repository a search takes up to a second or two;
the kinds are searched side by side,
and the results appear as each kind is done.

The tab runs Fossil's search through `fossil sql`,
and Fossil 2.28 and newer lost the search functions there
(a Fossil bug, reported).
With such a Fossil the tab says so and does not search;
Fossil 2.27 or older works, as will a Fossil with the bug fixed.
The other tabs' search boxes are not affected.

Go to the tab with **Ctrl+0**,
or with **Ctrl+Shift+F** from any tab
(which also puts the cursor in the search box).

## Search syntax

Type words and press Return (or click **Search**).

- A text matches when it has **all** the words, in any order and anywhere in it.
- Words match whole words: `menu` does not find "menubutton".
- A word ending in `*` matches every word that starts with it:
  `menu*` finds "menu", "menus", "menubutton".
- Upper and lower case are the same.
- Punctuation separates words; quotes, `OR`,
  `-` and the like have no special meaning
  (they are ignored, or searched as words).

Examples:

```
menubutton traversal       both words
ttk::notebook              the words "ttk" and "notebook"
scroll*                    scroll, scrollbar, scrolling, ...
crash windows 9.0          all three words
```

What is searched of each kind:

| Kind | The text searched |
|---|---|
| Check-ins | the check-in comment, with the user and the branch and tags |
| Tickets | the title and the fields and comments of the ticket |
| Wiki | the newest version of each wiki page: its name and text |
| Technotes | the newest version of each technote: its comment and text |
| Forum | the newest version of each forum post: its title and text |

The check boxes under the search box
(**Check-ins**, **Tickets**, **Wiki**, **Technotes**,
**Forum**) choose the kinds; changing one searches again. They are remembered,
and so are the last 30 searches (the drop-down list of the search box).

## Results

Each result is a line with its kind, its title and its date,
and under it a snippet: the part of the text around the words found,
with the words marked.
For a check-in the title is the start of its comment.

The results of all kinds are ranked together by Fossil's score,
and among equal scores the newest first.
Each kind gives up to 200 results;
the status line says how many of each were found
("200+ check-ins, 37 tickets") and whether something could not be searched.
When a kind has 200 (shown as "200+"),
**More** searches again with twice as many of each kind;
a new search starts again with 200.

**Docs** (off at first) searches documents:
the files of the repository's `doc-branch`
(else `trunk` or `main`) matching its `doc-glob`,
as Fossil's `fossil search --docs` does.
Most clones have no `doc-glob`
(it is a setting of the web pages, not copied by a clone):
then type which files in the box next to Docs,
patterns separated by commas or spaces, like `*.md doc/*.n`;
the status line says so when there are none.
A document opens in the [Files](files.md) tab at that version.

**Fossil help** (off at first) searches Fossil's own help: its commands,
settings and web pages, as `fossil search -h` does.
A result opens the help text (`fossil help NAME`) in a window.

### The search index

**Search index…** shows Fossil's full-text index of the repository
(`fossil fts-config`): whether it is on, which kinds Fossil's search covers,
the tokenizer, how many documents.
Its buttons change these, each after a confirmation: **Reindex**, **Index on**,
**Index off**, **Enable** or **Disable** a kind
(check-ins, documents, tickets, wiki, technotes, forum, help, all),
and the **Tokenizer** (porter, unicode61, trigram, off; the index is rebuilt).
These are settings of this repository only, never synced.
The index serves Fossil's web search page and `fossil search`;
this tab does not need it and does not use it
(Fossil brings the index up to date when it searches,
which a reader of the repository cannot do).

To open a result:

- click its title, or
- press Down in the search box to move to the results,
  Up and Down to choose one (it is highlighted), and Return to open it.

| Result | Opens |
|---|---|
| Check-in | the check-in in the [Timeline](timeline.md) |
| Ticket | the ticket in the [Tickets](tickets.md) tab |
| Wiki page, technote | its newest version in the [Wiki](wiki.md) tab |
| Forum post | its thread in the [Forum](forum.md) tab, at the post |
| Document | the file in the [Files](files.md) tab, at the version searched |

**Back** (Alt+Left) returns to the search, with the same words and kinds,
scrolled where it was.
**F5** searches again;
it also happens by itself when you come back to the tab after the repository has
changed.

The words of a ticket's fields are found too
(for example a user name in the Assigned to field); to search tickets by field,
use the [Tickets](tickets.md) tab's own search (`assignee:`, `status:`, …).
To narrow down check-ins by date, branch or user,
use the [Timeline](timeline.md) search.
