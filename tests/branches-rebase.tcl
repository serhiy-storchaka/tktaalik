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

# Squashed: zz-d (with a side branch merged into it) onto main; its
# check-ins cherry-picked, not merged; the old tip closed after the commit.
exec fossil branch new zz-d main {*}[fossil::nosync branch] -R $R
exec fossil branch new zz-s main {*}[fossil::nosync branch] -R $R
commitOn zz-d README.md "zz on d"
fossilIn $co update --nosync zz-s
set f [open $co/zz-side.txt w]; puts $f side; close $f
fossilIn $co add zz-side.txt
fossilIn $co commit -m "zz side" --nosync --no-warnings
fossilIn $co update --nosync zz-d
fossilIn $co merge {*}[fossil::nosync merge] zz-s
fossilIn $co commit -m "zz merge side" --nosync --no-warnings
commitOn main license.terms "zz on main again"
set oldD [tip zz-d]
set mainTip [tip main]
fossilIn $co update --nosync zz-d
set nD [lindex [sql "SELECT count(*) FROM tagxref WHERE tagtype>0 AND value='zz-d'
    AND tagid=(SELECT tagid FROM tag WHERE tagname='branch')" $R] 0 0]
set ::outputs {}
set ::confirms {}
proc tagwrite::confirm {title message text args} { lappend ::confirms $message; return 1 }
set tkbranches::squash 1
whenOpen .branches.merge {
    set ::dry [.branches.merge.f.t get 1.0 end]
    set tkbranches::mergeOpt(answer) ok
}
tkbranches::rebase main $co tkcommit::refresh; update
check "squash: cherry-picked, the $nD check-ins of zz-d" {[string match "fossil merge *--cherrypick*[string range $oldD 0 9]*" $::dry]
    && [llength [regexp -all -inline -line {^    [0-9a-f]{40,}$} $::dry]] == $nD - 1}
check "squash: \"(squashed)\" in the comment" {[string trim [.commit.bottom.msg.text get 1.0 end]] eq "Rebase to main (squashed)" && $tkcommit::squashed eq $oldD}
tkcommit::commit; update
destroy .commit.log
set newD [tip zz-d]
set parents [sql "SELECT b.uuid FROM plink p JOIN blob b ON b.rid=p.pid
    WHERE p.cid=(SELECT rid FROM blob WHERE uuid='$newD')" $R]
check "squashed: one parent, main's tip" {$newD ne $oldD && $parents eq [list [list $mainTip]]}
check "squashed: the side branch's file too" {[file exists $co/zz-side.txt] && [string match "*zz on d*" [fossilIn $co cat README.md -r $newD]]}
check "asked to close the old tip: [lindex $::confirms end]" {[string match "Close the old last check-in of zz-d, [string range $oldD 0 9]?*" [lindex $::confirms end]]}
check "the old tip closed: one leaf" {[lindex [sql "SELECT count(*) FROM tagxref WHERE rid=(SELECT rid FROM blob WHERE uuid='$oldD')
    AND tagtype>0 AND tagid=(SELECT tagid FROM tag WHERE tagname='closed')" $R] 0 0] == 1}
set tkbranches::squash 0

# Another branch than the checkout's (on main): zz-e rebased, the
# checkout ending on it.
exec fossil branch new zz-e main {*}[fossil::nosync branch] -R $R
commitOn zz-e README.md "zz on e"
commitOn main license.terms "zz on main once more"
set oldE [tip zz-e]
set mainTip [tip main]
fossilIn $co update --nosync main
set ::outputs {}
whenOpen .branches.merge { set tkbranches::mergeOpt(answer) ok }
tkbranches::rebase main $co tkcommit::refresh zz-e; update
check "another branch: asked, ending on zz-e" {[string match "*The checkout, now on main, ends on zz-e.*" [lindex $::outputs 0]]}
check "another branch: at main's tip, zz-e merged, the Commit tab" {[current] eq $mainTip
    && [string match "*[string range $oldE 0 9]*" [fossilIn $co changes --merge]] && $tkcommit::branch eq "zz-e"}
tkcommit::commit; update
destroy .commit.log
set newE [tip zz-e]
set parents [sql "SELECT p.isprim, b.uuid FROM plink p JOIN blob b ON b.rid=p.pid
    WHERE p.cid=(SELECT rid FROM blob WHERE uuid='$newE') ORDER BY p.isprim DESC" $R]
check "another branch: committed on zz-e, from main's tip" {$parents eq [list [list 1 $mainTip] [list 0 $oldE]]
    && [fossilIn $co branch current] eq "zz-e"}

# Uncommitted changes: refused.
set before [current]
set f [open $co/README.md a]; puts $f "local"; close $f
set ::boxes {}
check "uncommitted changes: refused" {![tkbranches::rebase main $co tkcommit::refresh] && [current] eq $before
    && [lindex $::boxes 0] eq "The checkout has uncommitted changes."}
fossilIn $co revert
done
