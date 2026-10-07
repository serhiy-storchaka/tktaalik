# The Timeline: tag:NAME (every check-in with the tag, propagated too),
# is:open, is:closed (leaves); the relations of a check-in in its details
# (parents, merged from, children, merged into, its state), links; the
# description from the nearest tag; Show artifact.  Read only.
source [file join [file dirname [info script]] common.tcl]
start timeline "" 1100x800
tktaalik::show timeline; update
set t .timeline.main.list.t
proc rows {q} {
    set tktimeline::query $q
    tktimeline::search
    after cancel tktimeline::search
    if {[.timeline.status cget -foreground] eq "red3"} { return [list error $tktimeline::status] }
    lmap i [.timeline.main.list.t children {}] { set i }
}
# tag: a tag on one check-in; a propagating one (tip-466 on revised_text).
set r [rows tag:core-9-0-2]
set want [lindex [sql "SELECT rid FROM tagxref WHERE tagtype>0 AND tagid=(SELECT tagid FROM tag WHERE tagname='sym-core-9-0-2')"] 0 0]
check "tag:core-9-0-2: $r" {$r eq $want}
set r [rows "tag:tip-466 kind:ci"]
set n [lindex [sql "SELECT count(*) FROM tagxref WHERE tagtype>0 AND tagid=(SELECT tagid FROM tag WHERE tagname='sym-tip-466')"] 0 0]
check "tag:tip-466: [llength $r] of $n (propagated)" {[llength $r] == min($n, 1000) && $n > 1}
set r [rows "tag:core-9-0-*"]
check "tag:GLOB: [llength $r]" {[llength $r] >= 3}
# is:open, is:closed: leaves.
set closedTag [lindex [sql "SELECT tagid FROM tag WHERE tagname='closed'"] 0 0]
set r [rows is:closed]
set bad [sql "SELECT count(*) FROM event e WHERE objid IN ([join $r ,]) AND (objid NOT IN (SELECT rid FROM leaf) OR NOT EXISTS (SELECT 1 FROM tagxref WHERE rid=e.objid AND tagid=$closedTag AND tagtype>0))"]
check "is:closed: [llength $r], all closed leaves" {[llength $r] > 0 && [lindex $bad 0 0] == 0}
set r [rows is:open]
set bad [sql "SELECT count(*) FROM event e WHERE objid IN ([join $r ,]) AND (objid NOT IN (SELECT rid FROM leaf) OR EXISTS (SELECT 1 FROM tagxref WHERE rid=e.objid AND tagid=$closedTag AND tagtype>0))"]
check "is:open: [llength $r], all open leaves" {[llength $r] > 0 && [lindex $bad 0 0] == 0}
check "is:nonsense: an error naming them" {[lindex [rows is:nonsense] 0] eq "error" && [string match "*is:open, is:closed*" $tktimeline::status]}
# The relations of a merge check-in.
set m [lindex [rows "is:merge date:2025"] 0]
$t selection set [list $m]; update
set d .timeline.main.details.text
set text [$d get 1.0 end]
check "relations: Parent, Merged from" {[string match "*Parent: *" $text] && [string match "*Merged from: *" $text]}
check "Child or State" {[regexp {\n(Child|Children): } $text] || [string match "*State: *" $text]}
check "describe in the details" {[regexp {\nDescribe: \S+} $text]}
# A link: the parent in the Timeline.
set parent [lindex [sql "SELECT b.uuid FROM plink p JOIN blob b ON b.rid=p.pid WHERE p.cid=$m AND p.isprim"] 0 0]
set i [$d search [string range $parent 0 9] 1.0]
check "the parent is a link" {"link" in [$d tag names $i]}
$d see $i; update
lassign [$d bbox $i] x y
event generate $d <Motion> -x [expr {$x + 2}] -y [expr {$y + 2}]; update
event generate $d <1> -x [expr {$x + 2}] -y [expr {$y + 2}]; update
check "clicked: the parent ([list $tktimeline::query])" {$tktimeline::query eq "hash:[string range $parent 0 15]"}
# A leaf: its state.
set leaf [lindex [rows is:open] 0]
$t selection set [list [lindex [rows "hash:[string range [lindex [sql "SELECT uuid FROM blob WHERE rid=$leaf"] 0 0] 0 15]"] 0]]; update
check "a leaf: State: leaf, open" {[string match "*State: leaf, open*" [$d get 1.0 end]]}
# Show artifact: a window with the manifest.
set uuid [lindex [sql "SELECT uuid FROM blob WHERE rid=$m"] 0 0]
histops::showArtifact $T(repo) $uuid; update
check "Show artifact: the manifest" {[winfo exists .artifact] && [string match "*\nU *" [.artifact.f.t get 1.0 end]] && [string match "*\nZ *" [.artifact.f.t get 1.0 end]]}
destroy .artifact
# The context menu: Show artifact, Save as archive; no Update without a checkout.
proc tk_popup {m x y args} { set ::posted $m }
set r [lindex [rows "kind:ci"] 0]
$t see $r; update
lassign [$t bbox $r] x y
event generate $t <ButtonPress-3> -x [expr {$x + 5}] -y [expr {$y + 3}] -rootx 10 -rooty 10; update
set labels {}
for {set i 0} {$i <= [$::posted index end]} {incr i} { catch {lappend labels [$::posted entrycget $i -label]} }
check "menu: Show artifact, Save as archive" {"Show artifact" in $labels && "Save as archive…" in $labels}
set i -1
for {set k 0} {$k <= [$::posted index end]} {incr k} {
    if {![catch {$::posted entrycget $k -label} l] && $l eq "Update checkout to this check-in…"} { set i $k }
}
check "Update disabled without a checkout" {$i >= 0 && [$::posted entrycget $i -state] eq "disabled"}
done
