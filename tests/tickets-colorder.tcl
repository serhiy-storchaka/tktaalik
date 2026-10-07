# Tickets: the default column order, and a saved one.
source [file join [file dirname [info script]] common.tcl]
tktaalik::main tickets [list $T(repo)]
update
set t .tickets.main.list.t
check "fresh: [$t cget -displaycolumns]" {[$t cget -displaycolumns] eq {id state priority severity title type subsystem version assignee updated}}
tablecols::moveColumn $t title 0; update
check "moved: [lrange [$t cget -displaycolumns] 0 1]" {[lindex [$t cget -displaycolumns] 0] eq "title"}
tablecols::defaultColumns $t; update
check "Default columns: [$t cget -displaycolumns]" {[$t cget -displaycolumns] eq {id state priority severity title type subsystem version assignee updated}}
if {$T(repo2) ne ""} {
    tktaalik::openPath $T(repo2); update
    check "tips: [$t cget -displaycolumns]" {[lrange [$t cget -displaycolumns] 0 4] eq {id state priority severity title}}
} else {
    puts "skip another ticket schema (no TKTAALIK_REPO2)"
}
tktaalik::openPath $T(repo); update
tablecols::moveColumn $t title 0; update
tktsearch::saveConfig
# a saved order wins
set saved [$t cget -displaycolumns]
destroy {*}[winfo children .tickets]
set tktsearch::order {}
tktsearch::build; tktsearch::setRepository $T(repo) ""; update
check "saved order kept: [$t cget -displaycolumns]" {[$t cget -displaycolumns] eq $saved}
done
