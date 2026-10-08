# Tickets: Start fix... -- a branch for the fix of a ticket: this checkout
# updated, or a new checkout beside it; the Commit tab gets the new branch
# and "Fix [id]: title".  On a scratch copy.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
set R $W/tk.fossil
set co $W/co
check "a branch name from a title" {[tktsearch::branchName "Tests fail at high display scale"] eq "tests-fail-high-display-scale"}
start tickets $co 1270x840
set bug [lindex [sql "SELECT tkt_uuid FROM ticket WHERE status='Open' AND type='Bug' ORDER BY tkt_mtime DESC LIMIT 1" $R] 0 0]
set title [lindex [sql "SELECT title FROM ticket WHERE tkt_uuid='$bug'" $R] 0 0]
tktsearch::showTicket $bug; update
check "Start fix… by the title" {[winfo exists .tickets.main.details.head.fix]}
.tickets.main.details.head.fix invoke; update
set f .tickets.startfix.f
check "the dialog: [list $tktsearch::fixBranch] from $tktsearch::fixBase, [list $tktsearch::fixComment]" {
    $tktsearch::fixBranch eq [tktsearch::branchName $title] && $tktsearch::fixBase eq "main"
    && $tktsearch::fixComment eq "Fix \[[string range $bug 0 9]\]: $title"}
check "a clean checkout: this one by default" {$tktsearch::fixWhere eq "here"}
# This checkout: updated (it is at main already), the Commit tab ready.
$f.b.start invoke; update
check "the Commit tab: branch [list $tkcommit::branch]" {$tktaalik::active eq "commit" && $tkcommit::branch eq [tktsearch::branchName $title]}
check "the comment" {[string trim [.commit.bottom.msg.text get 1.0 end]] eq "Fix \[[string range $bug 0 9]\]: $title"}
# An existing name: refused.
tktaalik::show tickets; update
tktsearch::startFix $bug; update
set tktsearch::fixBranch core-8-6-branch
set ::boxes {}
$f.b.start invoke; update
check "an existing branch: refused" {[winfo exists .tickets.startfix] && [string match "*already*" [lindex $::boxes end]]}
destroy .tickets.startfix
# With changes: a new checkout beside this one, by default.
set fh [open $co/README.md a]; puts $fh "pending change"; close $fh
tktsearch::startFix $bug; update
set tktsearch::fixBranch zz-startfix
check "changes: a new checkout by default, beside: $tktsearch::fixDir" {$tktsearch::fixWhere eq "new" && $tktsearch::fixDir eq [file join $W zz-startfix]}
$f.b.start invoke; update
check "the new checkout shown: $tktaalik::root" {$tktaalik::root eq [file join $W zz-startfix] && [file exists $W/zz-startfix/README.md]}
check "its Commit tab ready" {$tktaalik::active eq "commit" && $tkcommit::branch eq "zz-startfix"}
check "the old checkout keeps its change" {[string match "*EDITED*README.md*" [fossilIn $co changes]]}
done
