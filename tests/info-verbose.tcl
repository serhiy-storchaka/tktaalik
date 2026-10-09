# The Information window: "fossil info -v", the checkouts of the
# repository in a section of their own.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
# A second checkout (--keep: no files): Fossil lists the others, not the
# one it runs in.
file mkdir $W/co2
fossilIn $W/co2 open ../tk.fossil main --keep
tktaalik::main tickets [list $W/co]
update
tkinfo::window; update
set text [.info.text get 1.0 end]
check "a Checkouts section, with the other checkout" {[string match "*\nCheckouts\n*[file normalize $W/co2]*" $text]}
check "with the scratch checkout" {[string first [file normalize $W/co]/ $text] >= 0}
check "no alt-root lines" {[string first alt-root $text] < 0}
check "the counts still" {[string match "*\nContents\n*Check-ins\t*" $text]}
done
