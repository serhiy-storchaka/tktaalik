# Branches: Finish branch... -- cancel the branch's core-* CI tags, close
# the tickets it fixes, close the branch; on a scratch copy.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
set R $W/tk.fossil
set co $W/co
# A fix branch: a ticket fixed by its comment, another only mentioned, a
# CI tag on its tip.
set fixed [lindex [sql "SELECT tkt_uuid FROM ticket WHERE status='Open' AND type='Bug' ORDER BY tkt_mtime DESC LIMIT 1" $R] 0 0]
set mentioned [lindex [sql "SELECT tkt_uuid FROM ticket WHERE status='Open' AND tkt_uuid<>'$fixed' ORDER BY tkt_mtime DESC LIMIT 1" $R] 0 0]
set f [open $co/README.md a]; puts $f "finish test"; close $f
fossilIn $co commit --nosync -m "Fix \[[string range $fixed 0 9]\]: a test fix" --branch zz-finish
set f [open $co/README.md a]; puts $f "more"; close $f
fossilIn $co commit --nosync -m "See also \[[string range $mentioned 0 9]\] for context"
set tip [lindex [sql "SELECT uuid FROM blob WHERE rid=(SELECT objid FROM event WHERE type='ci' ORDER BY mtime DESC LIMIT 1)" $R] 0 0]
fossilIn $co tag add core-zz-finish $tip
fossilIn $co update --nosync main
start branches $co
set t .branches.main.list.t
set tkbranches::query ""; tkbranches::search; update
waitUntil {[$t exists zz-finish]}
# The button by the details of the branch selected.
$t selection set zz-finish; $t focus zz-finish; update
check "the Finish button enabled" {![.branches.main.details.finish instate disabled]}
.branches.main.details.finish invoke; update
set w .branches.finish.f
check "the dialog" {[winfo exists $w]}
check "not merged: said" {[winfo exists $w.warn]}
check "the CI tag, checked: [$w.t0 cget -text]" {[string match "*core-zz-finish*" [$w.t0 cget -text]] && $tkbranches::finish(tag,0)}
set labels [lmap c [lsearch -all -inline -glob [winfo children $w] $w.k*] { list [$c cget -text] [set tkbranches::finish(tkt,[string range [winfo name $c] 1 end])] }]
check "the fixed ticket checked, the mentioned one not: $labels" {
    [llength $labels] == 2
    && [lindex [lsearch -inline -glob $labels "*[string range $fixed 0 9]*"] 1] == 1
    && [lindex [lsearch -inline -glob $labels "*[string range $mentioned 0 9]*"] 1] == 0}
check "close the branch, checked" {$tkbranches::finish(close)}
# Finish: the confirmation (with the dry runs) answered yes.
set ::outputs {}
proc tkbranches::showOutput {title message text {ok ""} {option {}}} { lappend ::outputs [list $message $text]; expr {$ok ne ""} }
$w.b.ok invoke; update
check "asked once, with the dry runs" {[llength $::outputs] == 1 && [string match "*tag cancel*branch close*" [lindex $::outputs 0 1]]}
check "the tag cancelled" {![llength [sql "SELECT 1 FROM tagxref x JOIN tag t ON t.tagid=x.tagid JOIN blob b ON b.rid=x.rid WHERE b.uuid='$tip' AND t.tagname='sym-core-zz-finish' AND x.tagtype>0" $R]]}
lassign [lindex [sql "SELECT status, resolution, closer FROM ticket WHERE tkt_uuid='$fixed'" $R] 0] status resolution closer
check "the fixed ticket closed: $status, $resolution, $closer" {$status eq "Closed" && $resolution eq "Fixed" && $closer ne ""}
check "the mentioned ticket left open" {[lindex [sql "SELECT status FROM ticket WHERE tkt_uuid='$mentioned'" $R] 0 0] eq "Open"}
check "the branch closed" {[dict get $tkbranches::branches(zz-finish) closed]}
# Nothing left to do: the button disabled (the mentioned ticket does not count).
$t selection set zz-finish; $t focus zz-finish; update
check "finished: the button disabled" {[.branches.main.details.finish instate disabled]}
foreach target [lrange $tkbranches::targets 0 0] {
    $t selection set $target; $t focus $target; update
    check "$target (a merge target): disabled" {[.branches.main.details.finish instate disabled]}
}
done
