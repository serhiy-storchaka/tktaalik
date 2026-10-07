# The options of the blame: white space at line ends (-Z), reverse towards
# a later version (-o), how far back (-n); lines not attributed shown as
# "unchanged" or "older".  In a scratch checkout (blame needs one).
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
start tickets $W/co 1300x900
tktaalik::show files; update
proc blame {} {
    tkfiles::reblame
    waitUntil {$tkfiles::blamePipe eq ""}
    update
    .files.main.right.nb.blame.t get 1.0 end
}
set tkfiles::version core-8-6-0
tkfiles::showVersion; update
.files.main.tree.t selection set [list f:doc/wm.n]; update
.files.main.right.nb select .files.main.right.nb.blame; update
set tkfiles::ignoreEol 1
set tkfiles::blameOrigin main
set tkfiles::blameLimit 5s
set opts [tkfiles::blameOptions]
check "options: $opts" {"-Z" in $opts && [lindex $opts [lsearch $opts -o]+1] eq [tkfiles::resolve main] && [lindex $opts [lsearch $opts -n]+1] eq "5s"}
set tkfiles::ignoreEol 0
set tkfiles::blameLimit none
set text [blame]
set unchanged [regexp -all -line {^\s+unchanged\s+\d+ } $text]
set changed [regexp -all -line {^[0-9a-f]{10} } $text]
check "reverse: $unchanged unchanged, $changed changed later" {$unchanged > 0 && $changed > 0}
check "the code after the annotation" {[string match "*unchanged*Copyright (c) 1991-1994*" $text]}
# How far back: two versions only, the rest "older".
set tkfiles::blameOrigin ""
set tkfiles::version main
tkfiles::showVersion; update
.files.main.tree.t selection set [list f:doc/wm.n]; update
set tkfiles::blameLimit 2
set text [blame]
check "limit: [regexp -all -line {^\s+older\s+\d+ } $text] older lines" {[regexp -all -line {^\s+older\s+\d+ } $text] > 0}
set tkfiles::blameLimit none
# A wrong limit: not passed.
set tkfiles::blameLimit "x"
check "a wrong limit is left out" {"-n" ni [tkfiles::blameOptions]}
done
