# Files and folders in external programs (the program is not started:
# ui::launch records the path): the checkout's files to edit, read-only
# copies of versions to view, folders; what would run is refused.  The
# Files and Commit tabs, the Checkout menu (scratch copy).
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set co $W/co
proc tk_popup {m x y args} { set ::posted $m }
proc native {path} { file nativename [file normalize $path] }
proc entry {m label} { $m index $label }
set ::boxes {}

# What would run is refused (X11: desktop launchers; Windows: programs
# and scripts); a missing file or folder is said to be missing.  Nothing
# started.
set runner [if {$tcl_platform(platform) eq "windows"} {string cat x.bat} else {string cat x.desktop}]
check "runs: $runner, not a text" {[ui::runs $runner] && ![ui::runs x.c] && ![ui::runs README]}
set f [open $T(tmp)/$runner w]; puts $f "\[Desktop Entry\]"; close $f
set ::launched {}
check "$runner refused: [lindex $::boxes end]" {![ui::openFile $T(tmp)/$runner] && [string match "*it would run*" [lindex $::boxes end]] && $::launched eq ""}
check "missing: [lindex $::boxes end]" {![ui::openFile $T(tmp)/none.txt] && [string match "*is not there*" [lindex $::boxes end]]
    && ![ui::openFolder $T(tmp)/none] && $::launched eq ""}
check "a file opened" {[ui::openFile $co/README.md] && $::launched eq [list [native $co/README.md]]}

start files $co 1300x900
tktaalik::show files; update
set t .files.main.tree.t
waitUntil {[$t exists f:README.md]}
proc menuAt {item} {
    set t .files.main.tree.t
    $t see $item
    waitUntil {[llength [$t bbox $item]] > 0}
    lassign [$t bbox $item] x y
    set ::posted ""
    tkfiles::treeMenu [expr {$x + 5}] [expr {$y + 3}] 0 0
    return $::posted
}
# A file of the tree: this version, a copy to view; the checkout's file;
# its folder.
set m [menuAt f:library/button.tcl]
check "file menu posted: [labels $m]" {$m eq ".files.treectx" && "View in external program" in [labels $m]
    && "Open the checkout's file in external program" in [labels $m] && "Open the checkout's folder of it" in [labels $m]}
set ::launched {}
$m invoke [entry $m "View in external program"]
set copy [lindex $::launched 0]
check "a copy: [file tail $copy]" {[llength $::launched] == 1 && [file tail $copy] eq "button.tcl" && ![string match [native $co]* $copy]}
set fh [open $copy r]; fconfigure $fh -encoding utf-8; set got [read $fh]; close $fh
set want [exec fossil cat -R $W/tk.fossil -r $tkfiles::hash library/button.tcl]
check "the version's content ([string length $got] [string length $want])" {[string trimright $got \n] eq $want}
check "read-only" {![file writable $copy]}
$m invoke [entry $m "View in external program"]
check "the same copy again" {[llength $::launched] == 2 && [lindex $::launched 1] eq $copy}
set ::launched {}
$m invoke [entry $m "Open the checkout's file in external program"]
$m invoke [entry $m "Open the checkout's folder of it"]
check "the checkout's file and folder: $::launched" {$::launched eq [list [native $co/library/button.tcl] [native $co/library]]}
# A folder of the tree: the checkout's.
set m [menuAt d:library]
check "folder menu: [labels $m]" {[labels $m] eq [list "Open the checkout's folder"] && [$m entrycget 0 -state] eq "normal"}
set ::launched {}
$m invoke 0
check "the folder: $::launched" {$::launched eq [list [native $co/library]]}
# A version in the history: a copy of its own.
tkfiles::showHistory; update
set h .files.main.right.nb.history.t
waitUntil {[llength [$h children {}]] > 1}
set old [lindex [$h children {}] end]
$h see $old
waitUntil {[llength [$h bbox $old]] > 0}
lassign [$h bbox $old] x y
tkfiles::historyMenu [expr {$x + 5}] [expr {$y + 3}] 0 0
set m .files.histctx
set ::launched {}
$m invoke [entry $m "View this version in external program"]
set oldCopy [lindex $::launched 0]
check "an old version: a copy of its own" {[file tail $oldCopy] eq "button.tcl" && $oldCopy ne $copy && [file exists $oldCopy]}
# On quit the copies go.
ui::removeCopies
check "copies removed" {![file exists $copy] && ![file exists $oldCopy]}

# The Commit tab: a changed file, the selected ones; their folder.
set fh [open $co/library/button.tcl a]; puts $fh "# changed"; close $fh
tktaalik::show commit; update
tkcommit::refresh; update
waitUntil {[.commit.main.files.t exists library/button.tcl]}
.commit.main.files.t selection set [list library/button.tcl]
set ::launched {}
.commit.ctx invoke [entry .commit.ctx "Open in external program"]
.commit.ctx invoke [entry .commit.ctx "Open the folder"]
check "Commit: the file, its folder: $::launched" {$::launched eq [list [native $co/library/button.tcl] [native $co/library]]}
# The Checkout menu: the checkout's folder.
set m [tktaalik::checkoutMenu]
set ::launched {}
$m invoke [entry $m "Open the checkout's folder"]
check "Checkout menu: the folder" {$::launched eq [list [native $co]]}
exec fossil revert library/button.tcl << "" 2>@1
done
