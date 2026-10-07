# Files: the blame of a version from the history, under the file's old
# name (needs a checkout: the scratch one).
source [file join [file dirname [info script]] common.tcl]
need scratch
start files $T(scratch)/co 1300x800
tktaalik::show files; update
set tkfiles::version main; tkfiles::showVersion; update
set h .files.main.right.nb.history.t
.files.main.tree.t selection set [list f:README.md]; update
.files.main.right.nb select .files.main.right.nb.history; update
# The newest version as README with content.
set old ""
foreach i [$h children {}] {
    if {[$h set $i name] eq "README" && [$h set $i how] ne "deleted"} { set old $i; break }
}
check "an old version: [string range $old 0 9]" {$old ne ""}
tkfiles::showAt $old blame
set b .files.main.right.nb.blame.t
waitUntil {$tkfiles::blamePipe eq ""}
set first [$b get 1.0 1.end]
check "blame of README at it: [string range $first 0 60]" {[regexp {^[0-9a-f]{10} \d{4}-} $first] && [string first "Tk" [$b get 1.0 end]] >= 0}
# Ignoring white space: blamed again, with -w.
set before [$b get 1.0 end]
.files.main.right.nb.blame.opts.space invoke
waitUntil {$tkfiles::blamePipe eq ""}
check "ignoring white space: blamed again ([llength [split [$b get 1.0 end] \n]] lines)" {[regexp {^[0-9a-f]{10} } [$b get 1.0 1.end]] && [llength [split [$b get 1.0 end] \n]] == [llength [split $before \n]]}
check "title: [.files.main.right.title cget -text]" {[.files.main.right.title cget -text] eq "README at [string range $old 0 9]"}
# A deleted version: no content or blame in the menu.
set del ""
foreach i [$h children {}] { if {[$h set $i how] eq "deleted"} { set del $i; break } }
if {$del ne ""} {
    rename tk_popup realPopup
    proc tk_popup {m args} { set ::menu $m }
    $h see $del
    # (Tk 8.6 lays the rows out a little later.)
    for {set i 0} {$i < 20 && [$h bbox $del] eq ""} {incr i} { after 50 {set ::w 1}; vwait ::w; update }
    lassign [$h bbox $del] x y
    tkfiles::historyMenu [expr {$x + 5}] [expr {$y + 5}] 0 0
    check "deleted version: Content and Blame disabled" {[$::menu entrycget "Content of this version" -state] eq "disabled" && [$::menu entrycget "Blame of this version" -state] eq "disabled"}
}
done
