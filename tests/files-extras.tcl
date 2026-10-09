# The Files tab: when each file last changed and its size (sortable),
# the file's hash in its history, Find in history (fossil grep), a local
# file found in history (fossil whatis -f), a link to lines, an archive of
# the version.  Only reads the repository (writes files in $T(tmp)).
source [file join [file dirname [info script]] common.tcl]
proc tk_popup {m x y args} { set ::posted $m }
proc lseq0 {n} { set r {}; for {set i 0} {$i <= $n} {incr i} { lappend r $i }; return $r }
start tickets "" 1300x900
tktaalik::show files; update
set tkfiles::version core-9-0-2
tkfiles::showVersion; update
set t .files.main.tree.t
# Last changed, size.
set f f:doc/wm.n
set ls [exec fossil ls --age -v -r core-9-0-2 -R $T(repo) doc/wm.n]
regexp {^(\S+ \S+)\s+(\d+)} $ls -> date size
check "doc/wm.n: [$t set $f age], [$t set $f size]" {[$t set $f age] eq [string range $date 0 15] && [$t set $f size] eq [tkfiles::sizeText $size]}
check "a directory: its newest change ([$t set d:doc age])" {[$t set d:doc age] ne "" && [string compare [$t set d:doc age] [$t set $f age]] >= 0}
tkfiles::sortBy age; update
set kids [lmap c [$t children d:doc] {$t set $c age}]
check "sorted by age, newest first" {$kids eq [lsort -decreasing $kids]}
check "heading marked: [$t heading age -text]" {[string match "Last changed *" [$t heading age -text]]}
tkfiles::sortBy name; update
# The history: the file's hash.
$t see $f; $t selection set [list $f]; update
.files.main.right.nb select .files.main.right.nb.history; update
set h .files.main.right.nb.history.t
set first [lindex [$h children {}] 0]
set fh [lindex [fossil::sql $T(repo) "SELECT b.uuid FROM mlink m JOIN blob b ON b.rid=m.fid JOIN blob c ON c.rid=m.mid
    WHERE c.uuid='$first' AND m.fnid=(SELECT fnid FROM filename WHERE name='doc/wm.n')"] 0 0]
check "history: file hash [$h set $first fhash]" {"fhash" in [$h cget -displaycolumns] && [$h set $first fhash] eq [string range $fh 0 9]}
lassign [$h bbox $first] x y
event generate $h <ButtonPress-3> -x [expr {$x + 5}] -y [expr {$y + 3}] -rootx 10 -rooty 10; update
set m .files.histctx
set i [lsearch -exact [lmap k [lseq0 [$m index end]] {expr {[$m type $k] eq "command" ? [$m entrycget $k -label] : ""}}] "Copy file hash"]
check "menu: Copy file hash" {$i >= 0}
$m invoke $i
check "copied: [clipboard get]" {[clipboard get] eq $fh}
$m unpost
# Find in history.
.files.main.right.nb select .files.main.right.nb.grep; update
set g .files.main.right.nb.grep
set tkfiles::grepPattern "wm attributes"
set tkfiles::grepOnce 1
tkfiles::grep
waitUntil {$tkfiles::grepPipe eq ""}
update
set versions [$g.t children {}]
check "found: [$g.status cget -text]" {[llength $versions] == 1 && [llength [$g.t children [lindex $versions 0]]] >= 3}
set line [lindex [$g.t children [lindex $versions 0]] 0]
regexp {\d+} [$g.t set $line name] n
tkfiles::grepOpen $line; update
set c .files.main.right.nb.content.t
check "a line opens the content at it ($n)" {[.files.main.right.nb select] eq ".files.main.right.nb.content" && [string match "*wm attributes*" [$c get $n.0 "$n.0 lineend"]] && [$c tag ranges sel] ne ""}
# Versions without it.
.files.main.right.nb select $g; update
set tkfiles::grepOnce 0
set tkfiles::grepInvert 1
set tkfiles::grepPattern "Copyright"
tkfiles::grep
waitUntil {$tkfiles::grepPipe eq ""}
update
check "without it: [$g.status cget -text]" {[string match "* without it" [$g.status cget -text]]}
set tkfiles::grepInvert 0
# A pattern starting with "<": not a redirection.
set tkfiles::grepPattern "<<"
tkfiles::grep
waitUntil {$tkfiles::grepPipe eq ""}
update
check "a pattern with <: [$g.status cget -text]" {[string match "*line*version*" [$g.status cget -text]]}
# A local file found in history.
set local $T(tmp)/wm.n
exec fossil cat -R $T(repo) -r core-9-0-2 doc/wm.n > $local
tkfiles::findLocal $local; update
set ft .files.found.f.t
# (The check-ins that committed this content: mlink.)
set want [lsort [lmap r [fossil::sql $T(repo) "SELECT DISTINCT c.uuid FROM mlink m JOIN blob c ON c.rid=m.mid
    WHERE m.fid=(SELECT rid FROM blob WHERE uuid=(SELECT uuid FROM files_of_checkin('core-9-0-2') WHERE filename='doc/wm.n'))"] {lindex $r 0}]]
check "found in [llength [$ft children {}]] check-ins (committed in [llength $want])" {[lsort [$ft children {}]] eq $want && [llength $want]}
set ci [lindex [$ft children {}] 0]
tkfiles::openFound $ci; update
check "shown: $tkfiles::version, $tkfiles::file" {$tkfiles::file eq "doc/wm.n" && [.files.main.right.nb select] eq ".files.main.right.nb.content"}
set f [open $T(tmp)/none.txt w]; puts $f "not in any version, zzq"; close $f
tkfiles::findLocal $T(tmp)/none.txt; update
check "unknown: [.files.found.l cget -text]" {[string match "*in no version*" [.files.found.l cget -text]] && ![llength [$ft children {}]]}
destroy .files.found
# A link to lines.
set tkfiles::version core-9-0-2
tkfiles::showVersion; update
$t selection set [list f:doc/wm.n]; update
.files.main.right.nb select .files.main.right.nb.content; update
set url [tkfiles::linesUrl 10 20]
check "link: $url" {[string match "$tkfiles::remote/info/[string range $fh 0 9]?ln=10,20" $url] || ([string match "*/info/*?ln=10,20" $url] && $tkfiles::remote ne "")}
$c tag add sel 10.0 "12.0 lineend"
$c see 10.0; update
lassign [$c bbox 10.0] x y
event generate $c <ButtonPress-3> -x [expr {$x + 2}] -y [expr {$y + 2}] -rootx 10 -rooty 10; update
set cm .files.main.right.nb.content.t.ctx
set labels [lmap k [lseq0 [$cm index end]] {expr {[$cm type $k] eq "command" ? [$cm entrycget $k -label] : ""}}]
check "menu: [join $labels /]" {"Copy lines 10\u201312" in $labels && "Copy link to lines 10\u201312" in $labels}
$cm invoke [lsearch -exact $labels "Copy lines 10\u201312"]
check "lines copied without numbers" {[llength [split [clipboard get] \n]] == 3 && ![regexp {^\s*\d+  } [clipboard get]]}
# An archive.
set zip $T(tmp)/v.zip
check "archive saved" {[tkfiles::saveArchive zip $zip tk-902 doc/wm.n ""]}
set list [exec fossil zip -R $T(repo) core-9-0-2 $T(tmp)/check.zip --name tk-902 --include doc/wm.n -l]
check "with only doc/wm.n in tk-902/ ($list)" {[file size $zip] > 1000 && [string match "*tk-902/doc/wm.n*" $list]}
done
