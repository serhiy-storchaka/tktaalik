# The Stash tab's diff windows: External diff runs the gdiff-command
# setting (Fossil's "stash gshow" without -i, which would print a diff
# instead); on a scratch copy.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set co $W/co
proc fossilco {args} { fossilIn $::co {*}$args }
set f [open $co/README.md a]; puts $f "stashed line"; close $f
fossilco stash save -m "for the external diff"
# The external program: leaves a mark in the checkout.
fossilco settings gdiff-command "touch $co/MARK"
start stash $co 1100x800
tktaalik::show stash; update
set t .stash.main.list.t
$t selection set [lindex [$t children {}] 0]; update
tkstash::showDiff; update
set w [lindex [lsearch -all -inline -glob [winfo children .] .diffview*] end]
check "a diff window" {$w ne ""}
diffview::external $w
for {set i 0} {$i < 50 && ![file exists $co/MARK]} {incr i} { after 100; update }
check "External diff ran the gdiff-command" {[file exists $co/MARK]}
file delete $co/MARK
done
