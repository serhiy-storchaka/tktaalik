# Tickets: status, priority and severity icons (emoji on Tk 8.6).
source [file join [file dirname [info script]] common.tcl]
start tickets "" 1270x840
set t .tickets.main.list.t
check "columns: [$t cget -displaycolumns]" {[$t cget -displaycolumns] eq {id state priority severity title type subsystem version assignee updated}}
check "headings are icons: [lmap c {state priority severity} {$t heading $c -image}]" {[$t heading priority -image] ne "" && [$t heading severity -image] ne ""}
proc q {text} { set tktsearch::query $text; tktsearch::search; update; .tickets.main.list.t children {} }
foreach {query col expect} {
    {is:open priority:9} priority "🚨 9 Immediate"
    {is:open priority:8} priority "🔴 8"
    {is:open priority:5} priority "🔹 5 Medium"
    {is:open priority:2} priority "🔽 2"
    {is:open severity:critical} severity "🛑 Critical"
    {is:open severity:minor} severity "🔹 Minor"
    {is:open severity:cosmetic} severity "🎨 Cosmetic"
    {is:open} state "🔵 Open"
    {is:pending} state "🔶 Pending"
    {is:closed resolution:fixed} state "✔ Closed · Fixed"
    {is:closed resolution:duplicate} state "🔁 Closed · Duplicate"
    {is:closed resolution:"wont fix"} state "🚫 Closed · Wont Fix"
    {is:closed resolution:"works for me"} state "🤷 Closed · Works For Me"
} {
    set rows [q $query]
    # the value is the tooltip; the cell shows only the icon
    set cell [dict get $tktsearch::rows([lindex $rows 0]) tip:$col]
    set expect [join [lrange [split $expect] 1 end]]
    check "$query: $cell" {[llength $rows] > 0 && [string match "$expect*" $cell]}
}
# priority sorts by its number alone; severity by rank
q is:open
tablecols::sortBy $t priority desc; update
set pr [lmap i [lrange [$t children {}] 0 400] {regexp {([0-9]+)} [dict get $tktsearch::rows($i) tip:priority] -> n; set n}]
check "priority sorted by number" {$pr eq [lsort -integer -decreasing $pr]}
tablecols::sortBy $t severity desc; update
set first [dict get $tktsearch::rows([lindex [$t children {}] 0]) tip:severity]
check "severity sorted, critical first: $first" {[string match "*Critical" $first]}
check "sort state: $::tickets::sortkey $::tickets::sortdir" {$::tickets::sortkey eq "severity"}
# details header
q {id:4eef1fa86e}
set head [.tickets.main.details.head get 2.0 3.0]
check "details: $head" {[string match "*Status: *Open*Priority: *5 Medium*Severity: *M*" $head]}
# the context menu offers priority and severity separately
lassign [$t bbox [lindex [$t children {}] 0] severity] x y
tktsearch::contextMenu [expr {$x+5}] [expr {$y+5}] 300 300; update
set labels {}
for {set i 0} {$i <= [.tickets.ctx index end]} {incr i} { if {[.tickets.ctx type $i] eq "command"} { lappend labels [.tickets.ctx entrycget $i -label] } }
tk::MenuUnpost .tickets.ctx
check "context menu on severity: [lrange $labels 0 1]" {[string match "Filter severity:*" [lindex $labels 0]]}
q {is:open type:bug}
tablecols::sortBy $t updated desc; update
.tickets.main.list.t selection set [lindex [.tickets.main.list.t children {}] 0]; update; after 300; update
# Fossil's own ticket setup: other statuses, resolutions with "_".
set ok 1
foreach {status resolution icon} {
    Fixed {} st-fixed  Tested {} st-fixed  Review {} st-pending  Deferred {} st-postponed
    Verified {} st-open  Closed Wont_Fix st-rejected  Closed Not_A_Bug st-invalid
    Closed "Not Applicable Here" st-invalid  Closed Overcome_By_Events st-outofdate
    Closed Works_As_Designed st-worksforme  Closed Unable_To_Reproduce st-worksforme
    Closed Drive_By_Patch st-fixed  Closed Workaround st-closed  Closed {} st-closed
} {
    set got [tktsearch::iconName state $status $resolution]
    if {$got ne $icon} { set ok 0; puts "  $status/$resolution: $got, not $icon" }
    # The emoji of Tk 8.6 agree.
    if {[tktsearch::sign state $status $resolution] eq ""} { set ok 0; puts "  no emoji for $status/$resolution" }
}
check "icons of Fossil's statuses and resolutions" {$ok}
check "the same icon, the same emoji" {[tktsearch::sign state Fixed] eq [tktsearch::sign state Closed Fixed] && [tktsearch::sign state Closed Wont_Fix] eq [tktsearch::sign state Closed "Wont Fix"]}
# The states of the Open/Pending/Closed buttons and is: terms.
set rows [fossil::sql $T(repo) "SELECT status, [::tickets::stateExpr] FROM (SELECT 'Open' AS status
    UNION ALL SELECT 'Verified' UNION ALL SELECT 'Review' UNION ALL SELECT 'Pending'
    UNION ALL SELECT 'Deferred' UNION ALL SELECT 'Closed' UNION ALL SELECT 'Fixed'
    UNION ALL SELECT 'Tested' UNION ALL SELECT 'Deleted' UNION ALL SELECT 'Other')"]
check "states: $rows" {$rows eq {{Open open} {Verified open} {Review open} {Pending pending} {Deferred pending} {Closed closed} {Fixed closed} {Tested closed} {Deleted deleted} {Other other}}}
done
