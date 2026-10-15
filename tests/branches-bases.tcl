# Merging a base branch into the checkout's (A made from B, B from main:
# B or main into A): the bases with how many check-ins are new, in the
# Commit menu and the branch menu of the checkout's branch; the merge
# dialog without Integrate; up to date after the merge.  On a scratch copy.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set R $W/tk.fossil
set co $W/co
proc commitOn {branch text} {
    fossilIn $::co update --nosync $branch
    set f [open $::co/README.md a]; puts $f $text; close $f
    fossilIn $::co commit -m $text --nosync --no-warnings
}
exec fossil branch new zz-b main {*}[fossil::nosync branch] -R $R
exec fossil branch new zz-a zz-b {*}[fossil::nosync branch] -R $R
fossilIn $co update --nosync zz-a
start commit $co 1200x800
tktaalik::show commit; update
set m .commit.menu.commit.bases
proc bases {} {
    uplevel #0 [$::m cget -postcommand]
    labels $::m
}
check "up to date: [bases]" {[bases] eq {{zz-b: up to date} {main: up to date}}}

# New check-ins on both bases.
commitOn main "zz on main"
commitOn zz-b "zz on b 1"
commitOn zz-b "zz on b 2"
fossilIn $co update --nosync zz-a
tkcommit::refresh; update
check "new: [bases]" {[bases] eq [list "zz-b: 2 new check-ins…" "main: 1 new check-in…"]}

# The branch menu: only for the checkout's branch.
tktaalik::show branches; update
set tkbranches::query ""; tkbranches::search; update
waitUntil {[.branches.main.list.t exists zz-a]}
tkbranches::fillBranchMenu .branches.ctx zz-a
check "zz-a's menu: Merge a base branch" {"Merge a base branch" in [labels .branches.ctx]
    && [labels .branches.ctx.bases] eq [bases]}
tkbranches::fillBranchMenu .branches.ctx zz-b
check "zz-b's menu (not checked out): none" {"Merge a base branch" ni [labels .branches.ctx]}

# Merge main, from the Commit menu: the dialog without Integrate.
tktaalik::show commit; update
bases
set ::answers [dict create yesno no]
set ::outputs {}
rename tkbranches::showOutput tkbranches::realShowOutput
proc tkbranches::showOutput {title message text args} { lappend ::outputs $message }
whenOpen .branches.merge {
    set ::integrate [winfo exists .branches.merge.f.opts.integrate]
    set ::dry [.branches.merge.f.t get 1.0 end]
    set tkbranches::mergeOpt(answer) ok
}
$m invoke [lsearch -exact [labels $m] "main: 1 new check-in…"]
update
set mainTip [lindex [sql "SELECT b.uuid FROM tagxref x JOIN event e ON e.objid=x.rid JOIN blob b ON b.rid=x.rid
    WHERE x.tagid=(SELECT tagid FROM tag WHERE tagname='branch') AND x.tagtype>0
    AND x.value='main' ORDER BY e.mtime DESC LIMIT 1" $R] 0 0]
check "dialog: no Integrate, the dry run of main" {!$::integrate && [string match "fossil merge * main*" $::dry]}
check "from the Commit tab: the output, not to open the Commit tab: $::outputs" {$::outputs eq {{Merged into the checkout.}} && $tktaalik::active eq "commit"}
check "merged: [lindex [split [fossilIn $co changes --merge] \n] 0]" {[string match "*[string range $mainTip 0 9]*" [fossilIn $co changes --merge]]}
check "after the merge: main up to date, zz-b still new: [bases]" {[bases] eq [list "zz-b: 2 new check-ins…" "main: up to date"]}
fossilIn $co commit -m "zz merge main" --nosync --no-warnings
check "committed: the same: [bases]" {[bases] eq [list "zz-b: 2 new check-ins…" "main: up to date"]}

# main has no base.
fossilIn $co update --nosync main
check "main: [bases]" {[bases] eq {{No base branch}}}
done
