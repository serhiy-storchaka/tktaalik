# The Commit tab: a checkout whose check-in was moved to another branch
# since (fossil amend --branch, as a revert of a merge may do): said in
# the info line, a commit (which goes to that branch) and an update asked
# first; a pull that moves it said; a checkout gone on to another branch
# by plain updates (tkcommit::branchChanged) said and asked too.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
set R $W/tk.fossil
set co $W/co
proc ncheckins {} { lindex [fossil::sql $::R "SELECT count(*) FROM event WHERE type='ci'"] 0 0 }
proc tipBranch {} {
    lindex [fossil::sql $::R "SELECT value FROM tagxref WHERE tagtype>0
        AND tagid=(SELECT tagid FROM tag WHERE tagname='branch')
        AND rid=(SELECT objid FROM event WHERE type='ci' ORDER BY mtime DESC LIMIT 1)"] 0 0
}
# A check-in on main, then moved to zz-moved: the checkout is at it.
set f [open $co/README.md a]; puts $f "one"; close $f
fossilIn $co commit --nosync -m "On main"
fossilIn $co amend current --branch zz-moved
start commit $co 1100x800
tkcommit::refresh; update
check "moved, in the info line: $tkcommit::info" {[string match "*moved to zz-moved from main by *" $tkcommit::info]}
# Update: asked (it would follow zz-moved); Cancel: nothing done.
proc respond {w ok} {
    if {![winfo exists $w] || $::tkcommit::answer($w) ne ""} { after 20 [list respond $w $ok]; return }
    tkcommit::runPreview $w
    set ::preview [$w.f.p.t get 1.0 end-1c]
    set ::tkcommit::answer($w) $ok
}
proc here {} { lindex [fossil::checkoutSql $::co "SELECT (SELECT uuid FROM blob WHERE rid=value) FROM vvar WHERE name='checkout'"] 0 0 }
set moved [here]
set ::boxes {}
set ::answers [dict create "The check-in of the checkout was moved to zz-moved." cancel]
tkcommit::updateCheckout; update
check "update asked: [lindex $::boxes end]; Cancel: not updated" {[lindex $::boxes end] eq "The check-in of the checkout was moved to zz-moved."
    && [here] eq $moved && ![winfo exists .commit.update]}
# A commit: asked first, the branch named; No: nothing committed.
set f [open $co/README.md a]; puts $f "two"; close $f
tkcommit::refresh; update
.commit.bottom.msg.text insert end "After the move"
set n [ncheckins]
set ::boxes {}
set ::answers [dict create "This commit goes to the branch zz-moved." no]
tkcommit::commit; update
check "asked: [lindex $::boxes end]" {[lindex $::boxes end] eq "This commit goes to the branch zz-moved."
    && [dict get [lindex $::boxArgs end] -default] eq "no"}
check "No: nothing committed" {[ncheckins] == $n}
# Yes: committed, to zz-moved.
set ::answers [dict create "This commit goes to the branch zz-moved." yes]
tkcommit::commit; update
check "Yes: committed on [tipBranch]" {[ncheckins] == $n + 1 && [tipBranch] eq "zz-moved"}
# Update, Yes: the current check-in moved too (to zz-moved2); to the
# newest check-in of zz-moved instead (the one moved there first),
# through the dialog with its dry run.
fossilIn $co amend current --branch zz-moved2
set ::answers [dict create "The check-in of the checkout was moved to zz-moved2." yes]
after 20 [list respond .commit.update 1]
tkcommit::updateCheckout; update
check "update Yes: to the newest of zz-moved instead" {[here] eq $moved}
# Not moved (on main again): no question.
fossilIn $co update --nosync main
set f [open $co/README.md a]; puts $f "three"; close $f
tkcommit::refresh; update
check "not moved: nothing in the info line" {![string match "*moved*" $tkcommit::info]}
.commit.bottom.msg.text delete 1.0 end
.commit.bottom.msg.text insert end "On main again"
set ::boxes {}
tkcommit::commit; update
check "not moved: committed without asking, on [tipBranch]" {![llength $::boxes] && [tipBranch] eq "main" && [ncheckins] == $n + 2}

# Gone on to another branch by plain fossil commands (not Tktaalik's): a
# check-in on main moved to zz-elsewhere, and committed after it there.
set f [open $co/README.md a]; puts $f "four"; close $f
fossilIn $co commit --nosync -m "Main, then moved"
fossilIn $co amend current --branch zz-elsewhere
set f [open $co/README.md a]; puts $f "five"; close $f
fossilIn $co commit --nosync -m "Continued there"
tkcommit::refresh; update
check "changed, in the info line: $tkcommit::info" {[string match "*on zz-elsewhere since an update: it was on main*" $tkcommit::info]}
set f [open $co/README.md a]; puts $f "six"; close $f
tkcommit::refresh; update
.commit.bottom.msg.text delete 1.0 end
.commit.bottom.msg.text insert end "Where?"
set m [ncheckins]
set ::boxes {}
set ::answers [dict create "This commit goes to the branch zz-elsewhere." no]
tkcommit::commit; update
check "changed: asked ([lindex $::boxes end]), No: nothing" {[lindex $::boxes end] eq "This commit goes to the branch zz-elsewhere." && [ncheckins] == $m}
set ::answers [dict create "This commit goes to the branch zz-elsewhere." yes]
tkcommit::commit; update
tkcommit::refresh; update
check "Yes: committed there, then not asked again" {[ncheckins] == $m + 1 && [tipBranch] eq "zz-elsewhere"
    && ![string match "*since an update*" $tkcommit::info]}

# A pull that moves the checkout's check-in: said, the update offered.
set up $T(tmp)/up.fossil
file copy -force $R $up
exec fossil amend [here] --branch zz-pulled -R $up 2>@1
exec fossil remote file://$up -R $R 2>@1
tktaalik::show timeline; update
set ::boxes {}
set ::answers [dict create "The pull moved the check-in of the checkout to zz-pulled." no]
tktimeline::pull; update
.timeline.pull.f.b.ok invoke
for {set i 0} {$i < 600 && $tktimeline::pullChan ne ""} {incr i} { after 50; update }
update
check "pull: said ([lindex $::boxes end])" {[lindex $::boxes end] eq "The pull moved the check-in of the checkout to zz-pulled."}
done
