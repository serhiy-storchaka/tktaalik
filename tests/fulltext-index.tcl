# The search index window (fossil fts-config): the state, the changes
# after a confirmation; on a scratch copy.
source [file join [file dirname [info script]] common.tcl]
needSearch
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set ::answer ok
set ::boxes {}
tktaalik::main tickets [list $W/tk.fossil]
update
tktaalik::show search; update
.search.kinds.index invoke; update
set state [.search.fts.f.state get 1.0 end]
check "the state: [lindex [split [string trim $state] \n] end]" {[string match "*full-text index:*disabled*" $state]}
set ::answer cancel
tkfulltext::ftsChange {index on}; update
check "cancelled: nothing changed" {[string match "*disabled*" [exec fossil fts-config -R $W/tk.fossil]]}
set ::answer ok
tkfulltext::ftsChange {index on}; update
check "index on: [lindex $::boxes end]" {[string match "Turn the search index on?" [lindex $::boxes end]] && ![string match "*full-text index: *disabled*" [exec fossil fts-config -R $W/tk.fossil]]}
check "shown after the change" {![string match "*full-text index:*disabled*" [.search.fts.f.state get 1.0 end]]}
tkfulltext::ftsChange {enable check-in}; update
check "check-in search on" {[regexp {check-in search:\s+on} [exec fossil fts-config -R $W/tk.fossil]]}
tkfulltext::ftsChange reindex; update
check "reindexed: [lindex $::boxes end]" {[lindex $::boxes end] eq "Rebuild the search index?"}
# The tab's search: the same with the index on.
proc wait {} {
    waitUntil {![dict size $tkfulltext::running]}
    update
}
set tkfulltext::query menubutton
tkfulltext::search; wait
check "the search still works: [llength $tkfulltext::results]" {[llength $tkfulltext::results] > 0}
done
