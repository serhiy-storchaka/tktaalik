# The Search tab: Fossil's own help as a kind (commands, settings, web
# pages); a result opens the help text.
source [file join [file dirname [info script]] common.tcl]
needSearch
tktaalik::main tickets [list $T(repo)]
update
proc wait {} {
    waitUntil {![dict size $tkfulltext::running]}
    update
}
tktaalik::show search; update
check "a kind, off at first" {[winfo exists .search.kinds.h] && !$tkfulltext::use(h)}
foreach k [array names tkfulltext::use] { set tkfulltext::use($k) 0 }
set tkfulltext::use(h) 1
set tkfulltext::query merge
tkfulltext::search; wait
set r $tkfulltext::results
set names [lmap row $r {lindex $row 1}]
check "help results: [llength $r] ([lrange $names 0 4])" {[llength $r] > 3 && "merge" in $names && [lsort -unique [lmap row $r {lindex $row 0}]] eq "h"}
check "matches marked" {[llength [.search.main.text tag ranges mark]] > 0}
tkfulltext::openResult [lsearch -exact $names merge]; update
check "the help of merge: [wm title .search.fossilhelp]" {[winfo exists .search.fossilhelp] && [string match "*fossil merge*" [.search.fossilhelp.t get 1.0 end]]}
done
