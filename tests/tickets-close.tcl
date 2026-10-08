# Tickets: Close ticket... -- the resolution (Fixed for a bug, Accepted
# for others) and a closing comment, written as one change with the status
# Closed and the closer; on a scratch copy.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
set R $W/tk.fossil
start tickets $W/co 1270x840
proc ticket {where} {
    lindex [sql "SELECT tkt_uuid FROM ticket WHERE $where ORDER BY tkt_mtime DESC LIMIT 1" $::R] 0 0
}
proc fields {uuid} {
    lindex [sql "SELECT status, resolution, closer FROM ticket WHERE tkt_uuid='$uuid'" $::R] 0
}
set h .tickets.main.details.head
# An open bug: the Close button, Fixed by default.
set bug [ticket "status='Open' AND type='Bug'"]
tktsearch::showTicket $bug; update
check "Close… in the details of an open ticket" {[winfo exists $h.close]}
tktsearch::closeTicket $bug; update
set f .tickets.close.f
check "the dialog: resolution [tktsearch::fieldValue $f.eresolution]" {[winfo exists $f] && [tktsearch::fieldValue $f.eresolution] eq "Fixed"}
[formattext::widget $f.editor] insert end "Fixed by the test."
set ::boxes {}
$f.buttons.close invoke; update
check "asked first: [lindex $::boxes end]" {[string match "Close ticket [string range $bug 0 9] as Fixed?" [lindex $::boxes end]]}
lassign [fields $bug] status resolution closer
check "written: $status, $resolution, closer $closer" {$status eq "Closed" && $resolution eq "Fixed" && $closer eq $::tickets::me}
set comment [lindex [sql "SELECT icomment FROM ticketchng WHERE tkt_id=(SELECT tkt_id FROM ticket WHERE tkt_uuid='$bug')
    ORDER BY tkt_mtime DESC LIMIT 1" $R] 0 0]
check "the comment in the same change: [list $comment]" {$comment eq "Fixed by the test."}
check "the dialog closed, no Close… any more" {![winfo exists .tickets.close] && ![winfo exists $h.close]}
# Not a bug: Accepted; Cancel writes nothing.
set rfe [ticket "status='Open' AND type<>'Bug'"]
set before [fields $rfe]
tktsearch::closeTicket $rfe; update
check "not a bug: [tktsearch::fieldValue $f.eresolution]" {[tktsearch::fieldValue $f.eresolution] eq "Accepted"}
$f.buttons.cancel invoke; update
check "cancelled: nothing written" {[fields $rfe] eq $before && ![winfo exists .tickets.close]}
# Closed already: refused.
set ::boxes {}
tktsearch::closeTicket $bug; update
check "closed already: [lindex $::boxes end]" {![winfo exists .tickets.close] && [string match "*already*" [lindex $::boxes end]]}
done
