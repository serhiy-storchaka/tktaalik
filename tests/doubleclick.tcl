# Double-click: a ticket of the list opens Edit ticket (not the browser);
# in the Timeline a wiki, technote or forum edit shows it in its tab.
source [file join [file dirname [info script]] common.tcl]
set ::browsed {}
start tickets
set ::clickTime 100000
proc dclick {t item} {
    $t see $item; update
    while {[$t bbox $item] eq ""} { update; after 20 }
    lassign [$t bbox $item] x y
    # (Two clicks: Tk makes them a double-click.)
    # (With their times: else Tk takes all generated clicks for one
    # multiple click.)
    set now [incr ::clickTime 10000]
    foreach dt {0 100} {
        event generate $t <ButtonPress-1> -x [expr {$x + 20}] -y [expr {$y + 3}] -time [expr {$now + $dt}]
        event generate $t <ButtonRelease-1> -x [expr {$x + 20}] -y [expr {$y + 3}] -time [expr {$now + $dt + 20}]
    }
    update
}
# The Tickets list.
set t .tickets.main.list.t
set item [lindex [$t children {}] 0]
$t selection set [list $item]; update
dclick $t $item
check "double-click: Edit ticket" {[winfo exists .tickets.edit] && [string match "Edit ticket [string range $item 0 9]" [wm title .tickets.edit]] && ![llength $::browsed]}
destroy .tickets.edit
focus -force $t; event generate $t <Return>; update
check "Return: Edit ticket" {[winfo exists .tickets.edit] && ![llength $::browsed]}
destroy .tickets.edit
# The Timeline.
tktaalik::show timeline; update
set tl .timeline.main.list.t
foreach {kind tab} {wiki wiki technote wiki forum forum} {
    tktimeline::setQuery kind:$kind; update
    set rows [$tl children {}]
    if {![llength $rows]} { puts "  no $kind edits here"; continue }
    set r [lindex $rows 0]
    $tl selection set [list $r]; update
    set labels [lmap b [winfo children .timeline.main.details.buttons] {$b cget -text}]
    set want [expr {$kind eq "forum" ? "Show in Forum" : "Show in Wiki"}]
    check "$kind: a button $want ($labels)" {$want in $labels}
    dclick $tl $r
    check "$kind: double-click, the $tab tab" {$tktaalik::active eq $tab && ![llength $::browsed]}
    tktaalik::goBack; update; update
    check "$kind: Back to the Timeline" {$tktaalik::active eq "timeline"}
}
done
