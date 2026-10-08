# The All/Last pull/Outgoing/Private buttons of the Timeline are terms of
# the search (none, pull:1, is:unsent, is:private): a button puts its term
# in the search box, the rest of the search kept; typing a term selects the
# button; the buttons count the rest of the search.
source [file join [file dirname [info script]] common.tcl]
start timeline
proc counts {} { lmap v {all lastpull outgoing private} { .timeline.tabs.$v cget -text } }
check "at first: All, [list $tktimeline::query]" {$tktimeline::view eq "all"}
set tktimeline::query "kind:ci"; tktimeline::search; update
set before [counts]
foreach {v term} {lastpull pull:1 outgoing is:unsent private is:private} {
    .timeline.tabs.$v invoke; update
    check "$v: [list $tktimeline::query]" {$tktimeline::query eq "kind:ci $term" && $tktimeline::view eq $v}
}
check "the counts stay: [counts]" {[counts] eq $before}
.timeline.tabs.all invoke; update
check "All: the term gone: [list $tktimeline::query]" {$tktimeline::query eq "kind:ci" && $tktimeline::view eq "all"}
# Typed: the button follows; the list is that view's.
set tktimeline::query "IS:PRIVATE kind:ci"; tktimeline::search; update
set n [llength [.timeline.main.list.t children {}]]
check "typed is:private: the Private button" {$tktimeline::view eq "private"}
check "the list: [llength [.timeline.main.list.t children {}]] = the count" {[string match "*($n)*" [.timeline.tabs.private cget -text]] || $n >= 1000}
# Another pull:N is a filter, not the view.
set tktimeline::query "pull:2"; tktimeline::search; update
check "pull:2: All" {$tktimeline::view eq "all"}
done
