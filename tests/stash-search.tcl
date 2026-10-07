# The Stash tab: search terms (scratch checkout with stashes).
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
set ::boxes {}
proc tk_messageBox {args} {
    lappend ::boxes "[dict get $args -message] | [dict get [dict merge {-detail {}} $args] -detail]"
    expr {[dict get [dict merge {-type ok} $args] -type] eq "yesno" ? "no" : "ok"}
}
set ::runs {}
proc co {args} { fossilIn $::W/co {*}$args }
start stash $W/co 1200x800
set t .stash.main.list.t
proc q {text} {
    set tkstash::query $text
    tkstash::search 1
    update
    lsort -integer [.stash.main.list.t children {}]
}
puts "status: $tkstash::status"
check "all four" {[q ""] eq {1 2 3 4}}
check "word in comments: postponed" {[q postponed] eq {1 4}}
check "word in file names: tkfont" {[q tkfont] eq {2}}
check "glob word: *.test" {[q *.test] eq {1}}
check "comment:" {[q comment:font] eq {2}}
check "file:README" {[q file:README] eq {1 4}}
check "added:*" {[q added:*] eq {1}}
check "added:*.c (none)" {[q added:*.c] eq {}}
check "deleted:changes" {[q deleted:changes] eq {2}}
check "renamed: old name" {[q renamed:wish.1] eq {3}}
check "renamed: new name" {[q renamed:wish2] eq {3}}
check "-renamed:*" {[q -renamed:*] eq {1 2 4}}
check "diff: text only in the change" {[q diff:quuxmarker] eq {2}}
check "diff: case-insensitive, -diff" {[q {-diff:QUUXMARKER postponed}] eq {1 4}}
check "branch:main" {[q branch:main] eq {1 2 3}}
check "branch glob" {[q branch:core-8-*] eq {4}}
set h [string range [dict get $tkstash::stashes(4) hash] 0 9]
check "on:HASH" {[q on:$h] eq {4}}
check "files:2" {[q files:2] eq {1 2}}
check "files:>1 (stash 3 has only its rename)" {[q files:>1] eq {1 2}}
puts "  stash 3 files: [lmap f [dict get $tkstash::stashes(3) files] {dict get $f how}]"
check "date:today" {[q date:[clock format [clock seconds] -format %Y-%m-%d -timezone :UTC]] eq {1 2 3 4}}
check "is:current" {[q is:current] eq {1 2 3}}
check "alternatives" {[q file:README,tkFont] eq {1 2 4}}
# errors
foreach {bad expect} {is:foo {use is:current} on:xyz {not a check-in} files:x {bad number} foo:bar {unknown key} date:2026-13 {bad date}} {
    set tkstash::query $bad; tkstash::search; update
    check "error $bad" {[string match "*$expect*" $tkstash::status] && [.stash.status cget -foreground] eq "red3"}
}
q ""
check "status back: $tkstash::status" {[string match "4 stashes*" $tkstash::status]}
q postponed
check "status N of M: $tkstash::status" {[string match "2 of 4 stashes*" $tkstash::status]}
# matched files in bold, diff opens at the match
q diff:quuxmarker
$t selection set 2; update
set d .stash.main.details.text
set hit [$d tag ranges hit]
check "matched file in bold: [expr {[llength $hit] ? [$d get {*}[lrange $hit 0 1]] : {none}}]" {[llength $hit] == 2 && [$d get {*}$hit] eq "generic/tkFont.c"}
tkstash::showDiff; update
set w .diffview$diffview::count
for {set i 0} {$i < 100 && [$w.status cget -text] eq "Comparing…"} {incr i} { after 50; update }
set sel [lindex [$w.p.files.t selection] 0]
check "diff at the match: [$w.p.files.t set $sel file]" {[$w.p.files.t set $sel file] eq "generic/tkFont.c"}
destroy $w
# Go to: stash 4 was made on 8.6
q ""
$t selection set 4; update
tkstash::goto; update
check "asked, naming both check-ins: [string range [lindex $::boxes end-1] 0 160]" {[string match "*moves from * on main to * on core-8-6-branch*" [lindex $::boxes end-1]]}
check "checkout moved: [co branch current]" {[co branch current] eq "core-8-6-branch"}
check "stash applied: [co changes]" {[string match "*README.md*" [co changes]]}
check "kept" {4 in [$t children {}]}
check "now is:current = 4" {[q is:current] eq {4}}
check "Go back enabled: [.stash.bar.back state]" {![.stash.bar.back instate disabled]}
tkstash::goBack; update
check "asked to go back: [string range [lindex $::boxes end] 0 120]" {[string match "Go back to * on main?*" [lindex $::boxes end]]}
check "back on main, clean: [co branch current] / [co changes]" {[co branch current] eq "main" && [co changes] eq ""}
check "Go back disabled again" {[.stash.bar.back instate disabled]}
q ""
check "stash 4 still there" {4 in [$t children {}]}
# Go to refuses with uncommitted changes
set f [open $W/co/README.md a]; puts $f "local"; close $f
$t selection set 4; update
tkstash::goto; update
check "refused with changes: [lindex $::boxes end]" {[string match "The checkout has uncommitted changes.*" [lindex $::boxes end]] && [co branch current] eq "main"}
co revert README.md
q ""
# Go to the current check-in: says it is the same as Apply
$t selection set 1; update
tkstash::goto; update
check "same check-in: like Apply" {[string match "*already on*same as Apply*" [lindex $::boxes end-1]]}
check "no return point for the same check-in" {[.stash.bar.back instate disabled]}
co revert
# settings
tkstash::saveConfig
set f [open $T(tmp)/tkstash.conf]; set c [read $f]; close $f
check "history saved" {"diff:quuxmarker" in [dict get $c history]}
# Back and Forward restore the query.  (Its trace then runs inside the
# namespace, where a proc named "apply" once replaced the core command.)
q postponed
.stash.main.list.t selection set 4; update
tktaalik::navigate
q tkfont
check "Back/Forward: tkfont shown" {[lsort -integer [.stash.main.list.t children {}]] eq {2}}
if {[catch {tktaalik::goBack; update} err]} { puts "  error: $err" }
check "Back: postponed again, stash 4 selected" {$tkstash::query eq "postponed" && [tkstash::selected] eq "4"}
if {[catch {tktaalik::goForward; update} err]} { puts "  error: $err" }
check "Forward: tkfont again" {$tkstash::query eq "tkfont"}
done
