# Files in another encoding than UTF-8 (Latin-1 here): their diff, and
# Fossil's output through a pipe, read as in Tcl 8.6 (Tcl 9 reads such
# bytes as an error by default).
source [file join [file dirname [info script]] common.tcl]
set D $T(tmp)
file delete -force $D/co $D/l.fossil
exec fossil init $D/l.fossil
file mkdir $D/co
fossilIn $D/co open $D/l.fossil
proc write {bytes} { set f [open $::D/co/latin1.txt wb]; puts -nonewline $f $bytes; close $f }
write "caf\xe9\n"
fossilIn $D/co add latin1.txt
fossilIn $D/co commit -m "a Latin-1 file" --no-warnings
write "caf\xe9 au lait\n"

# The diff, in the diff view.
set w [diffview::run Latin-1 -dir $D/co -- latin1.txt]
waitUntil {![dict exists $diffview::data($w) chan]}
update
set text [$w.p.diff.u get 1.0 end]
check "the diff: [$w.status cget -text]" {[string match "*+café au lait*" $text] && [string match "1 file*" [$w.status cget -text]]}
destroy $w
# A pipe, set to UTF-8 after.
set p [fossil::pipe [list cat latin1.txt -R $D/l.fossil]]
fconfigure $p -encoding utf-8
check "a pipe: no error" {![catch {read $p} out] && $out eq "café\n"}
close $p
# In the background.
set ::bg ""
fossil::start -dir $D/co -encoding utf-8 -onDone {apply {{code out args} { set ::bg $out }}} diff latin1.txt
waitUntil {$::bg ne ""}
check "fossil::start: no error" {[string match "*+café au lait*" $::bg]}
done
