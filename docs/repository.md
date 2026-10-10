# The Repository menu

The Repository menu, in every tab, opens windows about the repository shown:
its information, settings, users,
remotes and unversioned files. They stay open beside the main window and follow
it: open another repository and they show that one.
Close one with **Close** or Escape; F5 reads it again.

Changes made in these windows go into the local repository
(or, for global settings, into Fossil's global settings),
after a confirmation. Nothing is synced: no window here pulls, pushes or syncs.

## Information

What `fossil info -v` says about the repository,
and about the checkout when one is open: the project name and code,
the repository file, the checkout's check-in, its tags and comment,
the Fossil version, and so on. Then:

- **Size**: the size of the repository file.
- **Checkouts**: every checkout of the repository Fossil knows of,
  with when each was last used
  (also when the repository is opened without a checkout).
- **Accessed as**: the URLs the repository was served at, with when.
- **Contents**: how many check-ins, ticket changes, tickets, wiki pages,
  technotes, tags, files, artifacts and users the repository holds,
  and forum posts and unversioned files when it has them.
- **Statistics** (`fossil dbstat`): the artifacts and their sizes,
  the compression, the latest change, the age of the project, its ID,
  the schema and SQLite versions, the database pages; the **hash policy**;
  the **login group** it is part of, if any.
- **Fossil**: the version of Fossil running.
  At start, Tktaalik warns if it is older than 2.21,
  the oldest it is tested with.
  A few things need a newer one and say so:
  the merge details and the three-way view of a merge need Fossil 2.26
  (`fossil merge-info`).

**Check integrity** runs a quick check of the database
(`fossil dbstat --db-check`) and says the result below.
**Full verification…** decodes and checks every artifact (`--db-verify`),
in the background: on a big repository it takes minutes.
Neither changes anything; **Refresh** reads it all again.

**Maintenance ▸** changes the repository file,
after asking (Fossil has no dry run for these):

- **Rebuild…** (`fossil rebuild`): after updating Fossil,
  or when a check found problems; with the full-text search index kept,
  added (`--index`) or left out (`--noindex`),
  as small as possible (`--compress`), analyzed (`--analyze`),
  vacuumed (`--vacuum`), clustered (`--cluster`),
  with a write-ahead log (`--wal`).
- **Repack…** (`fossil repack`): more delta compression, to make it smaller.
- **About Fossil…**: the version of Fossil and how it was built
  (`fossil version -v`).

Both offer a backup first (Back up repository…),
and run in a window showing their output; they are not stopped half way.

## Settings

Fossil's settings (`fossil settings`),
each with the value in effect and where it comes from.

| Column | What it is |
|---|---|
| Setting | the name |
| Value in effect | the value Fossil uses; "(file NAME)" for a versioned one |
| From | this repository, global, versioned or default |
| This repository | the value set for this repository |
| Global | the value set for all repositories |

The last two columns are hidden at first (right-click a heading to show them).
**Find** (Ctrl+F) narrows the list to names containing the text;
**Only the ones set** hides those at their default.
The status line counts the settings and those set.

Selecting a setting shows, on the right, where its value comes from,
the values for this repository and globally, and Fossil's own help for it.
A *versioned* setting is a file `.fossil-settings/NAME` in the checkout;
it overrides the other values, and its content is shown.
To change it, edit and commit that file.

Under the help, **Value** holds the value to set
(at first the repository's value, else the global one), and four buttons:

| Button | Runs |
|---|---|
| Set for this repository | `fossil settings NAME VALUE` |
| Set globally | `fossil settings NAME VALUE --global` |
| Unset here | `fossil unset NAME` |
| Unset globally | `fossil unset NAME --global` |

Each asks first, naming the repository or the global settings file.
A value cannot be empty (use Unset) or start with `-`, `<`,
`>` or `|`. Turning **autosync** on warns that Fossil then pushes after commits
and other changes, and that the Branches tab refuses to close,
hide or create branches.

## Users

The users of the repository: User, Capabilities, Changed, Contact.
The default user (the one changes made here are recorded as) is marked ★ and in
bold; the users that stand for kinds of users
(nobody, anonymous, reader, developer) are grey.
The status line names the default user and where it comes from: the repository,
or the environment (`USER`, ...).

Selecting a user shows its capabilities on the right, each letter explained,
and the capabilities it also has from nobody, anonymous,
reader (`u`) or developer (`v`).

| Button | What it does |
|---|---|
| New user… | create a user: name, contact, password (twice) and capabilities (`fossil user new`, then `capabilities`) |
| Edit… (or double-click) | change the contact, the capabilities and the password (`fossil user contact`, `capabilities`, `password`) |
| Make default user… | changes made here will be recorded as this user (`fossil user default NAME`) |
| Unset default… | no default user in the repository: Fossil then takes the user from `-U`, `FOSSIL_USER`, `USER`, `LOGNAME` or `USERNAME` (Fossil 2.26 or newer; older ones cannot unset it, nor say where the default user comes from) |

In the form the capabilities are a check box each, explained;
a new user starts with those of the repository's `default-perms` setting.
When editing, an empty password leaves it unchanged.
The question before writing lists what changes.
The password is passed to `fossil` on its command line,
as Fossil has no other way.

Users cannot be deleted in Fossil.
A user name cannot have spaces, quotes or `<>&`, nor start with `-`.

## Remotes

The remote repositories this one syncs with (`fossil remote list`):
the *default* remote, in bold, which `fossil pull` and `fossil push` use,
and named ones.
Passwords are never shown.

| Button | What it does |
|---|---|
| Add… | a named remote: a name and a URL (`fossil remote add`).  With the name empty, the URL becomes the default remote (`fossil remote URL`) |
| Save as… | a copy of the selected remote under another name, with its saved password (`fossil remote add NAME FROM`), to come back to it later |
| Delete… | delete a named remote |
| Make default… | the selected remote becomes the default (`fossil remote NAME`) |
| No default… | turn the default remote off (`fossil remote off`), as for working offline |
| Forget passwords… | forget the saved passwords; the URLs stay (`fossil remote scrub`) |
| Open in browser (or double-click) | the remote's web pages, without the user name |
| Copy link | the URL of the checkout on the default remote (`fossil remote hyperlink`); needs a checkout |

Each change asks first.
Remote names are letters, digits, `_`, `.` and `-`, not "default".

To work offline and come back: select the default remote,
**Save as…** under a name, then **No default…**;
later select the saved one and **Make default…**.

## Unversioned files

The files Fossil keeps outside the check-ins (`fossil uv`),
such as downloads and release archives: only the newest of each.

| Column | What it is |
|---|---|
| Name | the file name, possibly with folders |
| Size | its size |
| Stored | its size as stored (compressed); "not here" if the content is not in the local repository |
| Date (UTC) | when it was stored |
| Hash | its hash |

**Find** takes part of a name,
or a pattern like `*.zip` or `doc/*`. Several files can be selected
(Ctrl+A selects all).

| Button | What it does |
|---|---|
| View (or double-click, Return) | a text file, in a viewer; an image in a window of its own, as for [attached images](tickets.md#images) (zoom, several open); greyed out for an image that cannot be shown (without Img, …), which a double-click opens on the server |
| Export… | one file to a file, several to a folder (names with folders keep them) |
| Edit… | edit a text file and store it again (line ends kept) |
| Add… | add files: one under a name you choose, several under their own names in an optional folder; a file with an existing name replaces it |
| Rename… | store the file under another name and remove the old one (Fossil has no rename, so the time becomes now) |
| Touch… | change the time of the selected files, to now or any time |
| Remove… (or Delete) | remove the selected files |
| Open in browser | the file on the server (`/uv/NAME`) |
| Download… | make the files here those of the server (`fossil uv revert`): changed ones replaced, those only here removed.  The question lists the files it would download (`-n`); Fossil's dry run cannot tell which files only here it would remove, so it says how many files are here |

Add… also asks for the time of the files
(empty: now; the newer one wins at the next sync).
Every change asks first.
Names cannot have spaces
(suggested names have `_` instead) and cannot point outside the repository.

Changes to unversioned files cannot be undone: they have no history,
and replacing a file loses its old content.
They stay in the local repository:
they reach the server only with `fossil uv sync`, which is never run here.

## Repository operations

The **Repository** menu has, below its windows:

| Entry | What it does |
|---|---|
| Back up repository… | a copy of the repository file (`fossil backup`), to a file you choose (beside the repository at first; not the repository itself) |
| Pull configuration… | the configuration of an area (ticket setup and reports, skin, users…) from a remote, by its name so that its saved password is used (`fossil configuration pull`): it only downloads; "Replace" for `--overwrite` |
| Export configuration… | an area's configuration to a file (`fossil configuration export`); it asks before replacing a file |
| Import configuration… | a file exported before, merged with the configuration here or replacing it (`configuration merge` / `import`) |
| Reset configuration… | an area's configuration back to Fossil's defaults (`fossil configuration reset`), exported to a file first if wanted |
| Open locally in browser | the repository served on this computer only (`fossil ui`), in the browser, at what is shown (the check-in, ticket, branch, wiki page or forum thread selected); stopped when another repository is shown and when Tktaalik quits |
| Open chat in browser | the chat of the default remote (`/chat`) |
| Download chat archive… | the chat's messages into a file of their own (`fossil chat pull --out`, all of them or the new ones); the server allows it only to users with Setup privilege |

The **File** menu: **Known repositories** lists the repositories this computer
knows (`fossil all list`) to open one,
and **Known checkouts** its checkouts (`fossil all list -c`),
with **Changes in all of them…**: the uncommitted changes of each.
These only read: a repository or checkout not found now
(on a disk not mounted) is not listed,
and stays known. **Clone repository…** copies a repository from its URL
(or file) into a new file,
optionally with a checkout in a folder
(`fossil clone`: admin user, HTTP user and password, private branches,
unversioned files, remember the password, do not remember the URL (`--once`),
nested); it only downloads, the password is not shown in its window,
and the admin password Fossil makes is shown.
**New repository…** makes an empty one
(`fossil init`: project name, description, admin user,
the settings of another repository as a template).
Paths can start with `~` (the home folder);
relative paths are from the folder Tktaalik is in (the checkout's).

The **Checkout** menu:
**New checkout…** opens a checkout of the repository in a folder
(`fossil open --workdir`, never syncing: a version or the newest, empty,
file times as in the repository, keep the files there, nested, force);
**Close checkout…** closes the checkout shown (`fossil close`; its files stay):
it says first if changes are not committed or stashes would be lost,
then shows the repository.

Each asks first; nothing is pushed.
One of these dialogs is open at a time.
Those that take long
(Clone, Pull configuration, Download,
Download chat archive) show their output in a window with **Stop**;
whatever still runs is stopped when Tktaalik quits.
