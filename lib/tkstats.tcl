# The Statistics window of tktaalik (Repository menu): charts of what the
# repository holds (lib/charts.tcl), in tabs.  Activity: the events per
# period by kind, a calendar of the last year, weekday by hour.
# Contributors: who made the check-ins, how many did per period, and the
# events of a user chosen per period.
# Tickets: opened and closed per period, how many were open, by a field,
# the age of the open ones.  Forum: threads and replies, who posts.
# Size: what is stored per period and in all, the artifacts by kind, the
# largest files.  For a period (all, the last years...), counted by year,
# month, week or day, in UTC as the Timeline's date: terms.  A click on a
# bar or a day searches it in the Timeline or Tickets tab.  Only reads.

namespace eval tkstats {
    variable repo ""
    variable period all         ;# a key of $periods
    variable by auto            ;# year month week day, or auto by the period
    variable status ""
    variable field type         ;# the ticket field of the Tickets tab
    variable openOnly 1         ;# the field of open tickets only
    variable person ""          ;# the user of "Activity of" (Contributors)
    variable drawn {}           ;# the tabs drawn for the repository and period
    variable periods {
        all  "All time"         ""
        10y  "The last 10 years" "-10 years"
        5y   "The last 5 years"  "-5 years"
        1y   "The last year"     "-1 year"
        90d  "The last 90 days"  "-90 days"
    }
    variable units {auto Automatic year Year month Month week Week day Day}
    variable kinds {
        ci Check-ins ci  t Tickets ticket  w Wiki wiki  e Technotes technote
        f Forum forum  g Tags tag
    }
    variable fields {
        type Type type  status Status status  subsystem Subsystem subsystem
        priority Priority priority  severity Severity severity
        foundin "Found in" version  resolution Resolution resolution
        assignee Assignee assignee
    }
}

proc tkstats::window {} {
    if {[tktaalik::dialogWindow .stats Statistics]} { build }
    setRepository $::tktaalik::repo $::tktaalik::root
}

proc tkstats::build {} {
    variable periods
    variable units
    variable fields
    ui::size .stats 130 44
    ttk::frame .stats.top -padding {8 6 8 2}
    ttk::label .stats.top.pl -text Period:
    ttk::combobox .stats.top.p -state readonly -width 18 \
        -values [dict values [dict map {k v} [Triples $periods] {lindex $v 0}]]
    ttk::label .stats.top.bl -text "Counted by:"
    ttk::combobox .stats.top.b -state readonly -width 10 -values [dict values $units]
    ttk::button .stats.top.refresh -text Refresh -command tkstats::refresh
    pack .stats.top.pl .stats.top.p -side left -padx {0 4}
    pack .stats.top.bl -side left -padx {8 4}
    pack .stats.top.b -side left
    pack .stats.top.refresh -side right
    bind .stats.top.p <<ComboboxSelected>> {tkstats::choose period}
    bind .stats.top.b <<ComboboxSelected>> {tkstats::choose by}
    icons::tooltip .stats.top.b "The length of a bar: a year, month, week (from Monday) or day,\nin UTC as the Timeline's date: searches"

    ttk::notebook .stats.nb
    ttk::notebook::enableTraversal .stats.nb
    foreach {tab label} {activity Activity people Contributors tickets Tickets forum Forum size Size} {
        ttk::frame .stats.nb.$tab -padding 4
        .stats.nb add .stats.nb.$tab -text $label -underline 0
    }
    set a .stats.nb.activity
    charts::message $a.time ""
    charts::message $a.cal ""
    charts::message $a.hours ""
    grid $a.time - -sticky news
    grid $a.cal $a.hours -sticky news
    set p .stats.nb.people
    charts::message $p.top ""
    charts::message $p.count ""
    ttk::frame $p.userbar
    ttk::label $p.userbar.l -text "Activity of"
    ttk::combobox $p.userbar.u -state readonly -width 24 -textvariable tkstats::person
    pack $p.userbar.l $p.userbar.u -side left -padx {0 6}
    bind $p.userbar.u <<ComboboxSelected>> tkstats::DrawPerson
    icons::tooltip $p.userbar.u "Whose events, per period below (or click a user above)"
    charts::message $p.user ""
    grid $p.top $p.count -sticky news
    grid $p.userbar - -sticky w -pady {6 0}
    grid $p.user - -sticky news
    set t .stats.nb.tickets
    charts::message $t.flow ""
    charts::message $t.backlog ""
    ttk::frame $t.fieldbar
    ttk::label $t.fieldbar.l -text "Tickets by"
    ttk::combobox $t.fieldbar.f -state readonly -width 12 \
        -values [dict values [dict map {k v} [Triples $fields] {lindex $v 0}]]
    ttk::checkbutton $t.fieldbar.open -text "Open only" -variable tkstats::openOnly \
        -command {tkstats::draw tickets 1}
    pack $t.fieldbar.l $t.fieldbar.f $t.fieldbar.open -side left -padx {0 6}
    bind $t.fieldbar.f <<ComboboxSelected>> {tkstats::choose field}
    charts::message $t.field ""
    charts::message $t.age ""
    grid $t.flow $t.backlog -sticky news
    grid $t.fieldbar x -sticky w -pady {6 0}
    grid $t.field $t.age -sticky news
    set f .stats.nb.forum
    charts::message $f.posts ""
    charts::message $f.posters ""
    grid $f.posts $f.posters -sticky news
    set s .stats.nb.size
    charts::message $s.growth ""
    charts::message $s.total ""
    charts::message $s.kinds ""
    charts::message $s.largest ""
    grid $s.growth $s.total -sticky news
    grid $s.kinds $s.largest -sticky news
    foreach w [list $a $p $t $f $s] {
        grid columnconfigure $w {0 1} -weight 1 -uniform c
    }
    grid rowconfigure $a 0 -weight 3
    grid rowconfigure $a 1 -weight 2
    grid rowconfigure $p 0 -weight 3
    grid rowconfigure $p 2 -weight 2
    grid rowconfigure $t {0 2} -weight 1
    grid rowconfigure $f 0 -weight 1
    grid rowconfigure $s {0 1} -weight 1

    ttk::frame .stats.bottom -padding {8 2 8 6}
    ttk::label .stats.bottom.status -textvariable tkstats::status -anchor w
    ttk::button .stats.bottom.close -text Close -command {wm withdraw .stats}
    pack .stats.bottom.close -side right
    pack .stats.bottom.status -side left -fill x -expand 1
    pack .stats.top -fill x
    pack .stats.bottom -side bottom -fill x
    pack .stats.nb -fill both -expand 1 -padx 8
    bind .stats.nb <<NotebookTabChanged>> {tkstats::draw [tkstats::currentTab]}
    bind .stats <F5> tkstats::refresh
    ShowChoices
}

# {KEY A B KEY A B ...} as a dict KEY -> {A B}.
proc tkstats::Triples {list} {
    set d {}
    foreach {k a b} $list { dict set d $k [list $a $b] }
    return $d
}

proc tkstats::ShowChoices {} {
    variable periods
    variable units
    variable fields
    variable period
    variable by
    variable field
    .stats.top.p set [lindex [dict get [Triples $periods] $period] 0]
    .stats.top.b set [dict get $units $by]
    .stats.nb.tickets.fieldbar.f set [lindex [dict get [Triples $fields] $field] 0]
}

# A choice in a combobox: the period, the length of a bar, the field.
proc tkstats::choose {what} {
    variable periods
    variable units
    variable fields
    switch -- $what {
        period {
            set label [.stats.top.p get]
            dict for {k v} [Triples $periods] { if {[lindex $v 0] eq $label} { set ::tkstats::period $k } }
            refresh
        }
        by {
            set label [.stats.top.b get]
            dict for {k v} $units { if {$v eq $label} { set ::tkstats::by $k } }
            refresh
        }
        field {
            set label [.stats.nb.tickets.fieldbar.f get]
            dict for {k v} [Triples $fields] { if {[lindex $v 0] eq $label} { set ::tkstats::field $k } }
            draw tickets 1
        }
    }
}

proc tkstats::setRepository {path newRoot} {
    variable repo $path
    if {![winfo exists .stats]} return
    wm title .stats "Statistics \u2014 [file rootname [file tail $repo]]"
    refresh
}

proc tkstats::refresh {} {
    variable drawn {}
    if {![winfo exists .stats]} return
    draw [currentTab]
}

proc tkstats::currentTab {} {
    lindex [split [.stats.nb select] .] end
}

proc tkstats::sql {statement} {
    variable repo
    fossil::sql $repo $statement
}

# ------------------------------------------------------------- periods

# The condition on a time column for the period ("1" for all time), and
# the first day of it ("" for all time).
proc tkstats::since {column} {
    variable periods
    variable period
    set modifier [lindex [dict get [Triples $periods] $period] 1]
    if {$modifier eq ""} { return 1 }
    return "$column >= julianday('now', '$modifier')"
}

proc tkstats::firstDay {} {
    variable periods
    variable period
    set modifier [lindex [dict get [Triples $periods] $period] 1]
    if {$modifier eq ""} { return "" }
    lindex [sql "SELECT date('now', '$modifier')"] 0 0
}

# The length of a bar: as chosen, or by the length of the period.
proc tkstats::unit {} {
    variable by
    variable period
    if {$by ne "auto"} { return $by }
    switch -- $period {
        all - 10y { return year }
        5y { return month }
        1y { return week }
        default { return day }
    }
}

# The period of a time column as SQL: 2026, 2026-10, the Monday of the
# week (2026-10-26), the day.
proc tkstats::periodOf {column} {
    switch -- [unit] {
        year  { return "strftime('%Y', $column)" }
        month { return "strftime('%Y-%m', $column)" }
        week  { return "date($column, '-6 days', 'weekday 1')" }
        day   { return "date($column)" }
    }
}

# Every period from FIRST to LAST (as periodOf gives them), none left out.
proc tkstats::periodsBetween {first last} {
    if {$first eq "" || $last eq ""} { return {} }
    set list {}
    switch -- [unit] {
        year {
            for {set y $first} {$y <= $last} {incr y} { lappend list $y }
        }
        month {
            scan $first %d-%d y m
            scan $last %d-%d ly lm
            while {$y < $ly || ($y == $ly && $m <= $lm)} {
                lappend list [format %04d-%02d $y $m]
                if {[incr m] > 12} { set m 1; incr y }
            }
        }
        week - day {
            set step [expr {[unit] eq "week" ? 7 : 1}]
            set t [clock scan $first -format %Y-%m-%d -timezone :UTC]
            set end [clock scan $last -format %Y-%m-%d -timezone :UTC]
            while {$t <= $end} {
                lappend list [clock format $t -format %Y-%m-%d -timezone :UTC]
                set t [clock add $t $step days -timezone :UTC]
            }
        }
    }
    return $list
}

# The period KEY as a date: search term value (a week: its days).
proc tkstats::dateTerm {key} {
    if {[unit] ne "week"} { return $key }
    set t [clock scan $key -format %Y-%m-%d -timezone :UTC]
    return "$key..[clock format [clock add $t 6 days -timezone :UTC] -format %Y-%m-%d -timezone :UTC]"
}

# Values per period, PERIODS long, from {PERIOD VALUE ...} rows; 0 where
# there are none.
proc tkstats::along {periods rows} {
    set d {}
    foreach row $rows { dict set d [lindex $row 0] [lindex $row end] }
    lmap p $periods { if {[dict exists $d $p]} { dict get $d $p } else { expr 0 } }
}

# -------------------------------------------------------------- drawing

# Draw the charts of TAB unless drawn for this repository and period
# (or AGAIN).
proc tkstats::draw {tab {again 0}} {
    variable drawn
    variable repo
    variable status
    if {$repo eq "" || (!$again && $tab in $drawn)} return
    set busy [ui::busyHold .stats]
    try {
        Draw[string totitle $tab]
        lappend drawn $tab
        set status [Summary]
    } trap {FOSSIL DB} msg {
        set status "Database error: $msg"
    } finally {
        ui::busyRelease $busy
    }
}

proc tkstats::Summary {} {
    lassign [lindex [sql "SELECT count(*), date(min(mtime)), date(max(mtime)) FROM event"] 0] n first last
    if {!$n} { return "No events." }
    return "[charts::number $n] events from $first to $last (dates in UTC)"
}

# The events of the period (and of WHERE) per period, by kind: {PERIODS
# {LABEL VALUES ...}}, from the first of them to now.
proc tkstats::byKind {{where 1}} {
    variable kinds
    set rows [sql "SELECT [periodOf mtime], type, count(*) FROM event\
        WHERE [since mtime] AND $where GROUP BY 1, 2"]
    set first [lindex [sql "SELECT [periodOf mtime] FROM event WHERE [since mtime] AND $where\
        ORDER BY mtime LIMIT 1"] 0 0]
    set periods [periodsBetween $first [lindex [sql "SELECT [periodOf "'now'"]"] 0 0]]
    set series {}
    foreach {type label kind} $kinds {
        set values [along $periods [lmap r $rows { if {[lindex $r 1] ne $type} continue; set r }]]
        if {[tcl::mathfunc::max 0 {*}$values] > 0} { lappend series $label $values }
    }
    list $periods $series
}

proc tkstats::DrawActivity {} {
    set a .stats.nb.activity
    lassign [byKind] periods series
    charts::bars $a.time -title "Events per [unit]" -categories $periods -series $series \
        -command tkstats::showEvents -message "No events in this period."

    # The last year, a column a week (from Monday), a row a weekday.
    set start [lindex [sql "SELECT date('now', '-364 days', '-6 days', 'weekday 1')"] 0 0]
    set counts {}
    foreach row [sql "SELECT date(mtime), count(*) FROM event WHERE mtime >= julianday('$start') GROUP BY 1"] {
        dict set counts {*}$row
    }
    set t [clock scan $start -format %Y-%m-%d -timezone :UTC]
    set today [clock format [clock seconds] -format %Y-%m-%d -timezone :UTC]
    set cells {}; set columns {}; set i 0
    while {1} {
        set day [clock format $t -format %Y-%m-%d -timezone :UTC]
        if {[string compare $day $today] > 0} break
        set column [expr {$i / 7}]
        if {$i % 7 == 0} {
            set dom [clock format $t -format %e -timezone :UTC]
            lappend columns [if {$dom <= 7} { clock format $t -format %b -timezone :UTC }]
        }
        set n [if {[dict exists $counts $day]} {dict get $counts $day} else {expr 0}]
        lappend cells [expr {$i % 7}] $column $n $day \
            "[clock format $t -format {%a %Y-%m-%d} -timezone :UTC]: [charts::number $n] event[expr {$n == 1 ? "" : "s"}]"
        set t [clock add $t 1 day -timezone :UTC]
        incr i
    }
    charts::grid $a.cal -title "The last year" -rows {Mon Tue Wed Thu Fri Sat Sun} \
        -columns $columns -cells $cells -command tkstats::showDay

    # Weekday by hour (UTC).
    set cells {}
    set days {Sunday Monday Tuesday Wednesday Thursday Friday Saturday}
    foreach row [sql "SELECT strftime('%w', mtime), strftime('%H', mtime), count(*) FROM event\
            WHERE [since mtime] GROUP BY 1, 2"] {
        lassign $row w h n
        scan $h %d h
        lappend cells [expr {($w + 6) % 7}] $h $n "" \
            [format "%s %02d:00\u2013%02d:00 UTC: %s" [lindex $days $w] $h [expr {$h + 1}] [charts::number $n]]
    }
    charts::grid $a.hours -title "Weekday by hour (UTC)" -rows {Mon Tue Wed Thu Fri Sat Sun} \
        -columns [lmap h {0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23} {
            if {$h % 3} { string cat } else { set h } }] -cells $cells \
        -message "No events in this period."
}

proc tkstats::DrawPeople {} {
    set p .stats.nb.people
    set rows [sql "SELECT [fossil::outcol {coalesce(euser, user)}], count(*) FROM event\
        WHERE type='ci' AND [since mtime] GROUP BY 1 ORDER BY 2 DESC, 1 LIMIT 25"]
    charts::bars $p.top -title "Check-ins by user" -horizontal 1 \
        -categories [lmap r $rows {lindex $r 0}] -series [list Check-ins [lmap r $rows {lindex $r 1}]] \
        -command tkstats::chooseUser -message "No check-ins in this period."
    set top [lindex $rows 0 0]
    set rows [sql "SELECT [periodOf mtime], count(DISTINCT coalesce(euser, user)) FROM event\
        WHERE type='ci' AND [since mtime] GROUP BY 1 ORDER BY 1"]
    set periods [periodsBetween [lindex $rows 0 0] [lindex [sql "SELECT [periodOf "'now'"]"] 0 0]]
    charts::bars $p.count -title "Users with check-ins per [unit]" -categories $periods \
        -series [list Users [along $periods $rows]] -command tkstats::showCheckins \
        -message "No check-ins in this period."
    # Everyone with events in the period, the most active first; the user
    # chosen before if still there, else the one with the most check-ins.
    variable person
    set users [concat {*}[sql "SELECT [fossil::outcol {coalesce(euser, user)}] FROM event\
        WHERE [since mtime] GROUP BY 1 ORDER BY count(*) DESC, 1"]]
    $p.userbar.u configure -values $users
    if {$person ni $users} {
        set person [if {$top ne ""} {set top} else {lindex $users 0}]
    }
    DrawPerson
}

# The events of the user chosen per period, by kind.
proc tkstats::DrawPerson {} {
    variable person
    set w .stats.nb.people.user
    if {$person eq ""} {
        charts::message $w "No events in this period."
        return
    }
    lassign [byKind "coalesce(euser, user)=[fossil::sqlstr $person]"] periods series
    charts::bars $w -title "Events of $person per [unit]" -categories $periods -series $series \
        -command tkstats::showPersonEvents -message "No events of $person in this period."
}

# A user's bar: their activity below.
proc tkstats::chooseUser {user series} {
    variable person $user
    DrawPerson
}

proc tkstats::ticketColumns {} {
    concat {*}[sql "SELECT name FROM pragma_table_info('ticket')"]
}

proc tkstats::DrawTickets {} {
    variable fields
    variable field
    variable openOnly
    set t .stats.nb.tickets
    set columns [ticketColumns]
    if {![llength $columns] || ![lindex [sql "SELECT count(*) FROM ticket"] 0 0]} {
        foreach c {flow backlog field age} { charts::message $t.$c "No tickets in this repository." }
        return
    }
    set closing [expr {"closedate" in $columns}]
    set now [lindex [sql "SELECT [periodOf "'now'"]"] 0 0]
    # Opened and closed per period; how many were open at the end of each
    # (counted from the first ticket, shown for the period).
    set opened [sql "SELECT [periodOf tkt_ctime], count(*) FROM ticket GROUP BY 1 ORDER BY 1"]
    set closed [if {$closing} {
        sql "SELECT [periodOf closedate], count(*) FROM ticket\
            WHERE coalesce(closedate, '')<>'' AND [::tickets::stateExpr] IN ('closed', 'deleted') GROUP BY 1"
    }]
    set all [periodsBetween [lindex $opened 0 0] $now]
    set day [firstDay]
    set from 0
    if {$day ne ""} {
        set start [lindex [sql "SELECT [periodOf julianday('$day')]"] 0 0]
        set from [lsearch -exact -sorted $all $start]
        if {$from < 0} { set from 0 }
    }
    set periods [lrange $all $from end]
    set series [list Opened [lrange [along $all $opened] $from end]]
    if {$closing} { lappend series Closed [lrange [along $all $closed] $from end] }
    charts::bars $t.flow -title "Tickets opened and closed per [unit]" -line 1 \
        -categories $periods -series $series -command tkstats::showTickets
    if {$closing} {
        set open 0
        set backlog {}
        foreach o [along $all $opened] c [along $all $closed] {
            set open [expr {$open + $o - $c}]
            lappend backlog $open
        }
        charts::bars $t.backlog -title "Tickets not closed at the end of each [unit]" -line 1 \
            -categories $periods -series [list "Not closed" [lrange $backlog $from end]]
    } else {
        charts::message $t.backlog "These tickets have no closing date (closedate)."
    }

    # By a field.
    lassign [dict get [Triples $fields] $field] label key
    if {$field ni $columns} {
        charts::message $t.field "These tickets have no $label field."
    } else {
        set where [since tkt_ctime]
        if {$openOnly} { append where " AND [::tickets::stateExpr]='open'" }
        set rows [sql "SELECT [fossil::outcol "coalesce(nullif(trim($field), ''), '')"], count(*) FROM ticket\
            WHERE $where GROUP BY 1 ORDER BY 2 DESC, 1 LIMIT 25"]
        charts::bars $t.field -title "[expr {$openOnly ? "Open tickets" : "Tickets"}] by [string tolower $label]" \
            -horizontal 1 -categories [lmap r $rows { if {[lindex $r 0] eq ""} { string cat (none) } else { lindex $r 0 } }] \
            -keys [lmap r $rows {lindex $r 0}] -series [list Tickets [lmap r $rows {lindex $r 1}]] \
            -command [list tkstats::showField $key] -message "No tickets."
    }

    # How old the open tickets are.
    set ages [list 30 "Under a month"  182 "1\u20136 months"  365 "6\u201312 months" \
        730 "1\u20132 years"  1826 "2\u20135 years"  3652 "5\u201310 years" \
        1000000 "10 years and more"]
    set cases [join [lmap {days label} $ages { string cat "WHEN age < $days THEN $days" }] " "]
    set rows [sql "SELECT CASE $cases END, count(*) FROM (SELECT julianday('now') - tkt_ctime AS age\
        FROM ticket WHERE [::tickets::stateExpr]='open') GROUP BY 1"]
    set counts {}
    foreach row $rows { dict set counts {*}$row }
    set labels {}; set values {}; set keys {}; set younger 0
    foreach {days label} $ages {
        lappend labels $label
        lappend values [if {[dict exists $counts $days]} {dict get $counts $days} else {expr 0}]
        lappend keys [list $younger $days]
        set younger $days
    }
    charts::bars $t.age -title "How long the open tickets are open" -horizontal 1 \
        -categories $labels -keys $keys \
        -series [list "Open tickets" $values] -command tkstats::showAge
}

proc tkstats::DrawForum {} {
    set f .stats.nb.forum
    if {"forumpost" ni [concat {*}[sql "SELECT name FROM sqlite_schema WHERE type='table'"]]
            || ![lindex [sql "SELECT count(*) FROM forumpost"] 0 0]} {
        charts::message $f.posts "No forum in this repository."
        charts::message $f.posters "No forum in this repository."
        return
    }
    # The first version of each post (not its edits): a new thread or a reply.
    set rows [sql "SELECT [periodOf e.mtime], p.fpid=p.froot, count(*) FROM forumpost p\
        JOIN event e ON e.objid=p.fpid WHERE p.fprev IS NULL AND [since e.mtime] GROUP BY 1, 2"]
    set periods [periodsBetween [lindex [lsort [lmap r $rows {lindex $r 0}]] 0] \
        [lindex [sql "SELECT [periodOf "'now'"]"] 0 0]]
    set threads [along $periods [lmap r $rows { if {![lindex $r 1]} continue; set r }]]
    set replies [along $periods [lmap r $rows { if {[lindex $r 1]} continue; set r }]]
    charts::bars $f.posts -title "Forum posts per [unit]" -categories $periods \
        -series [list "New threads" $threads Replies $replies] -command tkstats::showForum \
        -message "No forum posts in this period."
    set rows [sql "SELECT [fossil::outcol {coalesce(e.euser, e.user)}], count(*) FROM forumpost p\
        JOIN event e ON e.objid=p.fpid WHERE p.fprev IS NULL AND [since e.mtime]\
        GROUP BY 1 ORDER BY 2 DESC, 1 LIMIT 25"]
    charts::bars $f.posters -title "Forum posts by user" -horizontal 1 \
        -categories [lmap r $rows {lindex $r 0}] -series [list Posts [lmap r $rows {lindex $r 1}]] \
        -command tkstats::showPoster -message "No forum posts in this period."
}

proc tkstats::DrawSize {} {
    set s .stats.nb.size
    # What each period added to the repository, compressed as stored: the
    # file versions it brought first, and the artifacts of its events.
    set added [sql "SELECT p, sum(n) FROM (\
        SELECT [periodOf e.mtime] AS p, length(b.content) AS n\
            FROM (SELECT fid, min(mid) AS mid FROM mlink WHERE fid>0 GROUP BY fid) m\
            JOIN blob b ON b.rid=m.fid JOIN event e ON e.objid=m.mid\
        UNION ALL SELECT [periodOf e.mtime], length(b.content) FROM event e JOIN blob b ON b.rid=e.objid\
        ) GROUP BY p ORDER BY p"]
    set all [periodsBetween [lindex $added 0 0] [lindex [sql "SELECT [periodOf "'now'"]"] 0 0]]
    set values [along $all $added]
    set from 0
    set day [firstDay]
    if {$day ne ""} {
        set from [lsearch -exact -sorted $all [lindex [sql "SELECT [periodOf julianday('$day')]"] 0 0]]
        if {$from < 0} { set from 0 }
    }
    charts::bars $s.growth -title "Stored per [unit] (compressed)" -format charts::bytes \
        -categories [lrange $all $from end] -series [list Stored [lrange $values $from end]] \
        -message "Nothing stored in this period."
    set sum 0
    set total [lmap v $values { set sum [expr {$sum + $v}] }]
    charts::bars $s.total -title "Stored in all (compressed)" -line 1 -format charts::bytes \
        -categories [lrange $all $from end] -series [list "In all" [lrange $total $from end]] \
        -message "Nothing stored in this period."

    set tables [concat {*}[sql "SELECT name FROM sqlite_schema WHERE type='table'"]]
    set parts {
        Check-ins          "(SELECT count(*) FROM event WHERE type='ci')"
        "File versions"    "(SELECT count(DISTINCT fid) FROM mlink WHERE fid>0)"
        "Ticket changes"   "(SELECT count(*) FROM event WHERE type='t')"
        "Wiki versions"    "(SELECT count(*) FROM event WHERE type='w')"
        "Technotes"        "(SELECT count(*) FROM event WHERE type='e')"
        "Forum posts"      "(SELECT count(*) FROM event WHERE type='f')"
        "Tag changes"      "(SELECT count(*) FROM event WHERE type='g')"
    }
    if {"attachment" in $tables} { lappend parts Attachments "(SELECT count(*) FROM attachment)" }
    set counts [lindex [sql "SELECT [join [dict values $parts] {, }]"] 0]
    set labels {}; set values {}
    foreach label [dict keys $parts] n $counts {
        if {$n > 0} { lappend labels $label; lappend values $n }
    }
    charts::bars $s.kinds -title "Artifacts by kind" -horizontal 1 -categories $labels \
        -series [list Artifacts $values]

    set rows [sql "SELECT [fossil::outcol f.name], max(b.size) FROM mlink m JOIN blob b ON b.rid=m.fid\
        JOIN filename f ON f.fnid=m.fnid WHERE m.fid>0 GROUP BY f.name ORDER BY 2 DESC LIMIT 20"]
    charts::bars $s.largest -title "Largest files (their largest version)" -horizontal 1 \
        -format charts::bytes -elide middle -categories [lmap r $rows {lindex $r 0}] \
        -series [list Size [lmap r $rows {lindex $r 1}]] -command tkstats::showFile \
        -message "No files."
}

# --------------------------------------------------------------- clicks

proc tkstats::timeline {query} {
    tktaalik::navigate
    tktaalik::show timeline
    tktimeline::setQuery $query
    raise .
}

proc tkstats::tickets {query} {
    tktaalik::navigate
    tktaalik::show tickets
    tktsearch::setQuery $query
    raise .
}

# The date: term of the period ("" for all time).
proc tkstats::periodTerm {} {
    set day [firstDay]
    if {$day eq ""} { return "" }
    return "date:>=$day"
}

proc tkstats::showEvents {key series} {
    variable kinds
    set q "date:[dateTerm $key]"
    foreach {type label kind} $kinds { if {$label eq $series} { append q " kind:$kind" } }
    timeline $q
}

proc tkstats::showDay {day} {
    timeline "date:$day"
}

proc tkstats::showPersonEvents {key series} {
    variable kinds
    variable person
    set q "date:[dateTerm $key] [::tickets::termText 0 user $person]"
    foreach {type label kind} $kinds { if {$label eq $series} { append q " kind:$kind" } }
    timeline $q
}

proc tkstats::showCheckins {key series} {
    timeline "kind:ci date:[dateTerm $key]"
}

proc tkstats::showTickets {key series} {
    tickets "[expr {$series eq "Closed" ? "closed" : "created"}]:[dateTerm $key]"
}

proc tkstats::showField {key value series} {
    variable openOnly
    if {$value eq ""} {
        set q "no:$key"
    } else {
        set value [::tickets::fold $value]
        set q [::tickets::termText 0 $key $value]
    }
    if {$openOnly} { set q "is:open $q" }
    set day [firstDay]
    if {$day ne ""} { append q " created:>=$day" }
    tickets $q
}

# The open tickets opened between YOUNGER and OLDER days ago.
proc tkstats::showAge {range series} {
    lassign $range younger older
    set to [lindex [sql "SELECT date('now', '-$younger days')"] 0 0]
    set q "is:open created:<=$to"
    if {$older < 1000000} {
        append q " created:>=[lindex [sql "SELECT date('now', '-[expr {$older - 1}] days')"] 0 0]"
    }
    tickets $q
}

proc tkstats::showForum {key series} {
    timeline "kind:forum date:[dateTerm $key]"
}

proc tkstats::showPoster {user series} {
    timeline [string trim "kind:forum [::tickets::termText 0 user $user] [periodTerm]"]
}

proc tkstats::showFile {name series} {
    timeline "path:$name"
}
