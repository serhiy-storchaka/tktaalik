# The values in the ticket details are links: a click searches the
# tickets with that value, Ctrl+click adds it to the search.
source [file join [file dirname [info script]] common.tcl]
start tickets
set uuid [lindex [fossil::sql $T(repo) "SELECT tkt_uuid FROM ticket WHERE tkt_uuid GLOB '2225507fff*'"] 0 0]
tktsearch::showTicket $uuid; update
set h .tickets.main.details.head
proc linkText {h tag} { $h get {*}[$h tag ranges $tag] }
set links {}
foreach tag [$h tag names] {
    if {[string match fl-* $tag] && [llength [$h tag ranges $tag]]} { lappend links [linkText $h $tag] $tag }
}
check "links: [dict keys $links]" {[dict exists $links Bug] && [dict exists $links randolf] && [dict exists $links "13. Win Menus"]}
proc click {h tag {state 0}} {
    set i [lindex [$h tag ranges $tag] 0]
    lassign [$h bbox $i] x y
    event generate $h <Motion> -x [expr {$x + 1}] -y [expr {$y + 1}]; update
    event generate $h <1> -x [expr {$x + 1}] -y [expr {$y + 1}] -state $state
    event generate $h <ButtonRelease-1> -x [expr {$x + 1}] -y [expr {$y + 1}] -state $state; update
}
check "the hand over a value" {[apply {{h tag} {
    set i [lindex [$h tag ranges $tag] 0]; lassign [$h bbox $i] x y
    event generate $h <Motion> -x [expr {$x + 1}] -y [expr {$y + 1}]; update
    $h cget -cursor}} $h [dict get $links Bug]] eq "hand2"}
click $h [dict get $links Bug]
check "Bug: [list $tktsearch::query]" {$tktsearch::query eq "type:bug"}
set n [llength [.tickets.main.list.t children {}]]
check "searched: $n tickets, all bugs" {$n > 0 && [llength [lsearch -all -inline -not [lmap i [.tickets.main.list.t children {}] {string tolower [.tickets.main.list.t set $i type]}] bug]] == 0}
tktaalik::goBack; update
check "Back: the search before" {$tktsearch::query ne "type:bug"}
# Ctrl+click: added to the search.
tktsearch::showTicket $uuid; update
set links {}
foreach tag [$h tag names] {
    if {[string match fl-* $tag] && [llength [$h tag ranges $tag]]} { lappend links [linkText $h $tag] $tag }
}
set tktsearch::query "type:bug"
tktsearch::search; update
tktsearch::showTicket $uuid; update
set links {}
foreach tag [$h tag names] {
    if {[string match fl-* $tag] && [llength [$h tag ranges $tag]]} { lappend links [linkText $h $tag] $tag }
}
set sub [lsearch -inline -glob [dict keys $links] "*Win Menus*"]
click $h [dict get $links $sub] 4
check "Ctrl+click: [list $tktsearch::query]" {[string match "type:bug subsystem:\"*Win Menus*\"" $tktsearch::query]}
# The submitter: author:.
tktsearch::showTicket $uuid; update
set links {}
foreach tag [$h tag names] {
    if {[string match fl-* $tag] && [llength [$h tag ranges $tag]]} { lappend links [linkText $h $tag] $tag }
}
click $h [dict get $links randolf]
check "submitter: [list $tktsearch::query]" {$tktsearch::query eq "author:randolf"}
check "old link tags removed" {[llength [lsearch -all -glob [$h tag names] fl-*]] == [dict size $links]}
done
