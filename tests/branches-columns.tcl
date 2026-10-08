# Choosing the columns of a wide table (Branches): the columns fill the
# window (tablecols::fit: the stretchable "Last comment" shrinks or grows);
# a column shown from the heading pop-up goes after the column
# right-clicked, and when even the shrunk columns leave no room, the table
# scrolls to it.
source [file join [file dirname [info script]] common.tcl]
start branches "" 1200x800
set t .branches.main.list.t
waitUntil {[llength [$t children {}]]}
update
proc check1 {key after} {
    global t
    tablecols::popup $t $after [winfo rootx $t] [winfo rooty $t]; update
    set cb .tablecolsPopup.f.c$key
    event generate $cb <Enter>
    event generate $cb <ButtonPress-1> -x 5 -y 5
    event generate $cb <ButtonRelease-1> -x 5 -y 5
    update
    destroy .tablecolsPopup; update
}
proc total {} {
    global t
    set s 0
    foreach c [$t cget -displaycolumns] { incr s [$t column $c -width] }
    return $s
}
proc inside {} {
    global t
    for {set x 0} {$x < 20} {incr x} { if {[$t identify column $x 10] ne ""} { return [expr {[winfo width $t] - 2 * $x}] } }
}
# Whether column KEY is in the visible part.
proc visible {key} {
    global t
    set total 0
    foreach c [$t cget -displaycolumns] {
        if {$c eq $key} { set left $total }
        incr total [$t column $c -width]
    }
    lassign [$t xview] first last
    expr {double($left) / $total >= $first - 1e-9
        && double($left + [$t column $key -width]) / $total <= $last + 1e-9}
}
check "fitted when shown: [total] in [inside], xview [$t xview]" {[total] == [inside]}
set min [$t column comment -minwidth]
check1 created base
set d [$t cget -displaycolumns]
check "shown after base: $d" {[lindex $d [expr {[lsearch $d base] + 1}]] eq "created"}
check "the comment column shrunk: [$t column comment -width] (min $min)" {[$t column comment -width] < 320}
check "the new column in view" {[visible created]}
check1 created base
check "hidden: fitted again, [total] in [inside]" {"created" ni [$t cget -displaycolumns] && [total] == [inside]}
# From the last column's heading: at the end, scrolled to if it overflows.
check1 users comment
set d [$t cget -displaycolumns]
check "shown after comment: $d" {[lindex $d end] eq "users"}
check "in view: [$t xview]" {[visible users]}
check1 users comment
check "hidden: fitted again" {[total] == [inside] && [$t xview] eq "0.0 1.0"}
done
