# Timeline: the Kind column as icons (Tk 9) or words (Tk 8.6).
source [file join [file dirname [info script]] common.tcl]
set tk9 [package vsatisfies [package provide Tk] 9]
start timeline "" 1270x840
set t .timeline.main.list.t
set tktimeline::query ""; tktimeline::search; update
proc firstOf {type} {
    foreach id [$::t children {}] { if {[dict get $tktimeline::rows($id) type] eq $type} { return $id } }
    return ""
}
set ci [firstOf ci]; set tk [firstOf t]
puts "  ci=$ci t=$tk rows=[llength [$t children {}]]"
proc hoverAt {x y} {
    global t
    event generate $t <Motion> -x $x -y $y -rootx [expr {[winfo rootx $t]+$x}] -rooty [expr {[winfo rooty $t]+$y}]
    after 800 {set ::w 1}; vwait ::w; update
    expr {[winfo exists .iconsTip] ? [.iconsTip.l cget -text] : ""}
}
proc hover {item col} {
    global t
    $t see $item; update
    lassign [$t bbox $item $col] x y w h
    hoverAt [expr {$x + $w/2}] [expr {$y + $h/2}]
}
proc hoverHead {col} {
    global t
    lassign [$t bbox [lindex [$t children {}] 0] $col] x y w h
    hoverAt [expr {$x + $w/2}] 6
}
set w [$t column kind -width]
if {$tk9} {
    check "Tk 9: kind cells empty: [list [$t set $ci kind] [$t set $tk kind]]" {[$t set $ci kind] eq "" && [$t set $tk kind] eq ""}
    check "Tk 9: narrow kind column: $w" {$w <= 60}
    check "icon tag on check-in" {[$t tag cell has icon:k-checkin [list $ci kind]]}
    check "icon tag on ticket" {[$t tag cell has icon:k-ticket [list $tk kind]]}
    check "cell tip check-in: [hover $ci kind]" {[hover $ci kind] eq "Check-in"}
    check "cell tip ticket: [hover $tk kind]" {[hover $tk kind] eq "Ticket"}
} else {
    check "Tk 8.6: words: [list [$t set $ci kind]]" {[$t set $ci kind] eq "check-in"}
    check "Tk 8.6: no redundant tip" {[hover $ci kind] eq ""}
}
check "heading tip: [list [hoverHead kind]]" {[string match "Check-in, ticket change*" [hoverHead kind]]}
check "heading text: [$t heading kind -text]" {[string match Kind* [$t heading kind -text]]}
tablecols::sortBy $t kind; update
set kinds [lmap id [$t children {}] {dict get $tktimeline::rows($id) type}]
set words [lmap k $kinds {dict get $tktimeline::kinds $k}]
check "sorted by kind: [lsort -unique $words]" {$words eq [lsort $words]}
tablecols::sortBy $t date; tablecols::sortBy $t date; update
$t selection set $tk; $t see $tk; update
check "details icon: [.timeline.main.details.text image names]" {[llength [.timeline.main.details.text image names]] == 1}
hover $ci kind
done
