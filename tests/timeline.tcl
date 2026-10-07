# The Timeline tab: views, search terms, details.
source [file join [file dirname [info script]] common.tcl]
proc diffview::run {title args} { lappend ::diffs [list $title $args] }
proc q {text {view all}} {
    set tktimeline::view $view
    set tktimeline::query $text
    tktimeline::search 1
    after cancel {tktimeline::search}
    update
    if {[.timeline.status cget -foreground] eq "red3"} { puts "   ERROR for $text: $tktimeline::status"; return {} }
    .timeline.main.list.t children {}
}
proc rows {} { lmap id [.timeline.main.list.t children {}] { set tktimeline::rows($id) } }
proc all {list script} { foreach r $list { if {![uplevel 1 [list apply [list r $script] $r]]} { puts "   counter-example: $r"; return 0 } }; return 1 }
set repo $T(repo)
start timeline $repo 1200x800
set t .timeline.main.list.t
puts "status: $tktimeline::status"
puts "tabs: [lmap v {all lastpull outgoing} {.timeline.tabs.$v cget -text}]"
puts "title: [wm title .]  menu: [. cget -menu]"
set n [llength [q ""]]
set total [lindex [tktimeline::sql "SELECT count(*) FROM event"] 0 0]
check "all: $n rows of $total" {$n == min(1000, $total) && [string match "*newest of $total*" $tktimeline::status]}
check "newest first" {[lsort -decreasing [lmap r [rows] {dict get $r date}]] eq [lmap r [rows] {dict get $r date}]}
tktimeline::more; update
check "more: [llength [$t children {}]]" {[llength [$t children {}]] == min(2000, $total)}
set got [q kind:ticket]
check "kind:ticket ([llength $got])" {[all [rows] {expr {[dict get $r type] eq "t"}}]}
set got [q {kind:ci user:@me}]
check "my check-ins ([llength $got])" {[llength $got] > 0 && [all [rows] {expr {[dict get $r type] eq "ci" && [dict get $r user] eq $tktimeline::me}}]}
set got [q branch:core-8-6-branch]
check "branch: ([llength $got])" {[llength $got] > 0 && [all [rows] {expr {[dict get $r branch] eq "core-8-6-branch"}}]}
set got [q {branch:x11-* date:2026-09}]
check "branch glob and date ([llength $got])" {[all [rows] {expr {[string match x11-* [dict get $r branch]] && [string match 2026-09-* [dict get $r date]]}}]}
set got [q ticket:4eef1fa86e]
check "ticket: changes and check-ins ([llength $got]: [lsort -unique [lmap r [rows] {dict get $r type}]])" {[lsort -unique [lmap r [rows] {dict get $r type}]] eq {ci t}}
set got [q harfbuzz]
set exp [lindex [tktimeline::sql "SELECT count(*) FROM event WHERE lower(coalesce(ecomment,comment)) LIKE '%harfbuzz%'"] 0 0]
check "word: [llength $got] = SQL $exp" {[llength $got] == min($exp, 2000)}
set got [q {100%}]
check "% is literal ([llength $got])" {[all [rows] {expr {[string first "100%" [dict get $r comment]] >= 0}}]}
set got [q {in:core-9-0-3 -in:core-9-0-2 kind:ci}]
puts "  9.0.3 minus 9.0.2: [llength $got] check-ins, branches [lsort -unique [lmap r [rows] {dict get $r branch}]]"
set exp [lindex [tktimeline::sql "WITH RECURSIVE a(rid) AS (SELECT (SELECT rid FROM tagxref WHERE tagtype>0 AND tagid=(SELECT tagid FROM tag WHERE tagname='sym-core-9-0-3'))
    UNION SELECT plink.pid FROM plink JOIN a ON plink.cid=a.rid), b(rid) AS (SELECT (SELECT rid FROM tagxref WHERE tagtype>0 AND tagid=(SELECT tagid FROM tag WHERE tagname='sym-core-9-0-2'))
    UNION SELECT plink.pid FROM plink JOIN b ON plink.cid=b.rid) SELECT count(*) FROM event WHERE type='ci' AND objid IN a AND objid NOT IN b"] 0 0]
check "release range = SQL ($exp)" {[llength $got] == $exp}
set got [q {in:2cf953f38c kind:ci date:2026-10-04}]
check "in:HASH: ancestors of the check-in itself" {[llength $got] > 0 && [all [rows] {string match 2026-10-04* [dict get $r date]}]}
set first [lindex [rows] end]
set got2 [q {in:core-9-0-2 kind:ci}]
check "ancestor sets differ" {[llength $got2] > 0}
set got [q pull:1]
set lp [q "" lastpull]
check "pull:1 = Last pull view ([llength $got])" {$got eq $lp}
set out [q "" outgoing]
set unsent [lindex [tktimeline::sql "SELECT count(*) FROM event WHERE objid IN (SELECT rid FROM unsent)"] 0 0]
check "outgoing = unsent events ($unsent)" {[llength $out] == $unsent}
# errors
foreach {bad expect} {kind:foo {use kind:} date:2026-13 {bad date} foo:bar {unknown key} pull:x {pull:1} ticket:xyz {not a ticket}} {
    set tktimeline::query $bad; tktimeline::search; after cancel {tktimeline::search}; update
    check "error $bad: $tktimeline::status" {[string match "*$expect*" $tktimeline::status] && [.timeline.status cget -foreground] eq "red3"}
}
# details
q {kind:ci hash:2cf953f38c}
set rid [lindex [$t children {}] 0]
$t selection set $rid; update
set text [.timeline.main.details.text get 1.0 end]
check "check-in details: files" {[string match "*1 file*changed*tests/unixButton.test*" $text]}
check "buttons: [lmap b [winfo children .timeline.main.details.buttons] {$b cget -text}]" {[lmap b [winfo children .timeline.main.details.buttons] {$b cget -text}] eq {Diff {Show branch} {Open in browser}}}
set ::diffs {}
tktimeline::activateRow $rid
check "double-click: diff $::diffs" {[string match "*--checkin 2cf953f38c*" $::diffs]}
q {kind:ticket ticket:4eef1fa86e}
$t selection set [lindex [$t children {}] end]; update
set text [.timeline.main.details.text get 1.0 end]
check "ticket change details: [string range [string map {\n |} $text] 0 120]" {[string match "*title:*" $text] || [string match "*icomment:*" $text] || [string match "*status:*" $text]}
q kind:tag
$t selection set [lindex [$t children {}] 0]; update
puts "  tag details: [string range [string map {\n |} [.timeline.main.details.text get 1.0 end]] 0 160]"
# links
q {kind:ci hash:2cf953f38c}
tktimeline::showBranch main; update
check "show branch: [list $tktaalik::active [.branches.main.list.t selection]]" {$tktaalik::active eq "branches" && [.branches.main.list.t selection] eq "main"}
tktimeline::showTicket 4eef1fa86e; update
check "show ticket: [list $tktaalik::active $tktsearch::query]" {$tktaalik::active eq "tickets" && $tktsearch::query eq "id:4eef1fa86e"}
tktaalik::show timeline; update
# context menu
set rid [lindex [$t children {}] 0]
lassign [$t bbox $rid] x y
event generate $t <ButtonPress-3> -x [expr {$x+20}] -y [expr {$y+5}] -rootx 200 -rooty 200; update
set labels {}
for {set i 0} {$i <= [.timeline.ctx index end]} {incr i} { lappend labels [expr {[.timeline.ctx type $i] eq "separator" ? "--" : [.timeline.ctx entrycget $i -label]}] }
tk::MenuUnpost .timeline.ctx
puts "  context menu: $labels"
check "context menu" {"Diff" in $labels && "Search user:serhiy.storchaka" in $labels}
tktimeline::saveConfig
set f [open $T(tmp)/tktimeline.conf]; set c [read $f]; close $f
check "config saved" {[dict exists $c table] && [dict get $c query] eq {kind:ci hash:2cf953f38c}}
done
