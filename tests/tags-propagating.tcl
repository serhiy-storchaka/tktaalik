# A propagating tag (tag add --propagate) can be cancelled: on its own
# check-in, from a descendant on ("from here on"), in the Tags tab; it is
# not taken for a branch name.  On a scratch copy.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set R $W/tk.fossil
proc tagwrite::confirm {args} { return 1 }
proc tk_popup {m x y args} { set ::posted $m }
# Two check-ins of main, one after the other.
lassign [lindex [fossil::sql $R "SELECT p.uuid, c.uuid FROM plink l JOIN blob p ON p.rid=l.pid JOIN blob c ON c.rid=l.cid
    WHERE l.isprim AND l.cid IN (SELECT objid FROM event WHERE type='ci' ORDER BY mtime DESC LIMIT 1 OFFSET 5)"] 0] parent child
exec fossil tag add --propagate qpropagated $parent -R $R
start tickets $R
# The Tags tab: a tag, not a branch; Cancel enabled.
tktaalik::show tags; update
check "kind: [dict get $tktags::tags(qpropagated) kind]" {[dict get $tktags::tags(qpropagated) kind] eq "Tag"}
check "main: still a branch" {[dict get $tktags::tags(main) kind] eq "Branch"}
.tags.main.list.t selection set [list qpropagated]; update
check "Cancel enabled" {[.tags.b.cancel instate !disabled]}
# The Timeline's Cancel tag menu: on the check-in, and from a descendant.
tktaalik::show timeline; update
proc cancelLabels {uuid} {
    tktimeline::setQuery hash:[string range $uuid 0 15]; update
    set t .timeline.main.list.t
    set rid [lindex [$t children {}] 0]
    $t selection set [list $rid]; update
    lassign [$t bbox $rid] x y
    event generate $t <ButtonPress-3> -x [expr {$x + 5}] -y [expr {$y + 3}] -rootx 10 -rooty 10; update
    set m $::posted.cancel
    set r {}
    for {set i 0} {$i <= [$m index end]} {incr i} { lappend r [$m entrycget $i -label] }
    return $r
}
set own [cancelLabels $parent]
check "its check-in: [join $own /]" {"qpropagated…" in $own && "main…" ni $own}
set inherited [cancelLabels $child]
check "a descendant: [join $inherited /]" {"qpropagated (from here on)…" in $inherited && [lsearch -glob $inherited "main*"] < 0}
# Edit check-in offers it too.
check "Edit check-in: own propagating tags" {"qpropagated" in [lmap r [fossil::sql $R "SELECT substr(t.tagname,5) FROM tagxref x JOIN tag t ON t.tagid=x.tagid
    WHERE x.rid=(SELECT rid FROM blob WHERE uuid='$parent') AND x.tagtype>0 AND x.origid=x.rid AND t.tagname GLOB 'sym-*'"] {lindex $r 0}]}
# Cancel it in the Tags tab: gone from the check-in and its descendants.
tktaalik::show tags; update
.tags.main.list.t selection set [list qpropagated]; update
tktags::cancelTag; update
set left [fossil::sql $R "SELECT count(*) FROM tagxref WHERE tagtype>0 AND tagid=(SELECT tagid FROM tag WHERE tagname='sym-qpropagated')"]
check "cancelled: [lindex $left 0 0] check-ins left with it" {[lindex $left 0 0] == 0}
done
