# The Branches tab after the history re-audit (on a scratch copy with a
# checkout): the File and Advanced menus (no Extend a bundle; Purge
# graveyard, Switch without merging, Purge the branch), the columns as
# they are now, names fossil cannot take, Ignore merges, bundles (counts,
# import --force asked, removal with its dry run, obliterate), switching
# without merging.  Nothing is pushed.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set R $W/tk.fossil
set co $W/co
set ::boxes {}
set ::answers {}
set ::confirms {}
proc tagwrite::confirm {args} { lappend ::confirms $args; return 1 }
proc steps {steps} {
    if {![llength $steps]} return
    lassign $steps cond script
    if {![uplevel #0 [list expr $cond]]} {
        after 50 [list steps $steps]
        return
    }
    uplevel #0 $script
    after 50 [list steps [lrange $steps 2 end]]
}
proc labels {m} {
    set l {}
    for {set i 0} {$i <= [$m index end]} {incr i} {
        if {[$m type $i] in {command cascade}} { lappend l [$m entrycget $i -label] [$m entrycget $i -state] }
    }
    return $l
}
proc checkoutRid {} { lindex [fossil::checkoutSql $::co "SELECT value FROM vvar WHERE name='checkout'"] 0 0 }
file copy $R $T(tmp)/other.fossil
set O $T(tmp)/other.fossil
start branches $co 1300x900

# The File menu: no Extend a bundle (Fossil does not have it).
set l [labels .branches.menu.file]
check "File: Purge graveyard, no Extend" {[dict exists $l "Purge graveyard\u2026"] && ![dict exists $l "Extend a bundle\u2026"] && [info commands histops::extendBundle] eq ""}

# The Advanced menu of a branch.
tkbranches::fillBranchMenu .branches.ctx main
set l [labels .branches.ctx.advanced]
check "Advanced: Switch, Purge ($l)" {[dict get $l "Switch checkout to main without merging\u2026"] eq "normal" && [dict get $l "Purge the branch\u2026"] eq "normal"}

# The columns as they are now (a column hidden, not saved yet), not as
# saved, when the list is set up again.
set tl .branches.main.list.t
set ::tablecols::on($tl,comment) 0
tablecols::toggle $tl comment
tkbranches::setupColumns 1
check "columns kept: comment still hidden" {"comment" ni [$tl cget -displaycolumns]}

# Names fossil cannot take: said so, nothing run.
foreach {what script} {
    update {tkbranches::updateTo -x}
    archive {histops::archive $R -x}
    ancestor {histops::showMergeBase $R $co -x main}
    merge {tkbranches::merge branch <x}
    publish {histops::publish $R |x x}
} {
    set ::boxes {}
    set ::confirms {}
    eval $script
    check "$what -x: said so" {[lindex $::boxes 0] eq "This name cannot be passed to fossil:" && ![llength $::confirms] && ![winfo exists .branches.merge]}
}

# Common ancestor: Ignore merges shows the one along the first parents.
set a [histops::mergeBase $R $co core-8-6-branch main]
set b [histops::mergeBase $R $co core-8-6-branch main 1]
set f [exec fossil merge-base --ignore-merges core-8-6-branch main --chdir $co]
check "ignore merges: as fossil ([string range $b 0 9])" {[string match "*[string range $b 0 15]*" $f] || [string match "[string range $f 0 9]*" $b]}
histops::showMergeBase $R $co core-8-6-branch main
update
check "dialog: Ignore merges, off, [string range $a 0 9]" {[winfo exists .tagwrite.f.ignore] && !$::histops::ignoreMerges && [string match "*[string range $a 0 15]*" [.tagwrite.f.msg cget -text]]}
.tagwrite.f.ignore invoke
update
check "Ignore merges: [string range $b 0 9] shown" {[winfo exists .tagwrite.f.ignore] && $::histops::ignoreMerges && [string match "*[string range $b 0 15]*" [.tagwrite.f.msg cget -text]]}
destroy .tagwrite

# Bundles: counts only the artifacts, not the header.
check "artifactCount" {[histops::artifactCount "mtime: 2026-10-07\nproject-code: 1234abcd5678ef90\n------\n1234567890abcdef  manifest\n  abcdef0123456789 file x\n"] == 2}
cd $co
set f [open $co/zz-b.txt w]; puts $f bundle; close $f
exec fossil add zz-b.txt
exec fossil commit --branch zz-b -m "A bundle test" --nosync --no-prompt
cd $T(dir)
set ci [lindex [sql "SELECT b.uuid FROM tagxref x JOIN blob b ON b.rid=x.rid WHERE x.tagtype>0 AND x.value='zz-b' AND x.tagid=(SELECT tagid FROM tag WHERE tagname='branch')"] 0 0]
set ::saveTo $T(tmp)/zz.bundle
whenOpen .tagwrite { set histops::bundle(standalone) 1; set tagwrite::answer 1 }
histops::exportBundle $R zz-b
set ::openFrom $T(tmp)/zz.bundle
set ls [exec fossil bundle ls $T(tmp)/zz.bundle -R $O]
set n [llength [regexp -all -inline -line {^[0-9a-f]{10,}} $ls]]
# Import --force: asked again; refused there, nothing imported.
set ::boxes {}
set ::answers {"Import a bundle of another project?" cancel}
steps {{[winfo exists .tagwrite.f.force]} {set histops::bundle(force) 1; set tagwrite::answer 1}}
histops::importBundle $O
check "--force asked, refused: not imported" {[lindex $::boxes 0] eq "Import a bundle of another project?" && ![llength [sql "SELECT 1 FROM blob WHERE uuid='$ci' AND size>=0" $O]]}
set ::answers {}
steps {{[winfo exists .tagwrite.f.force]} {set histops::bundle(force) 1; set tagwrite::answer 1}}
histops::importBundle $O
check "--force: imported" {[llength [sql "SELECT 1 FROM blob WHERE uuid='$ci' AND size>=0" $O]]}
# Removed: its dry run, the count; not into the graveyard (the bundle
# brings them back).
set before [llength [split [string trim [exec fossil purge list -R $O]] \n]]
set ::confirms {}
histops::purgeBundle $O
set c [lindex $::confirms 0]
check "remove: $n artifacts, not the graveyard, dry run" {[string match "*($n artifacts in it)*do not go to the*graveyard*importing the bundle again*" [lindex $c 1]] && [string match "*Dry run:*Purged artifacts found in the bundle*" [lindex $c 2]] && $n > 0}
check "removed, graveyard as before" {![llength [sql "SELECT 1 FROM blob WHERE uuid='$ci' AND size>=0" $O]] && [llength [split [string trim [exec fossil purge list -R $O]] \n]] == $before}

# Purge the branch (in the checkout, not on it), then obliterate that
# purge in the graveyard (asked first; cancelled once).
exec fossil update main --nosync --chdir $co
set before [llength [split [string trim [exec fossil purge list -R $R]] \n]]
set ::confirms {}
tkbranches::reload; update
tkbranches::fillBranchMenu .branches.ctx zz-b
.branches.ctx.advanced invoke "Purge the branch\u2026"
check "branch purged, dry run first" {[string match "*Dry run*" [lindex $::confirms 0 2]] && ![llength [sql "SELECT 1 FROM blob WHERE uuid='$ci' AND size>=0"]] && ![info exists tkbranches::branches(zz-b)]}
histops::graveyard $R
update
set g .graveyard.f.t
check "graveyard: the purge newest" {[llength [$g children {}]] == $before + 1}
set id [histops::graveSelected]
set ::answers [list "Obliterate purge $id?" cancel]
histops::graveObliterate $R
check "cancelled: kept" {[llength [$g children {}]] == $before + 1}
set ::answers {}
set ::boxes {}
histops::graveObliterate $R
check "obliterated (asked: [lindex $::boxes 0])" {[lindex $::boxes 0] eq "Obliterate purge $id?" && [llength [$g children {}]] == $before && ![$g exists p$id]}
destroy .graveyard

# Switch without merging: cancelled, nothing; then the checkout is at
# core-8-6-branch and its files as they were (edits, new files).
set was [checkoutRid]
set label "the last check-in of core-8-6-branch"
set ::answers [list "Switch the checkout to $label without changing its files?" cancel]
histops::switchKeep $R $co core-8-6-branch $label
check "cancelled: as before" {[checkoutRid] == $was}
set f [open $co/README.md a]; puts $f edited; close $f
set f [open $co/zz-new.txt w]; puts $f new; close $f
set ::answers {}
check "switched" {[histops::switchKeep $R $co core-8-6-branch $label]}
set tip86 [lindex [sql "SELECT x.rid FROM tagxref x JOIN event e ON e.objid=x.rid WHERE x.tagtype>0 AND x.value='core-8-6-branch' AND x.tagid=(SELECT tagid FROM tag WHERE tagname='branch') ORDER BY e.mtime DESC LIMIT 1"] 0 0]
check "at core-8-6-branch, files kept" {[checkoutRid] == $tip86 && [file exists $co/zz-new.txt] && [string match "*edited*" [exec cat $co/README.md]]}
done
