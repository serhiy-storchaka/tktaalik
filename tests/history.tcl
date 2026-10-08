# Back and Forward across the tabs: filters, views, jumps between tabs, tab
# switches, typing in a search box, versions in Files, the File menu.
source [file join [file dirname [info script]] common.tcl]
proc tktimeline::openUrl {args} {}
start timeline "" 1270x900
proc where {} { list $tktaalik::active [tktaalik::location] }
proc tlRow {} { lindex [.timeline.main.list.t selection] 0 }
proc menuState {e} { .timeline.menu.file entrycget $e -state }
proc wait {ms} { after $ms {set ::w 1}; vwait ::w; update }
check "start: nothing to go back to" {![llength $tktaalik::back] && [menuState Back] eq "disabled"}

# Timeline: a filter from the context menu, Back, Forward.
set t .timeline.main.list.t
$t selection set [lindex [$t children {}] 3]; update
set row [tlRow]
set user [dict get $tktimeline::rows($row) user]
tktimeline::addTerm user $user 0; update
check "filter: query user:$user" {$tktimeline::query eq "user:$user" && [menuState Back] eq "normal"}
tktaalik::goBack; update
check "Back: empty query, row $row selected again" {$tktimeline::query eq "" && [tlRow] eq $row}
tktaalik::goForward; update
check "Forward: the filter again" {$tktimeline::query eq "user:$user"}
tktaalik::goBack; update

# A view button.
.timeline.tabs.lastpull invoke; update
check "view: lastpull" {$tktimeline::view eq "lastpull"}
tktaalik::goBack; update
check "Back: view all, row $row" {$tktimeline::view eq "all" && [tlRow] eq $row}

# Typing in the search box: one place for all of it.
set n [llength $tktaalik::back]
focus -force .timeline.top.q; update
foreach c {c o r e} { .timeline.top.q insert end $c; update; wait 120 }
wait 400
foreach c {- 8} { .timeline.top.q insert end $c; update; wait 120 }
wait 400
check "typing: query core-8, one new place ([expr {[llength $tktaalik::back] - $n}])" {$tktimeline::query eq "core-8" && [llength $tktaalik::back] == $n + 1}
event generate .timeline.top.q <Return>; update
focus .; update
tktaalik::goBack; update
check "Back after typing: empty query, row $row" {$tktimeline::query eq "" && [tlRow] eq $row}

# Jump to the Tickets tab from a ticket change, and back.
set tk ""
foreach id [$t children {}] {
    if {[dict get $tktimeline::rows($id) type] eq "t"} { set tk $id; break }
}
$t selection set $tk; $t see $tk; update
set ticket [dict get $tktimeline::rows($tk) ticket]
tktimeline::showTicket $ticket; update
check "jump: Tickets tab, id:[string range $ticket 0 9]" {$tktaalik::active eq "tickets" && $tktsearch::query eq "id:[string range $ticket 0 9]"}
tktaalik::goBack; update
check "Back: Timeline, row $tk" {$tktaalik::active eq "timeline" && [tlRow] eq $tk}
tktaalik::goForward; update; update
check "Forward: Tickets, the ticket" {$tktaalik::active eq "tickets" && [string match [string range $ticket 0 9]* $tktsearch::shownTicket]}

# A tab switch by the user; Branches: a filter and a view button.
.nb select .branches; update
check "tab switch: Branches" {$tktaalik::active eq "branches"}
set b .branches.main.list.t
set name [lindex [$b children {}] 1]
$b selection set $name; update
tkbranches::addTerm user [lindex [dict get $tkbranches::branches($name) users] 0] 0; update
check "Branches filter: $tkbranches::query" {[string match "*user:*" $tkbranches::query]}
tktaalik::goBack; update
check "Back: no filter, $name selected" {$tkbranches::query eq "is:open" && $tkbranches::selected eq $name}
.branches.tabs.closed invoke; update
tktaalik::goBack; update
check "Back from the closed view: open, $name" {$tkbranches::view eq "open" && $tkbranches::selected eq $name}
tktaalik::goBack; update
check "Back again: Tickets" {$tktaalik::active eq "tickets"}

# Files: another version.
tktaalik::show files; update
set before $tkfiles::shownVersion
set tkfiles::version core-9-0-0
focus -force .files.top.version; update
event generate .files.top.version <Return>; update
focus .; update
check "Files: version core-9-0-0 ($tkfiles::status)" {$tkfiles::shownVersion eq "core-9-0-0"}
tktaalik::goBack; update
check "Back: version [list $before]" {$tkfiles::shownVersion eq $before && $before ne "core-9-0-0"}

# Tags: a checkbox, a jump to the Timeline and back.
tktaalik::show tags; update
.tags.top.branches invoke; update
check "Tags: branch names shown" {$tktags::showBranches}
tktaalik::goBack; update
check "Back: not shown" {!$tktags::showBranches && $tktaalik::active eq "tags"}
.tags.main.list.t selection set [list core-9-0-4]; update
.tags.b.timeline invoke; update
check "Show in Timeline" {$tktaalik::active eq "timeline"}
tktaalik::goBack; update
check "Back: Tags, core-9-0-4" {$tktaalik::active eq "tags" && $tktags::selected eq "core-9-0-4"}

# Wiki: a link to another page; Back returns to the page, version, scroll.
tktaalik::show wiki; update
set wt .wiki.main.list.t
set p1 "wiki-Migrating scripts to Tk 9"
$wt selection set [list $p1]; update
set h .wiki.main.page.head
set tkwiki::version [lindex [$h.version cget -values] 1]
event generate $h.version <<ComboboxSelected>>; update
.wiki.main.page.text yview 20.0; update
set top [.wiki.main.page.text index @0,0]
tkwiki::followLink "/wiki?name=Tk+Source+Code"; update
check "link followed" {$tkwiki::shown eq "wiki-Tk Source Code"}
tktaalik::goBack; update; update
check "Back: the page, version 2 of the list, the scroll ($top)" {$tkwiki::shown eq $p1 && $tkwiki::version eq [lindex [$h.version cget -values] 1] && [.wiki.main.page.text index @0,0] eq $top}

# Another repository: a new history.
tktaalik::openPath $T(repo); update
check "new repository: no history" {![llength $tktaalik::back] && ![llength $tktaalik::forward]}
done
