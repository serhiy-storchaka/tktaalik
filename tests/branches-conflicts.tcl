# The Files tab of Branches compared with another branch: the files a
# merge of the two would leave with conflicts in red (both changed the
# same lines, both added it), a file changed on one side and deleted on
# the other in orange, the others not marked; a line above says so.
# Checked with Fossil's own dry run of the merge too (Fossil 2.21 keeps
# a file both added, with a warning, instead of a conflict).  A small repository
# made here.
source [file join [file dirname [info script]] common.tcl]
set D $T(tmp)
file delete -force $D/co
file mkdir $D/co
exec fossil init $D/c.fossil
fossilIn $D/co open $D/c.fossil
proc put {name text} { set f [open $::D/co/$name w]; puts -nonewline $f $text; close $f }
proc lines {args} { join $args \n }
put a.txt [lines 1 2 3 4 5 6 7 8 ""]
put c.txt [lines 1 2 3 4 5 6 7 8 9 10 ""]
put d.txt [lines d1 d2 ""]
put e.txt [lines e ""]
fossilIn $D/co add a.txt c.txt d.txt e.txt
fossilIn $D/co commit -m "the files" --no-warnings --nosync
fossilIn $D/co branch new zz trunk {*}[fossil::nosync branch]
# On trunk: a's line 3, c's last line, d deleted, f added.
put a.txt [lines 1 2 "3 on trunk" 4 5 6 7 8 ""]
put c.txt [lines 1 2 3 4 5 6 7 8 9 "10 on trunk" ""]
fossilIn $D/co rm d.txt
put f.txt [lines "f on trunk" ""]
fossilIn $D/co add f.txt
fossilIn $D/co commit -m "trunk" --no-warnings --nosync
# On zz: a's line 3 otherwise, c's first line, d changed, f added too.
fossilIn $D/co update zz --nosync
put a.txt [lines 1 2 "3 on the branch zz" 4 5 6 7 8 ""]
put c.txt [lines "1 on zz" 2 3 4 5 6 7 8 9 10 ""]
put d.txt [lines d1 "d2 on zz" ""]
put f.txt [lines "f on the branch zz" ""]
fossilIn $D/co add f.txt
fossilIn $D/co commit -m "zz" --no-warnings --nosync
set dry [fossilIn $D/co merge -n trunk]

start branches $D/co 1200x800
set t .branches.main.list.t
waitUntil {[$t exists zz]}
$t selection set [list zz]; $t focus zz; update
set nb .branches.main.details.nb
set p $nb.files
set f $p.p.files.t
set line $p.bar.conflicts
$nb select $p; update
waitUntil {![dict exists $diffview::data($p) chan] && [llength [$f children {}]]}
check "where it started: no line" {[$line cget -text] eq ""}
proc marked {tag} {
    lsort [lmap item [$::f children {}] {
        if {$tag ni [$::f item $item -tags]} continue
        diffview::listedName $::p $item
    }]
}
proc compare {name} {
    $::p.bar.compared set $name
    tkbranches::compareWith
    waitUntil {![dict exists $diffview::data($::p) chan] && $tkbranches::conflictJob eq ""}
    update
}
compare trunk
# (f.txt, added, has no diff in the list: only named in the tooltip.)
check "conflicts: [marked conflict]" {[marked conflict] eq {a.txt}}
check "the names in the tooltip: [list [bind $line <Enter>]]" {[string match "*Conflicts:\n  a.txt\n  f.txt\nChanged on one side, deleted on the other:\n  d.txt*" [bind $line <Enter>]]}
check "changed and deleted: [marked warn]" {[marked warn] eq {d.txt}}
check "the line: [$line cget -text]" {[$line cget -text] eq "2 files conflict with the tip of trunk (red); 1 file changed on one side, deleted on the other (orange)"
    && [$line cget -foreground] eq "red3"}
check "as Fossil's dry run: [list $dry]" {[regexp {MERGE[^\n]*a\.txt[^\n]*\n\*{5} 1 merge conflict} $dry]
    && [regexp {\*{5} 1 merge conflict in f\.txt|no common ancestor for f\.txt} $dry]
    && ![regexp {conflict in c\.txt} $dry]}
# Tip to tip: the same conflicts; their files deleted after.
set tkbranches::tips 1; tkbranches::loadFiles
waitUntil {![dict exists $diffview::data($p) chan] && $tkbranches::conflictJob eq ""}
update
# (d.txt, not on trunk, has no diff in the list there.)
check "tip to tip: [marked conflict], [marked warn]" {[marked conflict] eq {a.txt f.txt} && [marked warn] eq ""
    && [string match "2 files conflict*1 file changed*" [$line cget -text]]}
set tkbranches::tips 0
# None: compared with itself's start, and with a check-in it contains.
compare "where it started"
check "where it started again: no line, nothing red, no tooltip" {[$line cget -text] eq "" && [marked conflict] eq "" && [bind $line <Enter>] eq ""}
set first [lindex [sql "SELECT uuid FROM blob b JOIN event e ON e.objid=b.rid WHERE e.type='ci' AND e.comment='the files'" $D/c.fossil] 0 0]
compare [string range $first 0 9]
check "with its first check-in: [$line cget -text]" {[$line cget -text] eq "No conflicts with the tip of [string range $first 0 9]" && [marked conflict] eq ""}
# Another branch chosen meanwhile: the check stopped, its line gone.
compare trunk
tkbranches::checkConflicts
set dir [dict get $tkbranches::conflictJob dir]
tkbranches::clearFiles
check "stopped: [list $tkbranches::conflictJob], the line kept a moment" {$tkbranches::conflictJob eq "" && ![file exists $dir]
    && [string match "2 files conflict*" [$line cget -text]]}
waitUntil {[$line cget -text] eq ""}
# Another branch with the same result: the line not emptied meanwhile.
compare trunk
set texts {}
trace add execution tkbranches::showConflicts enter {apply {{cmd op} { lappend ::texts [lindex $cmd 1] }}}
tkbranches::clearFiles
tkbranches::loadFiles
waitUntil {![dict exists $diffview::data($p) chan] && $tkbranches::conflictJob eq ""}
check "again: straight to the result: [list $texts]" {[llength $texts] == 1 && [string match "2 files conflict*" [lindex $texts 0]]}
done
