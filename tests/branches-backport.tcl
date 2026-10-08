# Branches: Backport to another checkout -- a fix branch made from main,
# cherry-picked into a checkout on core-8-6-branch; the checkout shown is
# not touched.  On a scratch copy.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
set R $W/tk.fossil
set co $W/co
# The checkout of 8.6, beside (at the tip of core-8-6-branch).
file mkdir $W/co86
fossilIn $W open $R core-8-6-branch --workdir $W/co86 --nosync
# A fix on a branch from main: two check-ins.
foreach n {1 2} {
    set f [open $co/license.terms a]; puts $f "backport test $n"; close $f
    if {$n == 1} {
        fossilIn $co commit --nosync -m "Fix: backport test $n" --branch zz-backport
    } else {
        fossilIn $co commit --nosync -m "Fix: backport test $n"
    }
}
fossilIn $co update --nosync main
start branches $co
set t .branches.main.list.t
set tkbranches::query ""; tkbranches::search; update
waitUntil {[$t exists zz-backport]}
tkbranches::backport zz-backport; update
set f .branches.backport.f
set dests [lmap d $tkbranches::bpDests { lindex $d 0 }]
check "the 8.6 checkout offered, not this one: $dests" {[file normalize $W/co86] in [lmap d $dests {file normalize $d}] && [file normalize $co] ni [lmap d $dests {file normalize $d}]}
check "preselected: the 8.6 one" {$tkbranches::bp(dest) ne "other" && [lindex $tkbranches::bpDests $tkbranches::bp(dest) 1] eq "core-8-6-branch"}
check "made from main, into 8.6: cherry-pick" {$tkbranches::bp(how) eq "cherrypick"}
check "both check-ins checked" {$tkbranches::bp(count) == 2 && $tkbranches::bp(ci,0) && $tkbranches::bp(ci,1)}
set ::outputs {}
proc tkbranches::showOutput {title message text {ok ""} {option {}}} { lappend ::outputs [list $message $text]; expr {$ok ne ""} }
$f.b.ok invoke; update
check "asked once, with the dry runs" {[llength $::outputs] == 1 && [regexp -all {merge --cherrypick} [lindex $::outputs 0 1]] == 2}
check "cherry-picked into 8.6" {[string match "*backport test 2*" [fossilIn $W/co86 diff license.terms]]}
check "then that checkout shown, its Commit tab: $tktaalik::root" {[file normalize $tktaalik::root] eq [file normalize $W/co86] && $tktaalik::active eq "commit"}
check "the main checkout untouched" {[fossilIn $co changes] eq ""}
done
