# Tickets: one whose submission is awaiting moderation (only the changes
# made to it since are in the repository) is marked in the list and in
# the details.  The repository is made here: a ticket, a change, then the
# ticket as submitted shunned, as if it had not come with a pull.
source [file join [file dirname [info script]] common.tcl]
set R $T(tmp)/moderation.fossil
proc f {args} {
    lassign [fossil::run {*}$args] code out
    if {$code} { puts "FAIL fossil $args: $out"; exit 1 }
    return $out
}
f new -A tester $R
f ticket add -R $R --user tester title "Submitted title" comment "The description" status Open type Bug
set u [lindex [sql "SELECT tkt_uuid FROM ticket" $R] 0 0]
f ticket change -R $R --user tester $u status Closed resolution Duplicate
f ticket add -R $R --user tester title "Another ticket" comment "Its description" status Open type Bug
set other [lindex [sql "SELECT tkt_uuid FROM ticket WHERE tkt_uuid<>'$u'" $R] 0 0]
set first [lindex [sql "SELECT b.uuid FROM ticketchng c JOIN blob b ON b.rid=c.tkt_rid
    WHERE c.tkt_id=(SELECT tkt_id FROM ticket WHERE tkt_uuid='$u') ORDER BY c.tkt_mtime LIMIT 1" $R] 0 0]
f sql -R $R "INSERT INTO shun(uuid, mtime) VALUES('$first', 0)"
f rebuild -R $R
check "the submission gone, the change kept" {[lindex [sql "SELECT title, status FROM ticket WHERE tkt_uuid='$u'" $R] 0] eq {{} Closed}}

start tickets $R
set t .tickets.main.list.t
# (All: it is closed.)
set tktsearch::query ""
tktsearch::search
waitUntil {[$t exists $u] && [$t exists $other]}
check "in the list: [list [$t set $u title]]" {[$t set $u title] eq "(awaiting moderation)" && "unsubmitted" in [$t item $u -tags]}
check "with a tooltip" {[string match "*awaiting a moderator*" [tktsearch::cellTip $u title]]}
check "another ticket as it is" {[$t set $other title] eq "Another ticket" && "unsubmitted" ni [$t item $other -tags]}

set h .tickets.main.details.head
set d .tickets.main.details.nb.comments.text
tktsearch::showTicket $u; update
set head [$h get 1.0 end]
check "the details: [string map {\n |} $head]" {[string match "Awaiting moderation*first changed * by tester, updated*" $head]
    && ![string match "*opened*" $head] && ![winfo exists $h.copytitle]}
check "the note for the description" {[string match "*Awaiting moderation*not in this repository*" [$d get 1.0 end]]}
tktsearch::showTicket $other; update
set head [$h get 1.0 end]
check "another ticket: [string map {\n |} $head]" {[string match "Another ticket*opened * by tester, updated*" $head]
    && [winfo exists $h.copytitle] && [string match "*Its description*" [$d get 1.0 end]]}
done
