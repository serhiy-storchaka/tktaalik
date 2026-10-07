# The Search tab: the docs (the files of doc-glob at doc-branch, or the
# files typed), More for more of each kind.  Only reads the repository.
source [file join [file dirname [info script]] common.tcl]
needSearch
start tickets
tktaalik::show search; update
proc wait {} {
    waitUntil {![dict size $tkfulltext::running]}
    update
}
check "Docs: a kind, off at first" {[winfo exists .search.kinds.d] && !$tkfulltext::use(d)}
foreach k {c t w e f} { set tkfulltext::use($k) 0 }
set tkfulltext::use(d) 1
# No doc-glob, no files typed: said so.
set tkfulltext::docGlob ""
set tkfulltext::query attributes
tkfulltext::search; wait
check "no doc-glob: $tkfulltext::status" {[string match "*no doc-glob*" $tkfulltext::status]}
# Files typed: the man pages.
set tkfulltext::docGlob "doc/*.n"
tkfulltext::search; wait
set docs [lsearch -all -inline -index 0 $tkfulltext::results d]
check "docs: [llength $docs] ([lindex $docs 0 1])" {[llength $docs] > 0 && [string match doc/*.n [lindex $docs 0 1]]}
# Open one: the Files tab at it.
tkfulltext::openResult [lsearch -index 0 $tkfulltext::results d]; update
check "opened: Files, $tkfiles::file" {$tktaalik::active eq "files" && $tkfiles::file eq [lindex $docs 0 1]}
tktaalik::show search; update
# More: twice as many of a kind at the limit.
set tkfulltext::use(d) 0
set tkfulltext::use(c) 1
set tkfulltext::query fix
tkfulltext::search; wait
set n [llength [lsearch -all -index 0 $tkfulltext::results c]]
check "check-ins: $n, More enabled" {$n == 200 && [.search.kinds.more instate !disabled]}
.search.kinds.more invoke; wait
set n2 [llength [lsearch -all -index 0 $tkfulltext::results c]]
check "More: $n2" {$n2 > 200 && $tkfulltext::limit == 400}
set tkfulltext::query "fix crash"
tkfulltext::search; wait
check "another search: 200 again" {$tkfulltext::limit == 200}
done
