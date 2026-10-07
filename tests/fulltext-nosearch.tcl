# The Search tab with a Fossil whose "fossil sql" lacks the search functions
# (2.28 and newer): nothing run, the reason in the status line, a warning
# once.  (Made so here: the Fossil of the tests has them.)
source [file join [file dirname [info script]] common.tcl]
start tickets
set fossil::hasSearch 0
tktaalik::show search; update
set tkfulltext::query menubutton
tkfulltext::search; update
check "nothing run" {![dict size $tkfulltext::running] && ![llength $tkfulltext::results]}
check "status: $tkfulltext::status" {[string match "Fossil * cannot search here*" $tkfulltext::status]}
set b [lindex $::boxArgs end]
check "a warning: [dict get $b -message]" {[llength $::boxArgs] == 1 && [dict get $b -icon] eq "warning" && [string match "*2.27 or*older*" [dict get $b -detail]]}
set tkfulltext::query button
tkfulltext::search; update
check "the warning once" {[llength $::boxArgs] == 1 && [string match "Fossil * cannot search here*" $tkfulltext::status]}
done
