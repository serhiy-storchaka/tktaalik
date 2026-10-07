# The lines of context of the diff window: Fossil's default (5) without
# -c, others with it.
source [file join [file dirname [info script]] common.tcl]
need scratch
set co $T(scratch)/co
package require Tk
wm withdraw .
set f [open $co/README.md a]; puts $f "an added line"; close $f
proc wait {w} {
    waitUntil {![dict exists $diffview::data($w) chan]}
    update
}
set w [diffview::run "test" -dir $co -- README.md]
wait $w
set m $w.bar.options.m.context
set labels {}
for {set i 0} {$i <= [$m index end]} {incr i} { lappend labels [$m entrycget $i -label] }
check "labels: $labels" {[lindex $labels 0] eq "Default (5)" && "5" ni $labels}
check "default: no -c" {$::diffview::opt($w,context) eq "" && "-c" ni [diffview::optionArgs $w]}
set before [llength [split [$w.p.diff.u get 1.0 end] \n]]
set ::diffview::opt($w,context) 3
check "3: -c 3" {[diffview::optionArgs $w] eq {-c 3}}
diffview::rerun $w; wait $w
set after [llength [split [$w.p.diff.u get 1.0 end] \n]]
check "fewer lines with 3 than the default 5: $after < $before" {$after < $before}
done
