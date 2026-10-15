# Merging a base branch into the checkout's (A made from B, B from main:
# B or main into A): the bases with how many check-ins are new, chosen in
# the merge window (from the Commit menu or a branch's menu), the dry run
# following the choice, no Integrate; up to date after the merge.  Into
# another branch: the checkout updated to it first, back if cancelled.
# On a scratch copy.
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
proc current {} { lindex [fossil::checkoutSql $::co "SELECT b.uuid FROM blob b
    WHERE b.rid=(SELECT value FROM vvar WHERE name='checkout')"] 0 0 }
exec fossil branch new zz-b main {*}[fossil::nosync branch] -R $R
exec fossil branch new zz-a zz-b {*}[fossil::nosync branch] -R $R
fossilIn $co update --nosync zz-a
start commit $co 1200x800
tktaalik::show commit; update
proc bases {{branch ""}} { tkbranches::baseChoices $::co $branch }
check "up to date: [bases]" {[bases] eq {{{zz-b (up to date)} {main (up to date)}} {zz-b (up to date)}}}

# New check-ins on both bases.
commitOn main "zz on main"
commitOn zz-b "zz on b 1"
commitOn zz-b "zz on b 2"
fossilIn $co update --nosync zz-a
tkcommit::refresh; update
check "new: [bases]" {[bases] eq {{{zz-b (2 new check-ins)} {main (1 new check-in)}} {zz-b (2 new check-ins)}}}
check "of another branch, zz-b: [bases zz-b]" {[bases zz-b] eq {{{main (1 new check-in)}} {main (1 new check-in)}}}
check "the names: [tkbranches::baseName {main (1 new check-in)}], [tkbranches::baseName {zz-b (up to date)}]" {
    [tkbranches::baseName {main (1 new check-in)}] eq "main" && [tkbranches::baseName {zz-b (up to date)}] eq "zz-b"
    && [tkbranches::baseName " core-8-6-branch "] eq "core-8-6-branch"}

# The menus: an entry each, no submenu.
tktaalik::show branches; update
set tkbranches::query ""; tkbranches::search; update
waitUntil {[.branches.main.list.t exists zz-a]}
tkbranches::fillBranchMenu .branches.ctx zz-b
check "a branch's menu: [labels .branches.ctx]" {"Merge a base branch…" in [labels .branches.ctx]
    && "Rebase onto a base branch…" in [labels .branches.ctx]}
check "the Commit menu" {"Merge a base branch…" in [labels .commit.menu.commit]
    && "Rebase onto a base branch…" in [labels .commit.menu.commit]}

# Merge, from the Commit menu: the window starts with zz-b; main chosen,
# the dry run again, merged.
tktaalik::show commit; update
set ::answers [dict create yesno no]
set ::outputs {}
rename tkbranches::showOutput tkbranches::realShowOutput
proc tkbranches::showOutput {title message text args} { lappend ::outputs $message; expr {[llength $args] > 0} }
whenOpen .branches.merge {
    set ::first $tkbranches::mergeOpt(what)
    set ::firstDry [.branches.merge.f.t get 1.0 end]
    set ::integrate [winfo exists .branches.merge.f.opts.integrate]
    set tkbranches::mergeOpt(what) "main (1 new check-in)"
    event generate .branches.merge.f.what.c <<ComboboxSelected>>
    after 500 {
        set ::dry [.branches.merge.f.t get 1.0 end]
        set tkbranches::mergeOpt(answer) ok
    }
}
.commit.menu.commit invoke [.commit.menu.commit index "Merge a base branch…"]
update
set mainTip [lindex [sql "SELECT b.uuid FROM tagxref x JOIN event e ON e.objid=x.rid JOIN blob b ON b.rid=x.rid
    WHERE x.tagid=(SELECT tagid FROM tag WHERE tagname='branch') AND x.tagtype>0
    AND x.value='main' ORDER BY e.mtime DESC LIMIT 1" $R] 0 0]
check "the window: zz-b first, its dry run; no Integrate" {$::first eq "zz-b (2 new check-ins)"
    && [string match "fossil merge * zz-b\n*" $::firstDry] && !$::integrate}
check "main chosen: its dry run" {[string match "fossil merge * main\n*" $::dry]}
check "from the Commit tab: the output, not to open the Commit tab: $::outputs" {$::outputs eq {{Merged into the checkout.}} && $tktaalik::active eq "commit"}
check "merged: [lindex [split [fossilIn $co changes --merge] \n] 0]" {[string match "*[string range $mainTip 0 9]*" [fossilIn $co changes --merge]]}
check "after the merge: main up to date: [bases]" {[lindex [bases] 0] eq {{zz-b (2 new check-ins)} {main (up to date)}}}
fossilIn $co commit -m "zz merge main" --nosync --no-warnings
check "committed: the same: [bases]" {[lindex [bases] 0] eq {{zz-b (2 new check-ins)} {main (up to date)}}}

# main has no base.
fossilIn $co update --nosync main
check "main: [bases]" {[bases] eq {{} {}}}

# Into another branch than the checkout's (on main): the checkout is
# updated to zz-b first; back on main if the merge is cancelled.
set onMain [current]
tktaalik::show branches; update
tkbranches::reload; update
set ::outputs {}
whenOpen .branches.merge { set tkbranches::mergeOpt(answer) cancel }
tkbranches::fillBranchMenu .branches.ctx zz-b
.branches.ctx invoke [.branches.ctx index "Merge a base branch…"]; update
check "cancelled: asked first, back on main: $::outputs" {[string match "Merge a base branch into zz-b?  The checkout, now on main,*" [lindex $::outputs 0]]
    && [lindex $::outputs end] eq "Not merged: the checkout is back on main." && [current] eq $onMain}
whenOpen .branches.merge { set ::first $tkbranches::mergeOpt(what); set tkbranches::mergeOpt(answer) ok }
tkbranches::fillBranchMenu .branches.ctx zz-b
.branches.ctx invoke [.branches.ctx index "Merge a base branch…"]; update
check "merged into zz-b: main, the checkout on zz-b" {$::first eq "main (1 new check-in)" && [fossilIn $co branch current] eq "zz-b"
    && [string match "*[string range $mainTip 0 9]*" [fossilIn $co changes --merge]]}
fossilIn $co revert
fossilIn $co update --nosync main
set f [open $co/README.md a]; puts $f "local"; close $f
set ::boxes {}
check "with uncommitted changes: refused" {![tkbranches::mergeInto zz-b $co tkbranches::reload]
    && [lindex $::boxes 0] eq "The checkout has uncommitted changes." && [current] eq $onMain}
fossilIn $co revert
done
