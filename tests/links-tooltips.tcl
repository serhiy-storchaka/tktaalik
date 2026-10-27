# Tooltips of links to check-ins and tickets: the first line of a
# check-in's comment (a long one cut), a ticket's title, with an icon (a ticket's of its status); none for other
# links.  Shown over a link in a ticket's comments and over a related
# check-in in the Timeline's details, hidden when the pointer leaves.
source [file join [file dirname [info script]] common.tcl]
start tickets
set R $T(repo)
# The texts.
proc commentOf {prefix} {
    lindex [fossil::sql $::R "SELECT [fossil::outcol "coalesce(e.ecomment,e.comment)"] FROM event e
        JOIN blob b ON b.rid=e.objid WHERE b.uuid GLOB '$prefix*'"] 0 0
}
set ci [lindex [fossil::sql $R "SELECT b.uuid FROM event e JOIN blob b ON b.rid=e.objid
    WHERE e.type='ci' AND length(e.comment) <= 100 ORDER BY e.mtime DESC LIMIT 1 OFFSET 10"] 0 0]
lassign [goto::linkTip info:$ci] tip image
check "a check-in: the first line of its comment: [list $tip]" {$tip eq [fossil::oneLine [commentOf $ci]] && $tip ne ""}
set long [lindex [fossil::sql $R "SELECT b.uuid FROM event e JOIN blob b ON b.rid=e.objid
    WHERE e.type='ci' AND length(e.comment) > 200 AND instr(e.comment, char(10)) = 0 ORDER BY e.mtime DESC LIMIT 1"] 0 0]
set cut [lindex [goto::linkTip info:$long] 0]
check "a long line cut: [list $cut]" {[string length $cut] <= 100 && [string index $cut end] eq "\u2026"
    && [string first [string range $cut 0 end-1] [commentOf $long]] == 0}
check "its icon: the check-in's" {$image eq [icons::get k-checkin row]}
check "as /info/HASH too" {[lindex [goto::linkTip /info/[string range $ci 0 9]] 0] eq $tip}
# A closed ticket with a resolution: its title, the icon of the two.
lassign [lindex [fossil::sql $R "SELECT tkt_uuid, [fossil::outcol title] FROM ticket
    WHERE title<>'' AND status='Closed' AND resolution='Fixed' ORDER BY tkt_mtime DESC LIMIT 1"] 0] tkt title
lassign [goto::linkTip tkt:$tkt] tip image
check "a ticket: its title alone: [list $tip]" {$tip eq [fossil::oneLine $title]}
check "its icon: of its status" {$image eq [icons::get st-fixed row]}
set open [lindex [fossil::sql $R "SELECT tkt_uuid FROM ticket WHERE status='Open' ORDER BY tkt_mtime DESC LIMIT 1"] 0 0]
check "an open one's" {[lindex [goto::linkTip tkt:$open] 1] eq [icons::get st-open row]}
check "other links: none" {[goto::linkTip https://example.org/] eq "" && [goto::linkTip /timeline?r=core-8-6-branch] eq ""
    && [goto::linkTip info:0000000000000000000000000000000000000000] eq ""}

proc tipText {} { expr {[winfo exists .iconsTip.l] ? [list [.iconsTip.l cget -text] [.iconsTip.l cget -image]] : ""} }
# Over a link at index I of the text D: the tooltip; away: gone.
proc hover {d i} {
    icons::tipHide
    $d see $i; update
    waitUntil {[llength [$d bbox $i]]}
    lassign [$d bbox $i] x y
    event generate $d <Motion> -x [expr {$x + 1}] -y [expr {$y + 1}]; update
    waitUntil {[winfo exists .iconsTip]}
    set text [tipText]
    event generate $d <Motion> -x 2 -y [expr {[winfo height $d] - 2}]; update
    set ::gone [expr {![winfo exists .iconsTip]}]
    return $text
}

# A ticket whose comment names a check-in by [hash] (as links-internal).
set found ""
foreach row [fossil::sql $R "SELECT t.tkt_uuid, [fossil::outcol c.icomment] FROM ticketchng c
        JOIN ticket t ON t.tkt_id=c.tkt_id WHERE c.icomment LIKE '%\[%'
        ORDER BY c.tkt_mtime DESC LIMIT 200"] {
    lassign $row id text
    foreach {- h} [regexp -all -inline {\[([0-9a-f]{10,40})\]} $text] {
        set full [lindex [fossil::sql $R "SELECT b.uuid FROM blob b JOIN event e ON e.objid=b.rid AND e.type='ci'
            WHERE b.uuid GLOB '$h*' LIMIT 1"] 0 0]
        if {$full ne ""} { set found [list $id $h $full]; break }
    }
    if {$found ne ""} break
}
lassign $found tkt short full
tktsearch::showTicket $tkt; update
set d .tickets.main.details.nb.comments.text
set i [$d search -- "\[$short\]" 1.0]
set shown [hover $d "$i + 2 chars"]
check "over \[$short\] in ticket [string range $tkt 0 9]: [list $shown]" {$shown eq [goto::targetTip [list goto::checkin $full]] && [lindex $shown 1] ne ""}
check "gone when the pointer leaves" {$::gone}

# The Timeline's details: a related check-in (the parent).
tktaalik::show timeline; update
tktimeline::setQuery hash:[string range $ci 0 15]
set d .timeline.main.details.text
waitUntil {[llength [$d tag ranges rel1]]}
set i [lindex [$d tag ranges rel1] 0]
set parent [$d get $i [lindex [$d tag ranges rel1] 1]]
set shown [hover $d "$i + 2 chars"]
check "over the parent $parent: [list $shown]" {[lindex $shown 0] eq [fossil::oneLine [commentOf $parent]] && [lindex $shown 1] eq [icons::get k-checkin row]}
check "gone there too" {$::gone}
done
