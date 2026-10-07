# Tickets: icon headings, their width and tooltips.
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
proc hoverHead {col} {
    global t i
    lassign [$t bbox $i $col] x y w h
    set x [expr {$x + $w/2}]; set y 6
    event generate $t <Motion> -x $x -y $y -rootx [expr {[winfo rootx $t]+$x}] -rooty [expr {[winfo rooty $t]+$y}]
    after 800 {set ::w 1}; vwait ::w; update
    expr {[winfo exists .iconsTip] ? [.iconsTip.l cget -text] : ""}
}
set widths [lmap c {state priority severity} {$t column $c -width}]
check "icon-wide columns: $widths" {[tcl::mathfunc::max {*}$widths] <= 60}
foreach c {state priority severity} {
    check "heading $c has an image, text [list [$t heading $c -text]]" {[$t heading $c -image] ne "" && ![regexp {[A-Za-z]} [$t heading $c -text]]}
}
check "title heading is text: [$t heading title -text]" {[$t heading title -image] eq "" && [string match Title* [$t heading title -text]]}
check "heading tip status: [list [hoverHead state]]" {[string match "Status and resolution*" [hoverHead state]]}
check "heading tip priority: [list [hoverHead priority]]" {[hoverHead priority] eq "Priority"}
check "heading tip severity: [list [hoverHead severity]]" {[hoverHead severity] eq "Severity"}
check "no heading tip on title" {[hoverHead title] eq ""}
check "cell tip after heading: [hover priority]" {[hover priority] eq "9 Immediate"}
tablecols::sortBy $t priority; update
check "sorted heading: arrow only [list [$t heading priority -text]]" {[$t heading priority -text] in {▲ ▼}}
check "sorted heading tip: [list [hoverHead priority]]" {[string match "Priority\nsorted by Priority, *" [hoverHead priority]]}
tablecols::sortBy $t state; update
check "status sorted: [list [$t heading state -text]] tip [list [hoverHead state]]" {[$t heading state -text] in {▲ ▼} && [string match "*sorted by*" [hoverHead state]]}
update
hoverHead state
done
