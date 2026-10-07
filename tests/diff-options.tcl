# The Options of the diff windows: Fossil's diff options, the diff run
# again; on a scratch checkout.
source [file join [file dirname [info script]] common.tcl]
need scratch
set co $T(scratch)/co
package require Tk
wm withdraw .
# A white space change and a real one, far apart.
set f [open $co/README.md]; set lines [split [read $f] \n]; close $f
lset lines 1 "[lindex $lines 1]   "
lset lines end-2 "A real change"
set f [open $co/README.md w]; puts -nonewline $f [join $lines \n]; close $f
proc wait {w} {
    waitUntil {![dict exists $diffview::data($w) chan]}
    update
}
proc counts {w} { lrange [$w.p.files.t item 0 -values] 0 1 }
set w [diffview::run "test" -dir $co -- README.md]
wait $w
set before [counts $w]
check "the diff: $before" {$before eq {2 2}}
check "an Options menu" {[winfo exists $w.bar.options]}
set ::diffview::opt($w,space) 1
diffview::rerun $w; wait $w
check "-w: [counts $w]" {[counts $w] eq {1 1}}
set ::diffview::opt($w,space) 0
set ::diffview::opt($w,invert) 1
diffview::rerun $w; wait $w
set d $w.p.diff.u
set text [$d get 1.0 end]
check "--invert: the real change removed" {[string match "*\n-A real change*" $text]}
set ::diffview::opt($w,invert) 0
set ::diffview::opt($w,context) 0
diffview::rerun $w; wait $w
set hunks [regexp -all -inline {@@ -\d+(?:,\d+)? \+\d+(?:,\d+)? @@} [$d get 1.0 end]]
check "-c 0: $hunks" {[llength $hunks] == 2 && [lindex $hunks 0] eq "@@ -2,1 +2,1 @@"}
set ::diffview::opt($w,context) 10
diffview::rerun $w; wait $w
set hunks [regexp -all -inline {@@ -\d+(?:,\d+)? \+\d+(?:,\d+)? @@} [$d get 1.0 end]]
check "-c 10: $hunks" {[llength $hunks] >= 1 && [string match "@@ -1,1* @@" [lindex $hunks 0]]}
destroy $w
# A diff shown from a text: no options.
set w [diffview::show "text" "--- a\n+++ a\n@@ -1 +1 @@\n-x\n+y\n"]
check "no Options for a text" {![winfo exists $w.bar.options]}
# Plain text (an attachment that is not a patch): no file list.
set w [diffview::show "notes.txt" "first line\nsecond line\n"]
update
set text [$w.p.diff.u get 1.0 end]
check "plain text: [$w.status cget -text]" {"$w.p.files" ni [$w.p panes] && [string match "Text:*" [$w.status cget -text]] && [string first "second line" $text] >= 0 && [string first "(description)" $text] < 0}
# Options given in the arguments (as the Commit tab does): ticked.
set w [diffview::run "args" -dir $co -- -w -c 0 README.md]
wait $w
check "-w in the arguments: ticked, [counts $w]" {$::diffview::opt($w,space) && $::diffview::opt($w,context) == 0 && [counts $w] eq {1 1}}
set ::diffview::opt($w,space) 0
diffview::rerun $w; wait $w
check "and can be unticked: [counts $w]" {[counts $w] eq {2 2}}
done
