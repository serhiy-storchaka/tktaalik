# Branches: the details' check-ins and tickets read in the background
# (the header at once; a branch selected meanwhile gets its own lists, not
# the earlier one's).  Also fossil::sqlAsync.
source [file join [file dirname [info script]] common.tcl]
start branches "" 1400x840
set tkbranches::view all; tkbranches::showList; update
set nb .branches.main.details.nb
set c $nb.checkins.t

# fossil::sqlAsync: the rows as fossil::sql has them; an error as such.
set q "SELECT tagname, tagid FROM tag WHERE tagname GLOB 'sym-core-9-*' ORDER BY tagid"
fossil::sqlAsync $T(repo) $q {::apply {{code rows} { set ::async [list $code $rows] }}}
waitUntil {[info exists ::async]}
check "sqlAsync: the rows of fossil::sql" {[lindex $::async 0] == 0 && [lindex $::async 1] eq [fossil::sql $T(repo) $q]}
unset ::async
fossil::sqlAsync $T(repo) "SELECT nosuchcolumn FROM tag" {::apply {{code rows} { set ::async [list $code $rows] }}}
waitUntil {[info exists ::async]}
check "sqlAsync: an error: $::async" {[lindex $::async 0] == 1 || [string match "*no such column*" [lindex $::async 1]]}

# The header at once, the check-ins after.
tkbranches::showDetails trunk
check "trunk: the header at once, no check-ins yet" {[string match "trunk *" $tkbranches::header]
    && [llength [$c children {}]] == 0 && [$nb tab 0 -text] eq "Check-ins"}
waitUntil {[string match "Check-ins (*" [$nb tab 0 -text]]}
check "then its check-ins: [$nb tab 0 -text]" {[llength [$c children {}]] == 1000}

# Another branch selected before the first one's lists came: its own.
tkbranches::showDetails trunk
tkbranches::showDetails tip-698
waitUntil {[string match "Check-ins (*" [$nb tab 0 -text]]}
after 1500 {set ::tick 1}; vwait ::tick; update
set n [dict get $tkbranches::branches(tip-698) checkins]
check "tip-698 right after trunk: its own $n check-ins ([llength [$c children {}]])" {[llength [$c children {}]] == $n
    && [$nb tab 0 -text] eq "Check-ins ($n)" && ![llength [fossil::running]]}

done
