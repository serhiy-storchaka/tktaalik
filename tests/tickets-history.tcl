# The History tab of the ticket details: "fossil ticket history", read
# when shown.
source [file join [file dirname [info script]] common.tcl]
tktaalik::main tickets [list $T(repo)]
update
set uuid [lindex [fossil::sql $T(repo) "SELECT tkt_uuid FROM ticket WHERE tkt_uuid GLOB '2225507fff*'"] 0 0]
tktsearch::showTicket $uuid; update
set nb .tickets.main.details.nb
set d $nb.history.text
set n [lindex [fossil::sql $T(repo) "SELECT count(*) FROM ticketchng WHERE tkt_id=(SELECT tkt_id FROM ticket WHERE tkt_uuid='$uuid')"] 0 0]
check "the tab: [$nb tab $nb.history -text]" {[$nb tab $nb.history -text] eq "History ($n)" && $n > 1}
check "not read before shown" {[$d get 1.0 end-1c] eq ""}
$nb select $nb.history; update
set text [$d get 1.0 end-1c]
set cli [exec fossil ticket history $uuid -R $T(repo)]
set heads [regexp -all -line {^Ticket Change by} $cli]
set shown [llength [lsearch -all [$d tag names] head]]
set lines [regexp -all -line {^\S+  \d{4}-\d\d-\d\d \d\d:\d\d:\d\d$} $text]
check "every change: $lines of $heads" {$lines == $heads}
# (The newest change: the first of "fossil ticket history".)
regexp -line {^Ticket Change by (.*) on (.*):$} $cli -> newestUser newestDate
check "newest first: [lindex [split $text \n] 0]" {[lindex [split $text \n] 0] eq "$newestUser  $newestDate"}
check "fields: change status ..." {[string match "*change severity: Minor*" $text]}
set first "change icomment: You are right, it has the same cause as \[2128087\]"
check "comments short" {[string first $first $text] >= 0 && [string first "\u2026\n" $text] > 0 && [string first "that merge." $text] < 0}
# Another ticket: read again when shown.
$nb select $nb.comments; update
set other [lindex [fossil::sql $T(repo) "SELECT tkt_uuid FROM ticket WHERE tkt_uuid<>'$uuid' ORDER BY tkt_mtime DESC LIMIT 1"] 0 0]
tktsearch::showTicket $other; update
check "cleared for another ticket" {[$d get 1.0 end-1c] eq ""}
$nb select $nb.history; update
check "read for it: $tktsearch::historyOf" {$tktsearch::historyOf eq $other && [$d get 1.0 end-1c] ne ""}
done
