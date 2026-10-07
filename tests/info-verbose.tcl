# The Information window: "fossil info -v", the checkouts of the
# repository in a section of their own.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
tktaalik::main tickets [list $W/co]
update
tkinfo::window; update
set text [.info.text get 1.0 end]
check "a Checkouts section" {[string match "*\nCheckouts\n*" $text]}
check "with the scratch checkout" {[string first [file normalize $W/co] $text] >= 0}
check "no alt-root lines" {[string first alt-root $text] < 0}
check "the counts still" {[string match "*\nContents\n*Check-ins\t*" $text]}
done
