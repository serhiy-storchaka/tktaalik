# Branches: the search terms is:leaf and descendant:, and "Branches
# descended from it" in the check-in context menu.
source [file join [file dirname [info script]] common.tcl]
start branches "" 1400x840
set tkbranches::view all; tkbranches::showList; update
set t .branches.main.list.t
proc shown {} { $::t children {} }
proc run {q} {
    set tkbranches::query $q
    tkbranches::search 1; update
    shown
}

# is:leaf: the branches with an open leaf.
set all [run ""]
set leaf [run is:leaf]
set want [lmap n $all { if {[dict get $tkbranches::branches($n) forks] > 0} { set n } else continue }]
check "is:leaf: [llength $leaf] of [llength $all]" {[lsort $leaf] eq [lsort $want] && [llength $leaf] > 0 && [llength $leaf] < [llength $all]}
set notleaf [run -is:leaf]
check "-is:leaf: the others ([llength $notleaf])" {[llength $notleaf] + [llength $leaf] == [llength $all]}

# descendant: by tag, by hash prefix, by branch.
set d [run descendant:core-9-0-0]
check "descendant:core-9-0-0: [llength $d] branches, main among them" {"main" in $d && "core-9-0-branch" in $d}
set rid [lindex [fossil::sql $T(repo) "SELECT rid FROM tagxref WHERE tagtype>0 AND tagid=(SELECT tagid FROM tag WHERE tagname='sym-core-9-0-0')"] 0 0]
set date [lindex [fossil::sql $T(repo) "SELECT strftime('%Y-%m-%d %H:%M', mtime) FROM event WHERE objid=$rid"] 0 0]
set older [lmap n $all { if {[string compare [dict get $tkbranches::branches($n) updated] $date] < 0} { set n } else continue }]
set wrong [lmap n $older { if {$n in $d} { set n } else continue }]
check "  none whose last check-in is older ([llength $older] older): $wrong" {[llength $older] > 0 && ![llength $wrong]}
set uuid [lindex [fossil::sql $T(repo) "SELECT uuid FROM blob WHERE rid=$rid"] 0 0]
set byHash [run descendant:[string range $uuid 0 11]]
check "by hash prefix: the same" {$byHash eq $d}
# Every branch shown has a check-in that is a descendant (checked one by one for a few).
set ok 1
foreach name [lrange $d 0 4] {
    set n [lindex [fossil::sql $T(repo) "WITH RECURSIVE a(rid) AS (
        SELECT x.rid FROM tagxref x WHERE x.tagid=(SELECT tagid FROM tag WHERE tagname='branch')
            AND x.tagtype>0 AND x.value=[fossil::sqlstr $name]
        UNION SELECT plink.pid FROM a JOIN plink ON plink.cid=a.rid)
        SELECT count(*) FROM a WHERE rid=$rid"] 0 0]
    if {!$n} { set ok 0; puts "  $name: no check-in after core-9-0-0" }
}
check "the branches shown descend from it" {$ok}
check "combined with other terms" {[llength [run "descendant:core-9-0-0 is:closed"]] < [llength $d]}
run descendant:zzzzzz
check "unknown: [list $tkbranches::status]" {[string match "*descendant:zzzzzz: no such*" $tkbranches::status]}

# The context menu of a check-in.
set tkbranches::query ""; tkbranches::search; update
$t selection set main; update
set c .branches.main.details.nb.checkins.t
.branches.main.details.nb select 0; update
set ci [lindex [$c children {}] end]
rename tk_popup realPopup
proc tk_popup {m args} { set ::menu $m }
$c see $ci; update
for {set i 0} {$i < 20 && [$c bbox $ci] eq ""} {incr i} { after 50 {set ::w 1}; vwait ::w; update }
lassign [$c bbox $ci] x y
tkbranches::checkinMenu [expr {$x + 5}] [expr {$y + 5}] 0 0
set labels {}
for {set i 0} {$i <= [$::menu index end]} {incr i} {
    if {[$::menu type $i] eq "command"} { lappend labels [$::menu entrycget $i -label] }
}
set i [lsearch -exact $labels "Branches descended from it"]
check "check-in menu: [lindex $labels $i]" {$i >= 0}
$::menu invoke [$::menu index "Branches descended from it"]; update
check "query: $tkbranches::query, [llength [shown]] branches" {[string match "descendant:[string range $ci 0 15]" $tkbranches::query] && "main" in [shown]}
tktaalik::goBack; update
check "Back: the query before" {$tkbranches::query eq ""}
done
