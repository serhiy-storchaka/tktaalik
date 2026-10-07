# The Tags tab: tags of check-ins, branch names, cancelled tags; the
# history of a tag; to the Timeline and Branches tabs.
source [file join [file dirname [info script]] common.tcl]
set ::browsed {}
start tickets "" 1000x700
check "a tab after Branches: [lmap w [.nb tabs] {winfo name $w}]" {[lsearch [.nb tabs] .tags] == [lsearch [.nb tabs] .branches] + 1}
tktaalik::show tags; update
set t .tags.main.list.t
proc kinds {} { lsort -unique [lmap i [$::t children {}] {$::t set $i kind}] }
# (Tags: on check-ins, or propagating but not the name of a branch, like
# tip-466 on the revised_text branch.)
lassign [lindex [fossil::sql $T(repo) "SELECT count(*) FROM (SELECT tagid FROM tagxref\
    WHERE tagid IN (SELECT tagid FROM tag WHERE tagname GLOB 'sym-*') GROUP BY tagid\
    HAVING max(tagtype) = 1 OR (max(tagtype) = 2 AND NOT EXISTS (SELECT 1 FROM tagxref b\
        WHERE b.tagid=(SELECT tagid FROM tag WHERE tagname='branch')\
        AND b.value=(SELECT substr(tagname,5) FROM tag WHERE tag.tagid=tagxref.tagid))))"] 0] singles
check "tags of check-ins only: [llength [$t children {}]] of $singles" {[llength [$t children {}]] == $singles && [kinds] eq "Tag"}
.tags.top.branches invoke; update
check "with branch names: [kinds]" {"Branch" in [kinds] && [$t exists core-9-0-branch]}
.tags.top.cancelled invoke; update
check "with cancelled: [kinds]" {"Cancelled" in [kinds]}
.tags.top.branches invoke; .tags.top.cancelled invoke; update
set tktags::filter core-9-0; after 400 {set ::w 1}; vwait ::w
check "filter: [llength [$t children {}]]" {[llength [$t children {}]] > 0 && [llength [lsearch -all -inline -not [$t children {}] *core-9-0*]] == 0}
set tktags::filter ""; after 400 {set ::w 1}; vwait ::w

# A release tag: its check-in and history.
set uuid [lindex [fossil::sql $T(repo) "SELECT b.uuid FROM tagxref x JOIN tag t ON t.tagid=x.tagid\
    JOIN blob b ON b.rid=x.rid WHERE t.tagname='sym-core-9-0-4' AND x.tagtype=1"] 0 0]
$t selection set [list core-9-0-4]; update
set d [.tags.main.details.text get 1.0 end]
check "core-9-0-4: on [string range $uuid 0 9]" {[$t set core-9-0-4 hash] eq [string range $uuid 0 9] && [string match "*added to [string range $uuid 0 9]*" $d]}
check "buttons: Timeline on, Branches off" {![.tags.b.timeline instate disabled] && [.tags.b.branch instate disabled]}
.tags.b.timeline invoke; update
check "Show in Timeline: hash:[string range $uuid 0 9]" {$tktaalik::active eq "timeline" && $tktimeline::query eq "hash:[string range $uuid 0 9]" && [dict get $tktimeline::rows([lindex [.timeline.main.list.t selection] 0]) uuid] eq $uuid}
set tktags::remote https://example.invalid/tk
.tags.b.browse invoke
check "Open in browser: [lindex $::browsed end]" {[lindex $::browsed end] eq "https://example.invalid/tk/timeline?t=core-9-0-4"}

# A branch name: to the Branches tab.
.tags.top.branches invoke; update
$t selection set [list core-9-0-branch]; update
check "branch: Branches on, Timeline off" {![.tags.b.branch instate disabled] && [.tags.b.timeline instate disabled]}
.tags.b.branch invoke; update
check "Show in Branches: core-9-0-branch" {$tktaalik::active eq "branches" && [lindex [.branches.main.list.t selection] 0] eq "core-9-0-branch"}
done
