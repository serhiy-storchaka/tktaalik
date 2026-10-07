# Tickets: tooltips of the icon cells.
source [file join [file dirname [info script]] common.tcl]
set tk9 [package vsatisfies [package provide Tk] 9]
tktaalik::main tickets [list $T(repo) {is:closed resolution:fixed priority:9 severity:critical}]
wm geometry . 1270x840+0+0
update
set t .tickets.main.list.t
set i [lindex [$t children {}] 0]
set cells [lmap c {state priority severity} {$t set $i $c}]
if {$tk9} {
    check "Tk 9: only icons, no text: [list $cells]" {$cells eq {{} {} {}}}
} else {
    check "Tk 8.6: only emoji: $cells" {$cells eq {✔ 🚨 🛑}}
}
check "narrow columns: [lmap c {state priority severity} {$t column $c -width}]" {[$t column state -width] < 100}
proc hover {col} {
    global t i
    $t see $i; update
    lassign [$t bbox $i $col] x y w h
    set x [expr {$x + $w/2}]; set y [expr {$y + $h/2}]
    event generate $t <Motion> -x $x -y $y -rootx [expr {[winfo rootx $t]+$x}] -rooty [expr {[winfo rooty $t]+$y}]
    after 800 {set ::w 1}; vwait ::w; update
    expr {[winfo exists .iconsTip] ? [.iconsTip.l cget -text] : ""}
}
check "tooltip on status: [hover state]" {[hover state] eq "Closed · Fixed"}
check "tooltip on priority: [hover priority]" {[hover priority] eq "9 Immediate"}
check "tooltip on severity: [hover severity]" {[hover severity] eq "Critical"}
check "no tooltip on title" {[hover title] eq ""}
hover severity
check "near the pointer: [winfo rooty .iconsTip] vs row [expr {[winfo rooty $t]+[lindex [$t bbox $i] 1]}]" {abs([winfo rooty .iconsTip] - [winfo rooty $t] - [lindex [$t bbox $i] 1]) < 60}
event generate $t <Leave>; update
check "hidden on leave" {![winfo exists .iconsTip]}
done
