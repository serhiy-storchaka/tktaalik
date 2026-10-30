# Statistics

**Repository ▸ Statistics…** opens a window of charts about the repository shown:
how active it is, who works on it, its tickets, its forum and its size.
It only reads the repository.
Like the other [windows of the Repository menu](repository.md),
it stays open beside the main window and follows it to another repository.

At the top:

- **Period**: all time, the last 10 or 5 years, the last year
  or the last 90 days.
- **Counted by**: what one bar is, a year, a month, a week (from Monday)
  or a day.
  **Automatic** chooses by the period: years for all time and for 10 years,
  months for 5 years, weeks for a year, days for 90 days.
- **Refresh** (F5) reads the repository again.

Dates are in UTC, as in the [Timeline](timeline.md),
so a click on a bar finds the same events there.
The status line counts the events and gives the first and the last date.

## Activity

- **Events per year** (month, week, day): the events of the period,
  stacked by kind (check-ins, tickets, wiki, technotes, forum, tags).
  Click a part of a bar to list those events in the Timeline
  (`date:2025-03 kind:ci`), or between the parts for all of them.
- **The last year**: a calendar, a column for each week, a square for each day,
  darker for more events.
  Click a day for its events in the Timeline.
- **Weekday by hour (UTC)**: when the events of the period happened.

## Contributors

- **Check-ins by user**: the 25 users with the most check-ins in the period.
  Click one for their activity below.
- **Users with check-ins**: how many users made check-ins in each year
  (month, week, day).
- **Activity of** a user: their events in each year (month, week, day),
  stacked by kind.
  At first the user with the most check-ins;
  choose another in the box (everyone with events in the period,
  the most active first) or click their bar above.
  Click a part of a bar for those events in the Timeline
  (`date:2025 user:NAME kind:ci`).

## Tickets

- **Tickets opened and closed**: lines of the tickets opened
  and those closed in each period.
  Click a point for those tickets in the Tickets tab
  (`created:2025`, `closed:2025`).
- **Tickets not closed**: how many were not closed at the end of each period.
  These two need the tickets' closing date (the `closedate` field):
  without it only the opened ones are shown.
- **Tickets by** a field (type, status, subsystem, priority, severity,
  found in, resolution, assignee): the tickets of the period by its values,
  of the open tickets only with **Open only**.
  Click a value for those tickets.
- **How long the open tickets are open**: from under a month
  to ten years and more.
  Click a bar for those tickets.

## Forum

- **Forum posts**: the new threads and the replies in each period
  (their first versions, not the edits).
  Click a bar for the posts in the Timeline.
- **Forum posts by user**: the 25 users who post the most.

## Size

- **Stored per year** (month, week, day): what the repository grew by,
  compressed as Fossil stores it: the versions of files
  that the check-ins of the period brought, and the check-ins,
  ticket changes, wiki pages and posts themselves.
- **Stored in all**: the size of the repository at the end of each period.
- **Artifacts by kind**: check-ins, versions of files, ticket changes,
  wiki and technote versions, forum posts, tag changes, attachments.
- **Largest files**: the 20 files with the largest version.
  Click one for the check-ins that changed it in the Timeline.

## Charts

These charts, and the others of Tktaalik, work alike:

- Hover over a bar, a point or a square for its values.
  Where a click shows something, the pointer is a hand.
- Right-click a chart for **Copy data** (its numbers, separated by tabs:
  for a spreadsheet), **Save as SVG…** and **Save as PostScript…**.
- They follow the [size of the text](keys.md#text-size):
  click a chart, then Ctrl+plus, Ctrl+minus, Ctrl+0, or Ctrl+Wheel over it.

The other charts:

- the [graph of the check-ins](timeline.md#the-graph) in the Timeline;
- the lines added and deleted by a check-in, in the
  [Timeline's details](timeline.md#details),
  and by each changed file in the [Commit tab](commit.md#changed-files);
- the activity of each branch of the last year in the
  [Branches list](branches.md#columns);
- the versions of a file per year in its [history](files.md#file-history);
- the check-ins of a [bisect](timeline.md#the-bisect-window) in a strip;
- a ticket report [by the values of a column](tickets.md#reports).
