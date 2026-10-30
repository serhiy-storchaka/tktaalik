# The Statistics window (lib/tkstats.tcl): its charts count what the
# repository has (checked against SQL), a click searches it in the
# Timeline or Tickets tab, the period and the length of a bar; an empty
# repository.  Also the other charts on the Tk repository: the activity
# of the branches and a ticket report by a column.  Only reads.
source [file join [file dirname [info script]] common.tcl]
start timeline
proc total {w} {
    set sum 0
    foreach {name values} [dict get $charts::spec($w) -series] {
        foreach v $values { set sum [expr {$sum + $v}] }
    }
    return $sum
}
proc cellsum {w} {
    set sum 0
    foreach {r c v k t} [dict get $charts::spec($w) -cells] { if {[string is integer $v]} { incr sum $v } }
    return $sum
}
tkstats::window
update
set a .stats.nb.activity
waitUntil {[dict get $charts::spec($a.time) -type] eq "bars"}
set events [lindex [sql "SELECT count(*) FROM event"] 0 0]
check "the events per year: [total $a.time] of $events" {[total $a.time] == $events}
set first [lindex [sql "SELECT strftime('%Y', min(mtime)) FROM event"] 0 0]
check "from $first to this year: [lindex [dict get $charts::spec($a.time) -categories] 0]..." {[lindex [dict get $charts::spec($a.time) -categories] 0] eq $first
    && [lindex [dict get $charts::spec($a.time) -categories] end] eq [clock format [clock seconds] -format %Y -timezone :UTC]}
check "kinds: [dict keys [dict get $charts::spec($a.time) -series]]" {"Check-ins" in [dict keys [dict get $charts::spec($a.time) -series]]
    && "Tickets" in [dict keys [dict get $charts::spec($a.time) -series]]}
check "weekday by hour: all of them" {[cellsum $a.hours] == $events}
set cells [dict get $charts::spec($a.cal) -cells]
set start [lindex $cells 3]
set lastYear [lindex [sql "SELECT count(*) FROM event WHERE mtime >= julianday('$start')"] 0 0]
check "the last year: [expr {[llength $cells] / 5}] days from $start, [cellsum $a.cal] events" {[llength $cells] / 5 >= 365 && [llength $cells] / 5 <= 371
    && [clock format [clock scan $start -format %Y-%m-%d -timezone :UTC] -format %u -timezone :UTC] == 1
    && [cellsum $a.cal] == $lastYear}
check "the status: $tkstats::status" {[string match "[charts::number $events] events from *" $tkstats::status]}

# Clicks: a search in the Timeline.
tkstats::showEvents 2025 Check-ins; update
check "a bar: [list $tktimeline::query]" {$tktaalik::active eq "timeline" && $tktimeline::query eq "date:2025 kind:ci"}
tkstats::showDay 2026-01-05; update
check "a day: [list $tktimeline::query]" {$tktimeline::query eq "date:2026-01-05"}

# Contributors.
.stats.nb select .stats.nb.people; update
set p .stats.nb.people
waitUntil {[dict get $charts::spec($p.top) -type] eq "bars"}
set top [lindex [sql "SELECT coalesce(euser, user), count(*) FROM event WHERE type='ci' GROUP BY 1 ORDER BY 2 DESC LIMIT 1"] 0]
check "the most check-ins: $top" {[lindex [dict get $charts::spec($p.top) -categories] 0] eq [lindex $top 0]
    && [lindex [dict get $charts::spec($p.top) -series] 1 0] == [lindex $top 1]
    && [llength [dict get $charts::spec($p.top) -categories]] <= 25}
# The activity of a user: the one with the most check-ins first, another
# chosen by a click on their bar.
check "at first the most check-ins: $tkstats::person" {$tkstats::person eq [lindex $top 0]}
set other [lindex [dict get $charts::spec($p.top) -categories] 1]
tkstats::chooseUser $other Check-ins; update
set theirs [lindex [sql "SELECT count(*) FROM event WHERE coalesce(euser, user)=[fossil::sqlstr $other]"] 0 0]
check "$other's events per year: [total $p.user] of $theirs" {$tkstats::person eq $other && [total $p.user] == $theirs
    && [string match "Events of $other per year" [dict get $charts::spec($p.user) -title]]
    && $other in [$p.userbar.u cget -values]}
set year [lindex [dict get $charts::spec($p.user) -categories] end]
tkstats::showPersonEvents $year Check-ins; update
check "a bar of theirs: [list $tktimeline::query]" {$tktimeline::query eq "date:$year user:$other kind:ci"}
tktaalik::show timeline

# Tickets.
.stats.nb select .stats.nb.tickets; update
set t .stats.nb.tickets
waitUntil {[dict get $charts::spec($t.flow) -type] eq "bars"}
set opened [lindex [dict get $charts::spec($t.flow) -series] 1]
check "opened: [tcl::mathop::+ {*}$opened]" {[tcl::mathop::+ {*}$opened] == [lindex [sql "SELECT count(*) FROM ticket"] 0 0]}
set open [lindex [sql "SELECT count(*) FROM ticket WHERE [::tickets::stateExpr]='open'"] 0 0]
check "open by type: [total $t.field] of $open" {[total $t.field] == $open}
check "open by age: [total $t.age]" {[total $t.age] == $open}
set backlog [lindex [dict get $charts::spec($t.backlog) -series] 1]
set notClosed [lindex [sql "SELECT count(*) FROM ticket WHERE NOT (coalesce(closedate, '')<>'' AND [::tickets::stateExpr] IN ('closed', 'deleted'))"] 0 0]
check "not closed at the end: [lindex $backlog end] of $notClosed" {[lindex $backlog end] == $notClosed}
tkstats::showField type Bug Tickets; update
check "a type: [list $tktsearch::query]" {$tktaalik::active eq "tickets" && $tktsearch::query eq "is:open type:bug"}
tkstats::showTickets 2025 Closed; update
check "closed in a year: [list $tktsearch::query]" {$tktsearch::query eq "closed:2025"}
tkstats::showAge {30 182} "Open tickets"; update
check "an age: [list $tktsearch::query]" {[regexp {^is:open created:<=\d{4}-\d\d-\d\d created:>=\d{4}-\d\d-\d\d$} $tktsearch::query]}
set tkstats::field subsystem
set tkstats::openOnly 0
tkstats::draw tickets 1
check "all by subsystem: [lindex [dict get $charts::spec($t.field) -title]]" {[string match "Tickets by subsystem" [dict get $charts::spec($t.field) -title]]
    && [total $t.field] <= [lindex [sql "SELECT count(*) FROM ticket"] 0 0]}

# Forum and size.
.stats.nb select .stats.nb.forum; update
set f .stats.nb.forum
set posts [lindex [sql "SELECT count(*) FROM forumpost WHERE fprev IS NULL"] 0 0]
check "forum posts: $posts" {($posts == 0 && [dict get $charts::spec($f.posts) -type] eq "message")
    || [total $f.posts] == $posts}
.stats.nb select .stats.nb.size; update
set s .stats.nb.size
waitUntil {[dict get $charts::spec($s.kinds) -type] eq "bars"}
check "check-ins among the artifacts" {[lindex [dict get $charts::spec($s.kinds) -categories] 0] eq "Check-ins"
    && [lindex [dict get $charts::spec($s.kinds) -series] 1 0] == [lindex [sql "SELECT count(*) FROM event WHERE type='ci'"] 0 0]}
set largest [lindex [sql "SELECT max(b.size) FROM mlink m JOIN blob b ON b.rid=m.fid WHERE m.fid>0"] 0 0]
check "the largest file: $largest" {[lindex [dict get $charts::spec($s.largest) -series] 1 0] == $largest}
set stored [lindex [dict get $charts::spec($s.total) -series] 1 end]
check "stored in all: [charts::bytes $stored]" {$stored > 0 && $stored == [total $s.growth]}

# The last year, by week.
# (The year moves on while the chart is drawn: an event at its start may
# leave it, so the events counted before and after are the bounds.)
proc lastYear {} { lindex [sql "SELECT count(*) FROM event WHERE mtime >= julianday('now', '-1 year')"] 0 0 }
set before [lastYear]
.stats.top.p set "The last year"
tkstats::choose period
.stats.nb select .stats.nb.activity; update
waitUntil {[llength [dict get $charts::spec($a.time) -categories]] < 60}
set weeks [dict get $charts::spec($a.time) -categories]
set after [lastYear]
check "a year in weeks: [llength $weeks], [total $a.time] events ($after..$before)" {[llength $weeks] >= 52 && [llength $weeks] <= 54
    && [total $a.time] <= $before && [total $a.time] >= $after}
tkstats::showEvents [lindex $weeks 1] ""; update
check "a week: [list $tktimeline::query]" {[regexp {^date:\d{4}-\d\d-\d\d\.\.\d{4}-\d\d-\d\d$} $tktimeline::query]}
.stats.top.b set Month
tkstats::choose by
check "by month: [llength [dict get $charts::spec($a.time) -categories]]" {[llength [dict get $charts::spec($a.time) -categories]] in {12 13}}
set tkstats::period all
set tkstats::by auto
tkstats::ShowChoices

# An empty repository: messages, no errors.
exec fossil init $T(tmp)/empty.fossil
tktaalik::openPath $T(tmp)/empty.fossil; update
foreach tab {activity people tickets forum size} {
    .stats.nb select .stats.nb.$tab; update
}
check "empty: no tickets" {[dict get $charts::spec($t.flow) -type] eq "message"}
check "empty: no forum" {[dict get $charts::spec($f.posts) -type] eq "message"}
wm withdraw .stats

# The activity of the branches (the last year, four weeks a bar).
tktaalik::openPath $T(repo); update
tktaalik::show branches; update
set bt .branches.main.list.t
waitUntil {[info exists tkbranches::branches(main)]}
set recent [lindex [sql "SELECT count(*) FROM tagxref x JOIN event e ON e.objid=x.rid
    WHERE x.tagid=(SELECT tagid FROM tag WHERE tagname='branch') AND x.tagtype>0 AND x.value='main'
    AND e.type='ci' AND e.mtime > julianday('now', '-364 days')"] 0 0]
set activity [dict get $tkbranches::branches(main) activity]
check "main's activity: $activity" {[llength $activity] == 13 && [tcl::mathop::+ {*}$activity] == $recent}
if {"activity" in [$bt cget -displaycolumns]} {
    $bt see main; update
    if {[catch {$bt tag cell has {}}]} {
        check "Tk 8.6: in characters: [$bt set main activity]" {[string length [$bt set main activity]] == 7}
    } else {
        check "Tk 9: an image" {[llength [lsearch -all -glob [$bt tag names] activity:*]] > 0 && [$bt set main activity] eq ""}
    }
}

# A ticket report by a column.
tktaalik::show tickets; update
ticketreports::window; update
.reports.main.list selection clear 0 end
.reports.main.list selection set 0
ticketreports::choose; update
set columns [.reports.main.out.top.chart cget -values]
# Only the columns worth it: not the ids, the titles, the times.
set heads [lmap c [.reports.main.out.t cget -columns] {.reports.main.out.t heading $c -text}]
puts "  report columns: $heads; chart by: [lrange $columns 1 end]"
check "chart by: not ids, titles, times" {"#" ni $columns && [lsearch -glob $columns *Change*] < 0
    && [lsearch -glob $columns Summary] < 0 && [lsearch -glob $columns Title] < 0}
if {[llength $ticketreports::rows] && [llength $columns] > 1} {
    set column [lindex $columns end]
    .reports.main.out.top.chart set $column
    ticketreports::chooseChart; update
    set w .reports.main.out.chart
    check "a report by [list $column]: [total $w] of [llength $ticketreports::rows] rows" {[winfo ismapped $w] && ![winfo ismapped .reports.main.out.t]
        && ([total $w] == [llength $ticketreports::rows] || [llength [dict get $charts::spec($w) -categories]] == 30)}
    set value [lindex [dict get $charts::spec($w) -keys] 0]
    ticketreports::chartFilter $value Rows; update
    check "filtered by it: [list $ticketreports::filter]" {[string match "\"$column\" = *" $ticketreports::filter]
        && [winfo ismapped .reports.main.out.t] && [llength $ticketreports::rows] == [lindex [dict get $charts::spec($w) -series] 1 0]}
} else {
    puts "(no ticket report here: not checked)"
}
# A report that counts: nothing to chart by.
set counting [lsearch -regexp [lmap rn [dict keys $ticketreports::reports] {
    lindex [dict get $ticketreports::reports $rn] 2 }] {(?i)group\s+by}]
if {$counting >= 0} {
    .reports.main.list selection clear 0 end
    .reports.main.list selection set $counting
    ticketreports::choose; update
    check "a report that counts: [.reports.main.list get $counting]" {[.reports.main.out.top.chart cget -state] eq "disabled"
        && [llength [.reports.main.out.top.chart cget -values]] == 1 && [winfo ismapped .reports.main.out.t]}
}
done
