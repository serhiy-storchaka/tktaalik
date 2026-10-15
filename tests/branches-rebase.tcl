# Rebasing the checkout's branch onto a base, as "Rebase to trunk" in the
# Tcl/Tk repositories: the checkout updated to the base's tip, the branch
# merged with --integrate, committed to the branch again (its primary
# parent the base's tip, the old tip a merge parent).  Cancelled: the
# checkout back where it was.  Refused with uncommitted changes.  On a
# scratch copy.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set R $W/tk.fossil
set co $W/co
proc commitOn {branch file text} {
    fossilIn $::co update --nosync $branch
    set f [open $::co/$file a]; puts $f $text; close $f
    fossilIn $::co commit -m $text --nosync --no-warnings
}
proc tip {branch} {
    lindex [sql "SELECT b.uuid FROM tagxref x JOIN event e ON e.objid=x.rid JOIN blob b ON b.rid=x.rid
        WHERE x.tagid=(SELECT tagid FROM tag WHERE tagname='branch') AND x.tagtype>0
        AND x.value='$branch' ORDER BY e.mtime DESC LIMIT 1" $::R] 0 0
}
proc current {} { lindex [fossil::checkoutSql $::co "SELECT b.uuid FROM blob b
    WHERE b.rid=(SELECT value FROM vvar WHERE name='checkout')"] 0 0 }
exec fossil branch new zz-b main {*}[fossil::nosync branch] -R $R
exec fossil branch new zz-c main {*}[fossil::nosync branch] -R $R
commitOn zz-b README.md "zz on b"
commitOn zz-c README.md "zz on c"
commitOn main license.terms "zz on main"
set oldB [tip zz-b]
set mainTip [tip main]
fossilIn $co update --nosync zz-b
set ::outputs {}
proc tkbranches::showOutput {title message text {ok ""} {option {}}} {
    lappend ::outputs $message
    expr {$ok ne ""}
}
start commit $co 1200x800
tktaalik::show commit; update
set m .commit.menu.commit.rebases
uplevel #0 [$m cget -postcommand]
check "the Commit menu: [labels $m]" {[labels $m] eq [list "main: 1 new check-in…"]}
tktaalik::show branches; update
set tkbranches::query ""; tkbranches::search; update
waitUntil {[.branches.main.list.t exists zz-b]}
tkbranches::fillBranchMenu .branches.ctx zz-b
check "the branch menu: Rebase onto a base branch" {"Rebase onto a base branch" in [labels .branches.ctx]
    && [labels .branches.ctx.rebases] eq [labels $m]}

# Rebase zz-b onto main: the merge with --integrate, then the Commit tab.
whenOpen .branches.merge {
    set ::integrate [winfo exists .branches.merge.f.opts.integrate]
    set ::dry [.branches.merge.f.t get 1.0 end]
    set tkbranches::mergeOpt(answer) ok
}
.branches.ctx.rebases invoke 0
update
check "asked first: [lindex $::outputs 0]" {[string match "Rebase zz-b onto the last check-in of main?*" [lindex $::outputs 0]]}
check "the merge: --integrate, no checkbox" {!$::integrate && [string match "fossil merge *--integrate* zz-b*" $::dry]}
check "the checkout at main's tip, zz-b merged" {[current] eq $mainTip && [string match "*[string range $oldB 0 9]*" [fossilIn $co changes --merge]]}
check "the Commit tab: zz-b again, \"Rebase to main\"" {$tktaalik::active eq "commit" && $tkcommit::branch eq "zz-b"
    && $tkcommit::rebased eq "zz-b" && [string trim [.commit.bottom.msg.text get 1.0 end]] eq "Rebase to main"}
set tkcommit::noWarnings 1
set ::answers [dict create yesno yes okcancel ok]
tkcommit::commit; update
destroy .commit.log
set newB [tip zz-b]
set parents [sql "SELECT p.isprim, b.uuid FROM plink p JOIN blob b ON b.rid=p.pid
    WHERE p.cid=(SELECT rid FROM blob WHERE uuid='$newB') ORDER BY p.isprim DESC" $R]
check "committed on zz-b: parents main's tip, then the old tip" {$newB ne $oldB && $parents eq [list [list 1 $mainTip] [list 0 $oldB]]}
check "the old tip no longer a leaf" {[lindex [sql "SELECT count(*) FROM leaf WHERE rid=(SELECT rid FROM blob WHERE uuid='$oldB')" $R] 0 0] == 0}
check "the checkout on zz-b" {[fossilIn $co branch current] eq "zz-b"}
check "the branch's diff: only its own file" {[string trim [fossilIn $co diff --branch zz-b --brief]] eq "CHANGED README.md"}
check "rebased forgotten after the commit" {$tkcommit::rebased eq "" && $tkcommit::branch eq ""}
check "now up to date with main: [labels $m]" {[uplevel #0 [$m cget -postcommand]; labels $m] eq {{main: up to date}}}

# Cancelled at the merge: back on zz-c.
fossilIn $co update --nosync zz-c
set before [current]
set ::outputs {}
whenOpen .branches.merge { set tkbranches::mergeOpt(answer) cancel }
tkbranches::rebase main $co tkcommit::refresh; update
check "cancelled: back on zz-c: [lindex $::outputs end]" {[current] eq $before && [lindex $::outputs end] eq "Not merged: the checkout is back on zz-c."
    && [fossilIn $co changes --merge] eq ""}

# Uncommitted changes: refused.
set f [open $co/README.md a]; puts $f "local"; close $f
set ::boxes {}
check "uncommitted changes: refused" {![tkbranches::rebase main $co tkcommit::refresh] && [current] eq $before
    && [lindex $::boxes 0] eq "The checkout has uncommitted changes."}
fossilIn $co revert
done
