# The Timeline's search keys for what "fossil timeline" can select:
# path:, desc:, after:, before:, is:leaf, is:merge (and is:current,
# branch:@current: only with a checkout); the tags of a check-in in its
# details ("fossil tag list"); saving an artifact; no bisect without a
# checkout.
source [file join [file dirname [info script]] common.tcl]
start timeline "" 1000x700
tktaalik::show timeline; update
set t .timeline.main.list.t
proc rows {q} {
    set tktimeline::query $q
    tktimeline::search
    after cancel tktimeline::search
    if {[.timeline.status cget -foreground] eq "red3"} { return [list error $tktimeline::status] }
    lmap i [.timeline.main.list.t children {}] { set i }
}
set tag core-9-0-0
set rid [lindex [sql "SELECT rid FROM tagxref WHERE tagtype>0 AND tagid=(SELECT tagid FROM tag WHERE tagname='sym-$tag')"] 0 0]

# path: a file, a directory, a glob
set r [rows "path:generic/tkButton.c"]
set n [lindex [sql "SELECT count(DISTINCT m.mid) FROM mlink m JOIN filename f ON f.fnid=m.fnid WHERE f.name='generic/tkButton.c'"] 0 0]
check "path:file: [llength $r] of $n" {[llength $r] == min($n, 1000) && $n > 0}
set r [rows "path:library/ttk date:2025"]
set bad [sql "SELECT count(*) FROM event e WHERE e.objid IN ([join [lmap i $r {set i}] ,]) AND NOT EXISTS (SELECT 1 FROM mlink m JOIN filename f ON f.fnid=m.fnid WHERE m.mid=e.objid AND f.name GLOB 'library/ttk/*')"]
check "path:dir: [llength $r], all touch library/ttk/" {[llength $r] > 0 && $bad == 0}
set r [rows "path:*.test date:2025-01"]
check "path:glob: [llength $r]" {[llength $r] > 0}

# desc:, in: (ancestors), after:, before:
set r [rows "desc:$tag -after:core-9-0-1 kind:ci"]
check "desc:$tag: the check-in, and descendants after it" {$rid in $r && [llength $r] > 1}
set first [lindex [sql "SELECT min(e.mtime) FROM event e WHERE objid IN ([join $r ,])"] 0 0]
set at [lindex [sql "SELECT mtime FROM event WHERE objid=$rid"] 0 0]
check "desc: nothing before it" {$first >= $at}
set r [rows "after:$tag"]
set old [sql "SELECT count(*) FROM event WHERE objid IN ([join $r ,]) AND mtime<=$at"]
check "after:$tag: [llength $r] rows, none before" {[llength $r] > 0 && $old == 0 && $rid ni $r}
set r [rows "before:$tag date:2024"]
set new [sql "SELECT count(*) FROM event WHERE objid IN ([join $r ,]) AND mtime>=$at"]
check "before:$tag: none after" {[llength $r] > 0 && $new == 0}

# is:leaf, is:merge
set r [rows "is:leaf"]
set leaves [lindex [sql "SELECT count(*) FROM leaf"] 0 0]
check "is:leaf: [llength $r] of $leaves" {[llength $r] == min($leaves, 1000)}
set r [rows "is:merge date:2025"]
set m [sql "SELECT count(*) FROM event e WHERE objid IN ([join $r ,]) AND (SELECT count(*) FROM plink WHERE cid=e.objid)<2"]
check "is:merge: [llength $r], each with two parents or more" {[llength $r] > 0 && $m == 0}

# Without a checkout
check "is:current: an error" {[lindex [rows is:current] 0] eq "error" && [string match "*no checkout*" $tktimeline::status]}
check "branch:@current: an error" {[lindex [rows branch:@current] 0] eq "error"}
check "desc:current: an error" {[lindex [rows desc:current] 0] eq "error"}
# (Without a checkout too: described by SQL.)
set d [tktimeline::describe [lindex [sql "SELECT uuid FROM blob WHERE rid=$rid"] 0 0]]
check "describe without a checkout: $d" {$d ne ""}
set m .timeline.menu.bisect
tktimeline::bisectMenu $m
check "Bisect menu disabled" {[$m entrycget 0 -state] eq "disabled" && [$m entrycget [$m index end] -state] eq "disabled"}

# The tags of a check-in in the details
set r [rows "hash:[string range [lindex [sql "SELECT uuid FROM blob WHERE rid=$rid"] 0 0] 0 11]"]
$t selection set $rid; update
set d [.timeline.main.details.text get 1.0 end]
check "details: Tags: ... $tag" {[regexp "Tags: \[^\n\]*$tag" $d] && [regexp {branch=\S} $d]}
set tags [tktimeline::checkinTags $rid]
check "checkinTags: $tag its own, the branch inherited" {[lsearch -index 0 $tags $tag] >= 0 && [lindex [lsearch -index 0 -inline $tags $tag] 3] == 0}

# The context menu of a check-in
event generate $t <ButtonPress-3> -x 50 -y [lindex [$t bbox $rid] 1] -rootx 100 -rooty 100
update
set labels {}
for {set i 0} {$i <= [.timeline.ctx index end]} {incr i} {
    if {[.timeline.ctx type $i] ne "separator"} { lappend labels [.timeline.ctx entrycget $i -label] }
}
tk::MenuUnpost .timeline.ctx
check "context menu: [join $labels /]" {"Edit check-in\u2026" in $labels && "Add tag\u2026" in $labels && "Cancel tag" in $labels && "Bisect" in $labels && "Advanced" in $labels && "Save artifact\u2026" in $labels}
check "Bisect disabled without a checkout" {[.timeline.ctx entrycget Bisect -state] eq "disabled"}
set cancels {}
for {set i 0} {$i <= [.timeline.ctx.cancel index end]} {incr i} { lappend cancels [.timeline.ctx.cancel entrycget $i -label] }
check "Cancel tag: $cancels" {"$tag\u2026" in $cancels}

# Save artifact ("fossil artifact HASH FILE")
set file $T(tmp)/artifact.txt
set ::saveTo $file
tktimeline::saveArtifact $rid
set text [read [set f [open $file]]]; close $f
check "artifact saved: [string length $text] bytes" {[string match "*\nP *" $text] && [string match "*\nZ *" $text]}
done
