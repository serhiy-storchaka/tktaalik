# Tickets: Back/Forward after ticket links (keys, menu, mouse side buttons).
source [file join [file dirname [info script]] common.tcl]
proc tktsearch::openUrl {path} {}
tktaalik::main tickets [list $T(repo) id:4c595d4d78]
wm geometry . 1270x900+0+0; wm attributes . -topmost 1
update
set t .tickets.main.list.t
set d .tickets.main.details.nb.comments.text
set m .tickets.menu.file
set A 4c595d4d788ea5142731ae3a3395151c32a724d1
# Real side-button presses through XTEST, but only on Xvfb (never on the
# user's display); else synthetic ones, which Tk 9 numbers differently
# (event generate -button 4 is the X server's button 8).
set real 0
if {$T(xbutton) ne "" && ![catch {exec pgrep -x Xvfb} pids]} {
    foreach pid $pids {
        # (Other tests' servers come and go: one may be gone already.)
        if {![catch {exec ps -o args= -p $pid} args] && [lsearch -exact $args $env(DISPLAY)] >= 0} { set real 1 }
    }
}
if {!$real} { puts "note: synthetic mouse buttons (no XTEST helper or not on Xvfb)" }
proc press {w b} {
    if {$::real} {
        event generate $w <Motion> -warp 1 -x 20 -y 20; update; after 100; update
        exec $::T(xbutton) $b
        after 300
    } else {
        if {[package vsatisfies [package provide Tk] 9] && $b >= 8} { incr b -4 }
        event generate $w <ButtonPress> -button $b -x 20 -y 20
        event generate $w <ButtonRelease> -button $b -x 20 -y 20
    }
    update; update
}
$t selection set $A; update
proc shown {} { string range $tktsearch::shownTicket 0 9 }
proc state {e} { $::m entrycget $e -state }
check "start: A, Back and Forward disabled" {[shown] eq "4c595d4d78" && [state Back] eq "disabled" && [state Forward] eq "disabled"}
$d yview moveto 0.4; update
set topA [$d index @0,0]
# Click the link to ticket 80213d1b1c in a comment.
set tag ""
foreach tg [$d tag names] {
    if {[string match ht-href-* $tg] && $htmltext::links($d,[string range $tg 8 end]) eq "tkt:80213d1b1c8458e1655b608d73b637d7d273879f"} { set tag $tg; break }
}
check "a link to 80213d1b1c: $tag" {$tag ne ""}
lassign [$d tag ranges $tag] a
$d see $a; update
set topA [$d index @0,0]
lassign [$d bbox $a] x y
event generate $d <Enter> -x [expr {$x+2}] -y [expr {$y+2}]
event generate $d <Motion> -x [expr {$x+2}] -y [expr {$y+2}]; update
event generate $d <ButtonPress-1> -x [expr {$x+2}] -y [expr {$y+2}]
event generate $d <ButtonRelease-1> -x [expr {$x+2}] -y [expr {$y+2}]; update
check "link followed: [shown], query $tktsearch::query" {[shown] eq "80213d1b1c"}
check "Back enabled, Forward not" {[state Back] eq "normal" && [state Forward] eq "disabled"}
# Mouse Back (button 8) anywhere in the tab.
press $d 8
check "button 8: back at [shown], query $tktsearch::query" {[shown] eq "4c595d4d78" && $tktsearch::query eq "id:4c595d4d78"}
check "scroll restored: [$d index @0,0] (was $topA)" {[$d index @0,0] eq $topA}
check "Forward enabled" {[state Forward] eq "normal" && [state Back] eq "disabled"}
press $t 9
check "button 9: forward at [shown]" {[shown] eq "80213d1b1c" && [state Forward] eq "disabled"}
# Alt+Left from the keyboard.
focus -force $t; update
event generate $t <Alt-Left>; update; update
check "Alt+Left: back at [shown]" {[shown] eq "4c595d4d78"}
event generate $t <Alt-Right>; update; update
check "Alt+Right: forward at [shown]" {[shown] eq "80213d1b1c"}
# The menu entry.
$m invoke Back; update; update
check "menu Back: [shown]" {[shown] eq "4c595d4d78"}
# A new link clears Forward.
tktsearch::followLink tkt:80213d1b1c8458e1655b608d73b637d7d273879f; update
check "new link: Forward cleared" {[state Forward] eq "disabled" && [llength $tktaalik::back] == 1}
# Nothing to go back to: no error.
tktaalik::goBack; update; tktaalik::goBack; update
check "Back with an empty history: still [shown]" {[shown] eq "4c595d4d78"}
# Tk 9: the TIP 474 patterns; Tk 8.6: the %b mapping.
if {[package vsatisfies [package provide Tk] 9]} {
    check "Tk 9: bound as <Button-4>/<Button-5>" {[bind . <Button-4>] ne "" && [bind . <Button-5>] ne ""}
} else {
    check "Tk 8.6: bound by %b, not <Button-4> (the wheel)" {[bind . <Button-4>] eq "" && [string match *sideButton* [bind . <ButtonPress>]]}
}
# The wheel (X button 4) is not Back.
tktsearch::followLink tkt:80213d1b1c8458e1655b608d73b637d7d273879f; update
set before [shown]
if {$real} {
    press $d 4
    check "wheel up (X button 4): still [shown]" {[shown] eq $before && [llength $tktaalik::back] >= 1}
}
# From another tab, Back returns to the ticket.
set before [shown]
tktaalik::show timeline; update
press .timeline 8
check "Timeline tab: Back returns to Tickets at [shown]" {$tktaalik::active eq "tickets" && [shown] eq $before}
done
