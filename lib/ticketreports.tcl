# The ticket reports of the repository (the Reports window of the Tickets
# tab): the reports stored in it ("fossil ticket ls reports"), each run as
# "fossil ticket show" runs it, with an optional filter (an SQL condition
# on the report's columns, as TICKETFILTER).  The report's SQL is run here,
# read-only, rather than by "fossil ticket show": that leaves out the row
# colours (the "bgcolor" column) and fails on reports for the user ($login,
# here the default user, as the web pages do for the one logged in).
# Columns whose name starts with "_" are shown under the table, for the
# row selected, as on the web pages.  "Chart by" shows how many rows have
# each value of a column instead (lib/charts.tcl), for the columns where
# that tells something; a click on a bar filters the report by it.
# Nothing is changed.

namespace eval ticketreports {
    variable repo ""
    variable reports {}       ;# rn -> {title owner sql}
    variable report ""        ;# the rn shown
    variable filter ""
    variable status ""
    variable columns {}       ;# the columns of the report shown
    variable rows {}          ;# its rows
    variable details {}       ;# row id -> {name value} of the "_" columns
    variable chartBy ""       ;# the column of the chart, "" for the table
}

proc ticketreports::window {} {
    variable repo
    if {[tktaalik::dialogWindow .reports "Ticket reports"]} { build }
    if {$repo ne $::tickets::repo} { setRepository }
    focus .reports.main.list
}

proc ticketreports::build {} {
    ui::size .reports 125 30
    ttk::panedwindow .reports.main -orient horizontal
    ui::splitByWeights .reports.main
    listbox .reports.main.list -width 34 -exportselection 0 -activestyle none
    .reports.main add .reports.main.list -weight 1
    set f .reports.main.out
    ttk::frame $f
    ttk::frame $f.top -padding {0 0 0 4}
    ttk::label $f.top.l -text "Filter:"
    ttk::entry $f.top.filter -textvariable ticketreports::filter -font TkFixedFont
    icons::tooltip $f.top.filter "An SQL condition on the columns of the report,\
        \ne.g. \"Status\" = 'Open' (Return to run)"
    ttk::button $f.top.run -text Run -command ticketreports::run
    ttk::label $f.top.cl -text "Chart by:"
    ttk::combobox $f.top.chart -state readonly -width 16 -values [list "(the table)"]
    $f.top.chart set "(the table)"
    bind $f.top.chart <<ComboboxSelected>> ticketreports::chooseChart
    icons::tooltip $f.top.chart "How many rows have each value of a column:\na click on a bar filters the report by it"
    pack $f.top.l -side left
    pack $f.top.run -side right -padx {4 0}
    pack $f.top.chart $f.top.cl -side right -padx {8 0}
    pack $f.top.filter -side left -fill x -expand 1 -padx {4 0}
    ttk::treeview $f.t -show headings -selectmode browse \
        -yscrollcommand [list $f.y set] -xscrollcommand [list $f.x set]
    ttk::scrollbar $f.y -command [list $f.t yview]
    ttk::scrollbar $f.x -orient horizontal -command [list $f.t xview]
    text $f.more -height 5 -wrap word -padx 6 -pady 4 -font TkTextFont -state disabled
    grid $f.top - -sticky ew
    grid $f.t $f.y -sticky news
    grid $f.x -sticky ew
    charts::message $f.chart ""
    grid $f.chart -row 1 -column 0 -columnspan 2 -rowspan 2 -sticky news
    grid remove $f.chart
    grid $f.more - -sticky ew -pady {4 0}
    grid columnconfigure $f 0 -weight 1
    grid rowconfigure $f 1 -weight 1
    .reports.main add $f -weight 4
    ttk::frame .reports.b -padding 6
    ttk::label .reports.b.status -textvariable ticketreports::status -anchor w
    ttk::button .reports.b.browse -text "Open in browser" -command ticketreports::browse
    ttk::button .reports.b.save -text "Save as\u2026" -command ticketreports::save
    ttk::button .reports.b.close -text Close -command {wm withdraw .reports}
    pack .reports.b.close .reports.b.browse .reports.b.save -side right -padx {4 0}
    pack .reports.b.status -side left -fill x -expand 1
    pack .reports.b -side bottom -fill x
    pack .reports.main -fill both -expand 1 -padx 6 -pady {6 0}
    bind .reports.main.list <<ListboxSelect>> ticketreports::choose
    bind $f.top.filter <Return> ticketreports::run
    bind $f.t <<TreeviewSelect>> ticketreports::showMore
    bind $f.t <Double-1> {
        if {[.reports.main.out.t identify region %x %y] eq "cell"} {
            ticketreports::openTicket [.reports.main.out.t identify item %x %y]
        }
    }
    bind .reports <F5> ticketreports::run
    popup::attach .reports.main.list ticketreports::listMenu
    popup::attach .reports.main.out.t ticketreports::rowMenu
    # (Ctrl+C: the rows, their cells separated by tabs.)
    popup::copyKey .reports.main.out.t {::apply {{item} {
        join [.reports.main.out.t item $item -values] \t
    }}}
}

# The reports of the repository of the Tickets tab.
proc ticketreports::setRepository {} {
    variable repo $::tickets::repo
    variable reports {}
    variable report ""
    variable status
    wm title .reports "Ticket reports \u2014 [file rootname [file tail $repo]]"
    try {
        foreach row [fossil::sql $repo "SELECT rn, [fossil::outcol title],\
                [fossil::outcol "coalesce(owner,'')"], [fossil::outcol sqlcode]\
                FROM reportfmt ORDER BY rn"] {
            lassign $row rn title owner sql
            dict set reports $rn [list $title $owner $sql]
        }
    } trap {FOSSIL DB} msg {
        set status "Cannot read the reports: $msg"
    }
    set l .reports.main.list
    $l delete 0 end
    dict for {rn r} $reports { $l insert end "$rn. [lindex $r 0]" }
    clear
    if {[dict size $reports]} {
        set status "[dict size $reports] reports"
        $l selection set 0
        choose
    } elseif {![info exists msg]} {
        set status "No ticket reports in this repository"
    }
}

proc ticketreports::clear {} {
    set f .reports.main.out
    $f.t delete [$f.t children {}]
    $f.t configure -columns {}
    $f.more configure -state normal
    $f.more delete 1.0 end
    $f.more configure -state disabled
}

proc ticketreports::choose {} {
    variable reports
    variable report
    set i [lindex [.reports.main.list curselection] 0]
    if {$i eq ""} return
    set report [lindex [dict keys $reports] $i]
    run
}

# The report's SQL as the web pages run it: $login is the user.
proc ticketreports::query {sql} {
    variable filter
    set me [if {[info exists ::tickets::me]} {set ::tickets::me}]
    regsub -all {\$login\M} $sql [fossil::sqlstr $me] sql
    set sql [string trimright [string trim $sql] ";"]
    if {[string trim $filter] ne ""} {
        # (As "fossil ticket show" applies TICKETFILTER.)
        set sql "SELECT * FROM ($sql) WHERE [string trim $filter]"
    }
    return $sql
}

# Run the query with the column names: {names rows}.  (Kept as it is: the
# reports have comments and line breaks.)
proc ticketreports::sqlWithNames {sql} {
    variable repo
    set script "[fossil::sqlMode]\n.headers on\n$sql\n;\n"
    set chan [fossil::pipe [list sql -R $repo --readonly 2>@1] r+]
    fconfigure $chan -encoding utf-8 -translation lf
    puts -nonewline $chan $script
    chan close $chan write
    set out [read $chan]
    try {
        close $chan
    } on error msg {
        throw {FOSSIL DB} [string trim [lindex [split "$out\n$msg" \n] 0]]
    }
    # (fossil sql reports an error in the query on its output, and exits 0.)
    if {[regexp {^(?:Parse|Runtime) error[^\n]*|^Error:[^\n]*} $out msg]} {
        throw {FOSSIL DB} $msg
    }
    set rows [lmap row [split [string trimright $out \x1e] \x1e] { split $row \x1f }]
    if {![llength $rows]} { return {{} {}} }
    list [lindex $rows 0] [lrange $rows 1 end]
}

proc ticketreports::run {} {
    variable reports
    variable report
    variable status
    variable details
    if {$report eq "" || ![dict exists $reports $report]} return
    clear
    set details {}
    lassign [dict get $reports $report] title owner sql
    try {
        lassign [sqlWithNames [query $sql]] names rows
    } trap {FOSSIL DB} msg {
        set status "The report failed: $msg"
        set ::ticketreports::columns {}
        set ::ticketreports::rows {}
        return
    }
    # (Kept: Save as... writes them.)
    set ::ticketreports::columns $names
    set ::ticketreports::rows $rows
    # The shown columns; bgcolor colours the row, "_" ones go below.
    set shown {}
    set index {}
    foreach name $names {
        if {$name eq "bgcolor" || [string match _* $name]} continue
        lappend shown c[llength $shown]
        lappend index [lsearch -exact $names $name]
    }
    set t .reports.main.out.t
    $t configure -columns $shown
    set char [font measure TkDefaultFont 0]
    set i 0
    foreach c $shown {
        set name [lindex $names [lindex $index $i]]
        $t heading $c -text $name -anchor w
        # As wide as the widest of the first rows, within reason.
        set width [string length $name]
        foreach row [lrange $rows 0 200] {
            set width [expr {max($width, [string length [lindex $row [lindex $index $i]]])}]
        }
        $t column $c -width [expr {min($width + 2, 60) * $char}] -stretch 0
        incr i
    }
    if {[llength $shown]} { $t column [lindex $shown end] -stretch 1 }
    set bg [lsearch -exact $names bgcolor]
    set n 0
    foreach row $rows {
        set id r[incr n]
        set tags {}
        if {$bg >= 0} {
            set colour [lindex $row $bg]
            if {[regexp {^#[0-9a-fA-F]{3,6}$} $colour] || ($colour ne "" && ![catch {winfo rgb . $colour}])} {
                set tag bg$colour
                $t tag configure $tag -background $colour
                lappend tags $tag
            }
        }
        $t insert {} end -id $id -tags $tags -values [lmap k $index { lindex $row $k }]
        set more {}
        foreach name $names value $row {
            if {[string match _* $name] && $value ne ""} { lappend more [string range $name 1 end] $value }
        }
        if {[llength $more]} { dict set details $id $more }
    }
    set status "$title: [llength $rows] rows"
    if {$owner ne ""} { append status " (by $owner)" }
    if {[lsearch -exact $names #] >= 0} { append status "; double-click: the ticket" }
    # (A report that counts, GROUP BY: its rows are already a count each.)
    set chartable [lmap c $shown {
        set name [$t heading $c -text]
        if {[regexp -nocase {\mgroup\s+by\M} $sql] || ![chartable [lsearch -exact $names $name]]} continue
        set name
    }]
    .reports.main.out.top.chart configure -values [list "(the table)" {*}$chartable] \
        -state [if {[llength $chartable]} {string cat readonly} else {string cat disabled}]
    showChart
}

# Whether the column I is worth a chart of the rows by its values: some
# values, each in several rows (not the ids, the titles); not one value
# for all (a report of open bugs by status or type); not dates; numbers
# only as levels (priorities 1 to 9), not the counts of a report that
# counts.
proc ticketreports::chartable {i} {
    variable rows
    set n [llength $rows]
    set counts {}
    set dates 0
    set numbers 0
    foreach row $rows {
        set v [lindex $row $i]
        dict incr counts $v
        if {[regexp {^\d{4}-\d\d-\d\d} $v]} { incr dates }
        if {[string is double -strict $v]} { incr numbers }
    }
    set distinct [dict size $counts]
    expr {$distinct >= 2 && $distinct <= 100 && $distinct * 2 <= $n
        && $dates * 2 < $n && ($numbers * 2 < $n || $distinct <= 10)}
}

proc ticketreports::chooseChart {} {
    variable chartBy
    set chosen [.reports.main.out.top.chart get]
    set chartBy [if {$chosen ne "(the table)"} {set chosen}]
    showChart
}

# The chart of the column chosen instead of the table: the rows by its
# values (the 30 most frequent).
proc ticketreports::showChart {} {
    variable chartBy
    variable columns
    variable rows
    set f .reports.main.out
    set i [lsearch -exact $columns $chartBy]
    if {$chartBy eq "" || $chartBy ni [$f.top.chart cget -values]} {
        set chartBy ""
        $f.top.chart set "(the table)"
        grid remove $f.chart
        grid $f.t $f.y
        grid $f.x
        return
    }
    $f.top.chart set $chartBy
    set counts {}
    foreach row $rows { dict incr counts [lindex $row $i] }
    set sorted [lrange [lsort -stride 2 -index 1 -integer -decreasing $counts] 0 59]
    grid remove $f.t $f.y $f.x
    grid $f.chart
    set title "Rows by $chartBy"
    if {[dict size $counts] > 30} { append title " (the 30 most frequent of [dict size $counts])" }
    charts::bars $f.chart -title $title -horizontal 1 \
        -categories [lmap {v n} $sorted { if {$v eq ""} { string cat (none) } else { set v } }] \
        -keys [dict keys $sorted] -series [list Rows [dict values $sorted]] \
        -command ticketreports::chartFilter -message "No rows."
}

# A bar of the chart: the report filtered by its value, as a table.
proc ticketreports::chartFilter {value series} {
    variable chartBy
    variable filter
    set column [string map {{"} {""}} $chartBy]
    set filter "\"$column\" = '[string map {' ''} $value]'"
    set chartBy ""
    run
}

proc ticketreports::showMore {} {
    variable details
    set f .reports.main.out
    set id [lindex [$f.t selection] 0]
    $f.more configure -state normal
    $f.more delete 1.0 end
    if {[dict exists $details $id]} {
        foreach {name value} [dict get $details $id] { $f.more insert end "$name: $value\n" }
    }
    $f.more configure -state disabled
}

# The ticket of a row (its "#" column, a prefix of the id), in the Tickets tab.
proc ticketreports::openTicket {id} {
    variable repo
    set t .reports.main.out.t
    set k [lsearch -exact [lmap c [$t cget -columns] { $t heading $c -text }] #]
    if {$k < 0} return
    set prefix [string tolower [lindex [$t item $id -values] $k]]
    if {![regexp {^[0-9a-f]{4,64}$} $prefix]} return
    set uuid [lindex [fossil::sql $repo "SELECT tkt_uuid FROM ticket WHERE tkt_uuid GLOB '$prefix*'\
        ORDER BY tkt_mtime DESC LIMIT 1"] 0 0]
    if {$uuid eq ""} return
    tktaalik::show tickets
    tktsearch::showTicket $uuid
}

proc ticketreports::browse {} {
    variable report
    if {$report ne ""} { tktsearch::openUrl rptview/$report }
}

# The context menus: of a report, of a row of its results.
proc ticketreports::listMenu {m index} {
    $m add command -label Run -command ticketreports::run
    popup::button $m .reports.b.browse
}

proc ticketreports::rowMenu {m item} {
    set t .reports.main.out.t
    set heads [lmap c [$t cget -columns] { $t heading $c -text }]
    if {"#" in $heads} {
        $m add command -label "Show the ticket" -command [list ticketreports::openTicket $item]
    }
    # The column clicked: filter by its value.
    set c $::popup::column
    if {$c ne "" && $c in [$t cget -columns]} {
        set name [$t heading $c -text]
        set value [$t set $item $c]
        set cond "\"[string map {\" \"\"} $name]\" = '[string map {' ''} $value]'"
        $m add command -label "Only rows with $name = $value" \
            -command [list apply {{cond} { set ::ticketreports::filter $cond; ticketreports::run }} $cond]
        popup::separator $m
        popup::copy $m "Copy $name" $value
    }
    popup::default $m "Show the ticket"
}

# The results shown (all their columns, the hidden ones too) as a file:
# tab-separated (.tsv, what "fossil ticket show" writes) or CSV.
proc ticketreports::save {} {
    variable reports
    variable report
    variable columns
    variable rows
    if {$report eq "" || ![info exists rows] || ![llength $columns]} return
    set name [regsub -all {[^A-Za-z0-9._-]+} [lindex [dict get $reports $report] 0] -]
    set file [tk_getSaveFile -parent .reports -title "Save the report" -initialfile $name.tsv \
        -filetypes {{{Tab-separated} {.tsv}} {{CSV} {.csv}} {{All files} *}}]
    if {$file eq ""} return
    set csv [string equal -nocase [file extension $file] .csv]
    set f [open $file w]
    fconfigure $f -encoding utf-8 -translation [expr {$csv ? "crlf" : "lf"}]
    foreach row [concat [list $columns] $rows] {
        if {$csv} {
            puts $f [join [lmap v $row {
                if {[regexp {[",\n\r]} $v]} {string cat "\"[string map {\" \"\"} $v]\""} else {set v}
            }] ,]
        } else {
            puts $f [join [lmap v $row { string map {\t " " \n " " \r ""} $v }] \t]
        }
    }
    close $f
    variable status
    set status "Saved [llength $rows] rows into [file tail $file]"
}
