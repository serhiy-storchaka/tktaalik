# The ticket reports: the repository's reports, run with $login and the
# row colours, a filter, the ticket of a row.
source [file join [file dirname [info script]] common.tcl]
set ::browsed {}
tktaalik::main tickets [list $T(repo)]
update
set m .tickets.menu.ticket
set i -1
for {set k 0} {$k <= [$m index end]} {incr k} {
    if {[$m type $k] eq "command" && [$m entrycget $k -label] eq "Reports\u2026"} { set i $k }
}
check "in the Ticket menu" {$i >= 0}
.tickets.menu.ticket invoke $i; update
set n [lindex [fossil::sql $T(repo) "SELECT count(*) FROM reportfmt"] 0 0]
set l .reports.main.list
check "the reports: [$l size] of $n" {[$l size] == $n && $n > 0}
set t .reports.main.out.t
proc pick {rn} {
    set k [lsearch -glob [$::l get 0 end] "$rn. *"]
    $::l selection clear 0 end; $::l selection set $k
    event generate $::l <<ListboxSelect>>; update
}
# All Open: as many rows as "fossil ticket show" gives, with colours.
pick 4
set cli [expr {[llength [split [string trim [exec fossil ticket show 4 -q -R $T(repo)]] \n]] - 1}]
check "All Open: [llength [$t children {}]] rows, the CLI $cli" {[llength [$t children {}]] == $cli && $cli > 0}
set heads [lmap c [$t cget -columns] {$t heading $c -text}]
check "columns: $heads (no bgcolor)" {"#" in $heads && "bgcolor" ni $heads}
# A filter.
set ticketreports::filter {"Type" = 'Patch'}
ticketreports::run; update
set k [lsearch -exact $heads Type]
set types [lsort -unique [lmap r [$t children {}] {lindex [$t item $r -values] $k}]]
check "filtered: $types" {$types eq "Patch"}
set ticketreports::filter {nosuchcolumn = 1}
ticketreports::run; update
check "a bad filter: $ticketreports::status" {[string match "The report failed*" $ticketreports::status]}
set ticketreports::filter ""
# Row colours (bgcolor) of All Tickets.
pick 1
check "rows coloured" {[string match bg#* [lindex [$t item [lindex [$t children {}] 0] -tags] 0]]}
# A report for the user ($login): runs (the CLI prints nothing).
pick 15
check "\$login report runs: $ticketreports::status" {[string match "*rows*" $ticketreports::status]}
# The ticket of a row.
pick 4
set r [lindex [$t children {}] 0]
set prefix [lindex [$t item $r -values] [lsearch -exact $heads #]]
ticketreports::openTicket $r; update
check "ticket $prefix in the Tickets tab" {[string match $prefix* $tktsearch::shownTicket] && $tktaalik::active eq "tickets"}
ticketreports::browse
check "browse: [lindex $::browsed end]" {[string match */rptview/4 [lindex $::browsed end]]}
done
