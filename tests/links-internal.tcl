# Links in rendered texts to check-ins and other artifacts: shown in the
# application (the Timeline...), not in the browser; only what cannot be
# shown here goes to the browser (and has the arrow).
source [file join [file dirname [info script]] common.tcl]
set ::browsed {}
start tickets
set R $T(repo)
set ci [lindex [fossil::sql $R "SELECT b.uuid FROM event e JOIN blob b ON b.rid=e.objid WHERE e.type='ci' ORDER BY e.mtime DESC LIMIT 1 OFFSET 10"] 0 0]
set remote [fossil::remoteUrl $R]
# The forms of a link to a check-in.
foreach href [list info:$ci /info/[string range $ci 0 9] /timeline?c=[string range $ci 0 11] \
        $remote/info/[string range $ci 0 9]] {
    check "in the application: $href" {[goto::linkTarget $href] eq [list goto::checkin $ci]}
}
check "not here: the browser" {[goto::linkTarget info:0000000000000000000000000000000000000000] eq "" && [goto::linkTarget https://example.org/info/abcd] eq ""}
check "tickets: no arrow for check-ins" {![tktsearch::isExternal info:$ci] && [tktsearch::isExternal https://example.org/]}
# Branches, tags, diffs.
check "/timeline?r=: the branch" {[goto::linkTarget /timeline?r=core-8-6-branch] eq [list goto::branch core-8-6-branch]}
check "a URL of the server too" {[goto::linkTarget $remote/timeline?r=core-8-6-branch&n=50] eq [list goto::branch core-8-6-branch]}
check "/timeline?t= of a tag: its check-in" {[lindex [goto::linkTarget /timeline?t=core-9-0-2] 0] eq "goto::checkin"}
check "/info/NAME: [goto::linkTarget /info/core-8-6-branch]" {[goto::linkTarget /info/core-8-6-branch] ne ""}
check "/vdiff?branch=: its diff" {[goto::linkTarget /vdiff?branch=core-8-6-branch] eq [list goto::diffVersions core-8-6-branch core-8-6-branch] || [goto::linkTarget /vdiff?branch=core-8-6-branch] eq [list goto::diffBranch core-8-6-branch]}
set a [string range $ci 0 11]
set b [lindex [fossil::sql $R "SELECT substr(b.uuid,1,12) FROM event e JOIN blob b ON b.rid=e.objid WHERE e.type='ci' ORDER BY e.mtime DESC LIMIT 1 OFFSET 20"] 0 0]
check "/vdiff?from=&to=: the diff" {[goto::linkTarget "/vdiff?from=$a&to=$b"] eq [list goto::diffVersions $a $b]}
check "unknown branch, missing versions: the browser" {[goto::linkTarget /timeline?r=no-such-branch-here] eq "" && [goto::linkTarget /vdiff?from=0000000000ab&to=$b] eq ""}
check "branch links: no arrow" {![tktsearch::isExternal /timeline?r=core-8-6-branch]}
# Opening a diff link: a diff window.
set before [llength [lsearch -all -glob [winfo children .] .diffview*]]
goto::openLink "/vdiff?from=$a&to=$b"; update
check "a diff window" {[llength [lsearch -all -glob [winfo children .] .diffview*]] == $before + 1}
foreach w [lsearch -all -inline -glob [winfo children .] .diffview*] { destroy $w }
# A ticket comment with a link to a branch: the Branches tab.
set row [lindex [fossil::sql $R "SELECT t.tkt_uuid, substr(c.icomment, instr(c.icomment,'timeline?r=')+11, 40) FROM ticketchng c JOIN ticket t ON t.tkt_id=c.tkt_id WHERE c.icomment LIKE '%timeline?r=%' ORDER BY c.tkt_mtime DESC LIMIT 20"] 0]
lassign $row btkt btail
regexp {^[A-Za-z0-9._-]+} $btail branch
if {[goto::linkTarget /timeline?r=$branch] ne ""} {
    tktsearch::showTicket $btkt; update
    set d .tickets.main.details.nb.comments.text
    set link ""
    foreach tag [$d tag names] {
        if {[regexp {^ht-href-(\d+)$} $tag -> n] && [string match "*timeline?r=$branch*" $htmltext::links($d,$n)]} { set link $tag; break }
    }
    set i [lindex [$d tag ranges $link] 0]
    $d see $i; update
    lassign [$d bbox $i] x y
    event generate $d <Motion> -x [expr {$x + 1}] -y [expr {$y + 1}]; update
    event generate $d <1> -x [expr {$x + 1}] -y [expr {$y + 1}]
    event generate $d <ButtonRelease-1> -x [expr {$x + 1}] -y [expr {$y + 1}]; update
    check "a branch link in ticket [string range $btkt 0 9]: the Branches tab at $branch" {$tktaalik::active eq "branches" && [.branches.main.list.t selection] eq $branch}
    tktaalik::show tickets; update
}
# A ticket whose comment refers to a check-in by [hash]: shown in the Timeline.
# (The newest comments with a [hex] in them, then the first that names a
# check-in: joining every comment with every hash takes minutes.)
set tkt ""
foreach row [fossil::sql $R "SELECT t.tkt_uuid, [fossil::outcol c.icomment] FROM ticketchng c
        JOIN ticket t ON t.tkt_id=c.tkt_id
        WHERE c.icomment LIKE '%\[%'
        ORDER BY c.tkt_mtime DESC LIMIT 200"] {
    lassign $row id text
    foreach {- h} [regexp -all -inline {\[([0-9a-f]{10,40})\]} $text] {
        if {[llength [fossil::sql $R "SELECT 1 FROM blob b JOIN event e ON e.objid=b.rid AND e.type='ci'
                WHERE b.uuid GLOB '$h*' LIMIT 1"]]} {
            set tkt $id
            set short $h
            break
        }
    }
    if {$tkt ne ""} break
}
tktsearch::showTicket $tkt; update
set d .tickets.main.details.nb.comments.text
set i [$d search -- "\[$short\]" 1.0]
set tags [$d tag names "$i + 1 char"]
check "\[$short\] in ticket [string range $tkt 0 9]: a link, no arrow" {[lsearch -glob $tags ht-href-*] >= 0 && "ht-external" ni $tags}
set ::browsed {}
$d see $i; update
lassign [$d bbox "$i + 2 chars"] x y
event generate $d <Motion> -x [expr {$x + 1}] -y [expr {$y + 1}]; update
event generate $d <1> -x [expr {$x + 1}] -y [expr {$y + 1}]
event generate $d <ButtonRelease-1> -x [expr {$x + 1}] -y [expr {$y + 1}]; update
check "clicked: the Timeline at it ([list $tktimeline::query]), no browser" {$tktaalik::active eq "timeline" && [string match "hash:$short*" $tktimeline::query] && ![llength $::browsed]}
tktaalik::goBack; update
check "Back: the ticket again" {$tktaalik::active eq "tickets" && $tktsearch::shownTicket eq $tkt}
# The Check-ins tab of the ticket: double-click shows it in the Timeline.
set nb .tickets.main.details.nb
if {[llength [$nb.checkins.tv children {}]]} {
    set c [lindex [$nb.checkins.tv children {}] 0]
    $nb select $nb.checkins; update
    $nb.checkins.tv see $c; update
    lassign [$nb.checkins.tv bbox $c] x y
    event generate $nb.checkins.tv <Double-1> -x [expr {$x + 5}] -y [expr {$y + 3}]; update
    check "Check-ins tab: double-click, the Timeline" {$tktaalik::active eq "timeline" && $tktimeline::query eq "hash:[string range $c 0 15]"}
}
done
