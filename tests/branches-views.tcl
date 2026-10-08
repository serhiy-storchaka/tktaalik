# The Open/Unmerged/Mine/Closed/All buttons of Branches are terms of the
# search (is:open, is:open -merged:TARGET, is:open user:@me, is:closed;
# none): a
# button puts its terms in the search box, the rest of the search kept,
# and typing them selects the button.
source [file join [file dirname [info script]] common.tcl]
start branches
set t .branches.main.list.t
waitUntil {[llength [$t children {}]]}
proc closedOnly {} {
    foreach n [$::t children {}] { if {![dict get $tkbranches::branches($n) closed]} { return 0 } }
    return 1
}
proc counts {} { lmap v {open unmerged mine closed all} { .branches.tabs.$v cget -text } }
check "at first: $tkbranches::query, view $tkbranches::view" {[string match *is:open* $tkbranches::query] && $tkbranches::view eq "open"}
set before [counts]
.branches.tabs.closed invoke; update
check "Closed: $tkbranches::query" {$tkbranches::query eq "is:closed" && $tkbranches::view eq "closed" && [closedOnly] && [llength [$t children {}]]}
check "the counts stay: [counts]" {[counts] eq $before}
# The rest of the search kept.
set tkbranches::query "core is:closed"; tkbranches::search; update
.branches.tabs.open invoke; update
check "Open, the word kept: $tkbranches::query" {$tkbranches::query eq "core is:open" && $tkbranches::view eq "open"}
.branches.tabs.all invoke; update
check "All: $tkbranches::query" {$tkbranches::query eq "core" && $tkbranches::view eq "all"}
# Mine: is:open with user:@me; typed, the button follows.
.branches.tabs.mine invoke; update
check "Mine: $tkbranches::query" {$tkbranches::query eq "core is:open user:@me" && $tkbranches::view eq "mine"}
set n [llength [$t children {}]]
set tkbranches::query "user:@me is:open"; tkbranches::search; update
check "typed user:@me is:open: the Mine button" {$tkbranches::view eq "mine" && [llength [$t children {}]] >= $n}
set tkbranches::query "is:open user:$tkbranches::me"; tkbranches::search; update
check "the user by name: Mine too" {$tkbranches::view eq "mine"}
.branches.tabs.closed invoke; update
check "from Mine to Closed: user:@me goes too: $tkbranches::query" {$tkbranches::query eq "is:closed"}
# user:@me typed with another view stays a filter of its own.
set tkbranches::query "user:@me is:closed"; tkbranches::search; update
check "user:@me is:closed: the Closed button" {$tkbranches::view eq "closed"}
.branches.tabs.open invoke; update
check "then Open: user:@me kept, so Mine: $tkbranches::query" {$tkbranches::query eq "user:@me is:open" && $tkbranches::view eq "mine"}
set tkbranches::query "is:mine"; tkbranches::search; update
check "no is:mine term: $tkbranches::status" {[string match "*is:mine*" $tkbranches::status]}
# Unmerged: is:open -merged:FIRST-TARGET (main counts as merged into itself).
set first [lindex $tkbranches::targets 0]
set tkbranches::query ""; tkbranches::search; update
.branches.tabs.unmerged invoke; update
check "Unmerged: $tkbranches::query" {$tkbranches::query eq "is:open -merged:[tkbranches::targetHeading $first]" && $tkbranches::view eq "unmerged"}
check "the target itself not in it" {![$t exists $first] && [llength [$t children {}]]}
set n [llength [$t children {}]]
set tkbranches::query "-merged:$first is:open"; tkbranches::search; update
check "typed: the Unmerged button, the same list" {$tkbranches::view eq "unmerged" && [llength [$t children {}]] == $n}
.branches.tabs.open invoke; update
check "from Unmerged to Open: -merged goes too: $tkbranches::query" {$tkbranches::query eq "is:open"}
set tkbranches::query "-merged:$first is:closed"; tkbranches::search; update
check "-merged with Closed: a filter of its own" {$tkbranches::view eq "closed" && [string match "*-merged:*" $tkbranches::query]}
set tkbranches::query "is:Open"; tkbranches::search; update
check "case: is:Open is the Open view" {$tkbranches::view eq "open"}
done
