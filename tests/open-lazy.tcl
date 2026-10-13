# Opening a repository: only the tab shown reads it, the others when they
# are shown; meanwhile the window is busy, with a message.
source [file join [file dirname [info script]] common.tcl]
set D $T(tmp)
file delete -force $D/small.fossil
exec fossil init $D/small.fossil
start timeline
foreach tab {tickets branches tags} { tktaalik::show $tab; update }
tktaalik::show timeline; update
# While the Timeline reads it: busy, and the message.
set ::during {}
rename tktimeline::setRepository tktimeline::realSetRepository
proc tktimeline::setRepository {args} {
    lappend ::during [tk busy status .] [expr {[winfo exists .uiProgress] ? [.uiProgress.l cget -text] : ""}]
    tktimeline::realSetRepository {*}$args
}
check "opened" {[tktaalik::openPath $D/small.fossil]}
update
lassign $::during busy text
check "busy while reading, with a message: [list $text]" {$busy == 1 && [string match "Reading small.fossil for the Timeline tab*" $text]}
check "after: not busy, no message" {[tk busy status .] == 0 && ![winfo exists .uiProgress]}
check "the other tabs not read yet: $tktaalik::stale" {[lsort $tktaalik::stale] eq {branches tags tickets}}
check "Tickets still on the old one" {$::tickets::repo eq [file normalize $T(repo)]}
tktaalik::show tickets; update
check "Tickets read when shown: $::tickets::repo" {$::tickets::repo eq [file normalize $D/small.fossil] && "tickets" ni $tktaalik::stale}
# Back: the Timeline reads it, Tickets is stale again.
tktaalik::show timeline; update
tktaalik::openPath $T(repo); update
check "back to the first: $tktaalik::stale" {[lsort $tktaalik::stale] eq {branches tags tickets}}
done
