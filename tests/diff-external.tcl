# Diffs in external programs: fossil gdiff (a gdiff-command that records
# what it was given, never a real program) from a diff window, for one of
# its files, from the Commit tab and the Files history; a diff as a .diff
# file (ui::launch records it).  A small repository made here.
source [file join [file dirname [info script]] common.tcl]
# (The recording program is a shell script.)
if {$tcl_platform(platform) eq "windows"} {
    puts "== $T(name): skipped (Windows)"
    exit 0
}
set D $T(tmp)
file delete -force $D/co $D/x.fossil $D/gdiff.log
exec fossil init $D/x.fossil
file mkdir $D/co
fossilIn $D/co open $D/x.fossil
proc write {name text} { set f [open $::D/co/$name w]; puts -nonewline $f $text; close $f }
file mkdir $D/co/sub
write a.txt "one\n"
write sub/b.txt "two\n"
fossilIn $D/co add a.txt sub
fossilIn $D/co commit -m first --no-warnings
write a.txt "one more\n"
write sub/b.txt "two more\n"
fossilIn $D/co commit -m second --no-warnings
write a.txt "one more, again\n"
write sub/b.txt "two more, again\n"
# The program: the two files' names, then their contents, into the log.
set rec $D/rec.sh
set f [open $rec w]
puts $f "#!/bin/sh\necho \"\$(basename \"\$1\") \$(cat \"\$2\")\" >> $D/gdiff.log"
close $f
file attributes $rec -permissions 0755
fossilIn $D/co settings gdiff-command $rec
proc logged {} {
    if {![file exists $::D/gdiff.log]} { return {} }
    set f [open $::D/gdiff.log]; set lines [split [string trim [read $f]] \n]; close $f
    return $lines
}
proc clearLog {} { file delete $::D/gdiff.log }
proc tk_popup {m x y args} {}

start commit $D/co
tktaalik::show commit; update
set t .commit.main.files.t
waitUntil {[$t exists sub/b.txt]}
# The Commit tab: the selected files, each in its turn.
$t selection set [list a.txt]
.commit.ctx invoke [.commit.ctx index "External diff"]
waitUntil {[llength [logged]] >= 1} 10000
after 300; update
check "Commit: one file: [logged]" {[logged] eq [list "a~orig.txt one more, again"]}
clearLog
$t selection set [list a.txt sub/b.txt]
.commit.menu.commit invoke [.commit.menu.commit index "External diff of the selected files"]
waitUntil {[llength [logged]] >= 2} 10000
after 300; update
check "Commit: two files: [logged]" {[lsort [logged]] eq [list "a~orig.txt one more, again" "b~orig.txt two more, again"]}
clearLog

# A diff window: the whole diff, one file of it.
tkcommit::diffAll
set w [lindex [lsort -dictionary [lsearch -all -inline -glob [winfo children .] .diffview*]] end]
waitUntil {[llength [dict get $diffview::data($w) files]] == 2}
check "the button" {[winfo exists $w.bar.external]}
$w.bar.external invoke
waitUntil {[llength [logged]] >= 2} 10000
after 300; update
check "the window: [logged]" {[llength [logged]] == 2}
clearLog
set m .ctx
menu $m -tearoff 0
set i [lsearch -index 0 [dict get $diffview::data($w) files] sub/b.txt]
diffview::filesMenu $w $m $i
check "the file's menu: [labels $m]" {[labels $m] eq [list "Copy its diff" "External diff of this file" \
    "Open its diff in external program" "Open the whole diff in external program"]}
$m invoke [$m index "External diff of this file"]
waitUntil {[llength [logged]] >= 1} 10000
after 300; update
check "one file of it: [logged]" {[logged] eq [list "b~orig.txt two more, again"]}
clearLog
# As .diff files: read-only copies, the file's and the whole one.
set ::launched {}
$m invoke [$m index "Open its diff in external program"]
$m invoke [$m index "Open the whole diff in external program"]
lassign $::launched one whole
proc content {path} { set f [open $path]; set text [read $f]; close $f; return $text }
check "copies: [file tail $one], [file tail $whole]" {[file tail $one] eq "b.txt.diff" && [string match "Changes_in_co*.diff" [file tail $whole]]
    && ![file writable $one] && [string match "*+two more, again*" [content $one]] && ![string match "*a.txt*" [content $one]]
    && [string match "*a.txt*+two more, again*" [content $whole]]}
destroy $m $w

# A fixed text (a patch): no gdiff, but the .diff copy.
set w [diffview::show "A patch" "--- a.txt\n+++ a.txt\n@@ -1 +1 @@\n-x\n+y\n"]
update
menu $m -tearoff 0
diffview::filesMenu $w $m 0
check "a patch: no external diff" {![winfo exists $w.bar.external]
    && [$m entrycget [$m index "External diff of this file"] -state] eq "disabled"}
set ::launched {}
$m invoke [$m index "Open the whole diff in external program"]
check "a patch as A_patch.diff" {[file tail [lindex $::launched 0]] eq "A_patch.diff"}
destroy $m $w

# The Files history: a check-in's change of the file.
tktaalik::show files; update
tkfiles::goTo [list "" "" a.txt .files.main.right.nb.history ""]
update
set h .files.main.right.nb.history.t
waitUntil {[llength [$h children {}]] == 2}
set second [lindex [$h children {}] 0]
tkfiles::historyMenu {*}[apply {{h item} {
    $h see $item
    waitUntil {[llength [$h bbox $item]] > 0}
    lassign [$h bbox $item] x y
    list [expr {$x + 5}] [expr {$y + 3}] 0 0
}} $h $second]
.files.histctx invoke [.files.histctx index "External diff against the previous version"]
waitUntil {[llength [logged]] >= 1} 10000
after 300; update
check "Files: the check-in's change: [logged]" {[logged] eq [list "a~before.txt one more"]}
done
