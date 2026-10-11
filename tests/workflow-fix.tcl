# The Tcl/Tk workflow of a fix, each step through the application: Start
# fix from a ticket (a branch of its own), the fix committed, a CI tag,
# the branch merged into main and committed, Finish branch (the CI tag
# cancelled, the ticket closed, the branch closed), Backport into the
# checkout of core-8-6-branch, committed there.  On a scratch copy.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
set R $W/tk.fossil
set co $W/co
file mkdir $W/co86
fossilIn $W open $R core-8-6-branch --workdir $W/co86 --nosync
proc tip {branch} {
    lindex [sql "SELECT b.uuid FROM tagxref x JOIN event e ON e.objid=x.rid JOIN blob b ON b.rid=x.rid
        WHERE x.tagid=(SELECT tagid FROM tag WHERE tagname='branch') AND x.tagtype>0
        AND x.value='$branch' ORDER BY e.mtime DESC LIMIT 1" $::R] 0 0
}
set ::outputs {}
proc tkbranches::showOutput {title message text {ok ""} {option {}}} { lappend ::outputs $message; expr {$ok ne ""} }

# 1. Start fix, from a bug: a branch named after it, from main, here.
start tickets $co 1270x840
set bug [lindex [sql "SELECT tkt_uuid FROM ticket WHERE status='Open' AND type='Bug' ORDER BY tkt_mtime DESC LIMIT 1" $R] 0 0]
set bug10 [string range $bug 0 9]
tktsearch::showTicket $bug; update
.tickets.main.details.head.fix invoke; update
set fix zz-fix-[string range $bug 0 3]
set tktsearch::fixBranch $fix
check "Start fix: from main, here, \"Fix \[id\]...\"" {$tktsearch::fixBase eq "main" && $tktsearch::fixWhere eq "here"
    && [string match "Fix \\\[$bug10\\\]: *" $tktsearch::fixComment]}
.tickets.startfix.f.b.start invoke; update
check "the Commit tab: the branch and the comment" {$tktaalik::active eq "commit" && $tkcommit::branch eq $fix
    && [string match "Fix \\\[$bug10\\\]*" [.commit.bottom.msg.text get 1.0 end]]}

# 2. The fix, committed from the Commit tab: on the new branch.
set f [open $co/README.md a]; puts $f "the fix"; close $f
tkcommit::refresh; update
set tkcommit::noWarnings 1
set ::answers [dict create yesno yes okcancel ok]
tkcommit::commit; update
destroy .commit.log
set fixTip [tip $fix]
check "committed on $fix: [string range $fixTip 0 9]" {$fixTip ne "" && [string match "*the fix*" [fossilIn $co cat README.md -r $fixTip]]}

# 3. The CI tag (as TIP 710 asks: core-*, to have the CI test it).
fossilIn $co tag add core-$fix $fixTip

# 4. Merged into main: the checkout back to main, Merge from the Branches
# tab, the merge committed.
fossilIn $co update --nosync main
tktaalik::show branches; update
set tkbranches::query ""; tkbranches::search; update
waitUntil {[.branches.main.list.t exists $fix]}
check "not merged into main yet" {[dict get $tkbranches::branches($fix) merged main] == 0}
whenOpen .branches.merge { set tkbranches::mergeOpt(answer) ok }
tkbranches::merge branch $fix; update
check "merged into the checkout: [lindex [split [fossilIn $co changes --merge] \n] 0]" {[string match "*$fixTip*" [fossilIn $co changes --merge]]}
tktaalik::show commit; update
tkcommit::refresh; update
.commit.bottom.msg.text delete 1.0 end
.commit.bottom.msg.text insert end "Merge $fix: fix \[$bug10\]"
set tkcommit::branch ""
tkcommit::commit; update
destroy .commit.log
tktaalik::show branches; update
tkbranches::reload; update
waitUntil {[info exists tkbranches::branches($fix)]}
check "merged into main: shown so" {[dict get $tkbranches::branches($fix) merged main] == 2}

# 5. Finish branch: the CI tag cancelled, the ticket closed, the branch.
.branches.main.list.t selection set $fix; update
check "Finish enabled" {![.branches.main.details.finish instate disabled]}
.branches.main.details.finish invoke; update
set w .branches.finish.f
check "Finish: the CI tag, the ticket (fixed), the branch, all checked" {![winfo exists $w.warn]
    && $tkbranches::finish(tag,0) && $tkbranches::finish(tkt,0) && $tkbranches::finish(close)}
$w.b.ok invoke; update
check "the CI tag cancelled" {![llength [sql "SELECT 1 FROM tagxref x JOIN tag t ON t.tagid=x.tagid JOIN blob b ON b.rid=x.rid WHERE b.uuid='$fixTip' AND t.tagname='sym-core-$fix' AND x.tagtype>0" $R]]}
lassign [lindex [sql "SELECT status, resolution FROM ticket WHERE tkt_uuid='$bug'" $R] 0] status resolution
check "the ticket closed: $status, $resolution" {$status eq "Closed" && $resolution eq "Fixed"}
check "the branch closed" {[dict get $tkbranches::branches($fix) closed]}

# 6. Backport into the checkout of 8.6: offered, cherry-picked, committed.
tkbranches::backport $fix; update
check "Backport: the 8.6 checkout preselected, cherry-pick" {$tkbranches::bp(dest) ne "other"
    && [lindex $tkbranches::bpDests $tkbranches::bp(dest) 1] eq "core-8-6-branch" && $tkbranches::bp(how) eq "cherrypick"}
.branches.backport.f.b.ok invoke; update
check "then that checkout shown, its Commit tab" {[file normalize $tktaalik::root] eq [file normalize $W/co86] && $tktaalik::active eq "commit"}
tkcommit::refresh; update
.commit.bottom.msg.text delete 1.0 end
.commit.bottom.msg.text insert end "Fix \[$bug10\] (backport)"
set tkcommit::branch ""
tkcommit::commit; update
destroy .commit.log
set t86 [tip core-8-6-branch]
check "committed on core-8-6-branch: the fix there" {[string match "*the fix*" [fossilIn $W/co86 cat README.md -r $t86]]}
check "main's checkout untouched" {[fossilIn $co changes] eq ""}
done
