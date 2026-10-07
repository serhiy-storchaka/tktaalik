# Branches: heading and cell tooltips (merge, CI, forks).
source [file join [file dirname [info script]] common.tcl]
start branches "" 1400x840
set tkbranches::view all; tkbranches::showList; update
set t .branches.main.list.t
# A branch merged into the first target at its last check-in, one earlier only, one with a CI tag.
set m2 ""; set m1 ""; set ci ""
set first [lindex $tkbranches::targets 0]
foreach id [$t children {}] {
    set b $tkbranches::branches($id)
    if {$m2 eq "" && [dict get $b merged $first] == 2} { set m2 $id }
    if {$m1 eq "" && [dict get $b merged $first] == 1} { set m1 $id }
    if {$ci eq "" && [dict get $b ci] == 2} { set ci $id }
}
puts "  targets $tkbranches::targets; m2=$m2 m1=$m1 ci=$ci"
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
    set item [lindex [$t children {}] 0]
    lassign [$t bbox $item $col] x y w h
    hoverAt [expr {$x + $w/2}] 6
}
check "heading m0: [list [hoverHead m0]]" {[string match "Merged into $first:*✓*◐*" [hoverHead m0]]}
check "heading CI: [list [hoverHead ci]]" {[string match "A core-* tag*" [hoverHead ci]]}
check "heading Forks: [list [hoverHead forks]]" {[hoverHead forks] eq "Open leaves, if more than one"}
check "heading Base: [list [hoverHead base]]" {[hoverHead base] eq "The branch it was made from"}
check "no heading tip on Branch" {[hoverHead name] eq ""}
check "heading text unchanged: [$t heading m0 -text]" {[$t heading m0 -image] eq "" && [$t heading base -text] eq "Base"}
check "cell merged: [list [hover $m2 m0]]" {[hover $m2 m0] eq "Merged into $first"}
check "cell merged earlier: [list [hover $m1 m0]]" {[hover $m1 m0] eq "Merged into $first earlier; check-ins since"}
check "cell CI: [list [hover $ci ci]]" {[string match "The last check-in is tagged: core-*" [hover $ci ci]]}
check "no tip on comment cell" {[hover $m2 comment] eq ""}
tkbranches::addTerm has forks 0; update
set f [lindex [$t children {}] 0]
if {$f eq ""} { puts "  no forked branch" } else {
    set tip [hover $f forks]
    check "forks cell: [list $tip]" {[string match "Forked: * open leaves" $tip]}
}
event generate $t <Leave>; update
check "hidden on leave" {![winfo exists .iconsTip]}
set tkbranches::query ""; tkbranches::search 1; update; hoverHead ci
# The details of a big branch: the newest 1000 check-ins, and how many.
set tkbranches::query ""; tkbranches::search 1; update
.branches.main.list.t selection set main; update
set n [dict get $tkbranches::branches(main) checkins]
set label [.branches.main.details.nb tab 0 -text]
check "main: $label" {$n > 1000 && $label eq "Check-ins (1000 of $n)" && [llength [.branches.main.details.nb.checkins.t children {}]] == 1000}
done
