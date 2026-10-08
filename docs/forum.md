# Forum

The **Forum** tab shows the forum of the repository: its threads, newest
activity first, and below them the posts of the thread selected, threaded
and rendered.  You can start threads, reply, and edit or delete your own
posts ([Writing](#writing)).

A repository has a forum only if it is a forum repository or one where the
forum is used; otherwise the status line says "No forum in this
repository".  A clone has the forum posts its server sent it: pull to get
the new ones ([Pull](timeline.md#pull)).

## Threads

The upper half is the list of threads.

| Column | What it shows |
|---|---|
| Thread | the title of the thread (the title of its first post, as last edited) |
| Started by | who wrote the first post |
| Started | when the first post was written |
| Last post | when the thread last changed: the newest post or edit |
| Last by | who wrote that post or edit |
| Posts | how many posts the thread has (an edited post counts once) |

The list holds the 1000 threads with the newest activity; the status line
says how many there are in all ("1000 newest of 3568 threads").  **More**
doubles the number shown.  Click a heading to sort the threads shown by
that column; the columns can be chosen and moved like in the other tabs
([Columns and sorting](configuration.md#columns-and-sorting)).

**Find** (Ctrl+F) narrows the list to the threads whose title contains
what you type, or that were started by a user whose name contains it.
Upper and lower case are the same.  The list follows as you type.  To find
words in the posts themselves, use the [Search](search.md) tab with only
**Forum** checked.

The first thread is selected when the list is shown; select another one with
the mouse or the arrow keys.  **F5** (File ▸ Refresh) reads the forum again.
**Open in browser** opens the selected thread on the server the repository
was cloned from.

## Posts

The lower half shows the posts of the selected thread, under its title:

- Each post starts with a line with its author and the date it was written.
  An edited post shows its newest version, with "edited" and the date of
  the edit after the first date.
- A reply comes after the post it answers, indented one step more.  Replies
  to the same post are in the order they were written.  (Deep threads stop
  indenting after eight levels.)
- A post deleted by its author (an edit with no text) shows "(deleted)".
- The text is rendered as on the web pages: Markdown, Fossil wiki markup, or
  plain text, whichever the post was written in.

Links in the posts:

| Link to | Opens |
|---|---|
| another forum post (`/forumpost/HASH`, `/forumthread/HASH`) | that thread here, scrolled to the post |
| a ticket (`[hash]` of a ticket) | the ticket in the [Tickets](tickets.md) tab |
| a check-in or other artifact (`[hash]`, `/info/HASH`…) | a forum post here if it is one, else where it is shown in Tktaalik (a check-in in the [Timeline](timeline.md), as [Go to](goto.md) does), else the page on the server |
| a branch (`/timeline?r=BRANCH`), a diff (`/vdiff?…`) | the branch in the [Branches](branches.md) tab, the diff in the diff window |
| anything else | the web browser (such links end with a small ↗) |

`[hash]` references in the text (a hash prefix in square brackets) become
links when the repository has what they name.

Following a link records a place for **Back** (Alt+Left), which returns to
the thread and the place in it you left.  Back and Forward also remember the
Find text and how many threads were shown.

You can also open a post directly with [Go to](goto.md) (Ctrl+G): type the
hash or a prefix of any post, or of any version of an edited post.

## Writing

**New thread…** (Forum ▸ New thread…, Ctrl+N, or the button at the bottom)
asks for a title and the text; **Reply…**, after the name and date of each
post, answers that post.  The text is written in the same editor as ticket
comments, in Markdown (the default), Fossil wiki or plain text, with its
**Preview**.  **Post** (or Ctrl+Return in the text) sends it, as below.

Your own posts (by the user you post as) also have **Edit…** and
**Delete…**.  **Edit…** opens the post's text in its format (and the
thread's title, for the first post of a thread); **Save** sends a new
version of the post, which the thread then shows, "edited".  **Delete…**
replaces the text with nothing — a new, empty version, shown "(deleted)";
the replies to it stay.  Neither takes anything back: the earlier versions
stay in the repository's history.  The server decides in the end: a closed
thread cannot be edited, except by an administrator (whose **Edit…** for
other people's posts is only in the web interface).

Posts are sent to the server, as from its web pages: Tktaalik logs in
there (with `curl`) and fills in the same forms, so anyone allowed to post
on the website can post here, without the right to push.  The window asks
for your user and password on the server: the user from the repository's
server URL, else its default user, and the password Fossil saved for that
URL's user (when you let it remember the password for sync), if any.  A
password typed here is kept until Tktaalik is closed, never saved.
**Post** (**Save**, **Delete**) asks first: it goes to the server at once.
Then the repository pulls, and the thread is shown with the change.

If the server holds your posts for a moderator (users the forum does not
yet trust), Tktaalik says so; the post shows here once it is approved and
pulled.
