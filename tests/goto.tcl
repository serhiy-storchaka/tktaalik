# Go to (Ctrl+G): hashes, ticket ids, tags and branches, each shown where
# it belongs; several to choose from; Back.
source [file join [file dirname [info script]] common.tcl]
set R $T(repo)
start tickets $R 1200x800
proc sql1 {q} { lindex [fossil::sql $::R $q] 0 }
proc go {text} {
    goto::window; update
    set goto::text $text
    goto::go; update; update
}
# The File menu and Ctrl+G.
set m .tickets.menu.file
set labels {}
for {set i 0} {$i <= [$m index end]} {incr i} {
    if {[$m type $i] eq "command"} { lappend labels [$m entrycget $i -label] }
}
check "in the File menu" {"Go to…" in $labels}
focus -force .tickets.top.q; update
event generate .tickets.top.q <Control-g>; update
check "Ctrl+G opens it" {[winfo exists .goto] && [winfo ismapped .goto]}
wm withdraw .goto

# A check-in (a prefix of it): the Timeline.
set ci [lindex [sql1 "SELECT uuid FROM blob WHERE rid=(SELECT objid FROM event WHERE type='ci' ORDER BY mtime DESC LIMIT 1 OFFSET 30)"] 0]
go [string range $ci 0 11]
check "check-in: $tktaalik::active, [list $tktimeline::query]" {$tktaalik::active eq "timeline" && $tktimeline::query eq "hash:[string range $ci 0 15]" && ![winfo ismapped .goto]}
# As a link, and as [hash].
go https://core.tcl-lang.org/tk/info/[string range $ci 0 9]
check "a link" {$tktimeline::query eq "hash:[string range $ci 0 15]"}
tktaalik::show tickets
go "\[[string range $ci 0 9]\]"
check "\[hash\]" {$tktaalik::active eq "timeline"}

# A tag: the check-in it is on; a branch: the Branches tab.
go core-9-0-2
set tagged [lindex [sql1 "SELECT b.uuid FROM tagxref x JOIN blob b ON b.rid=x.rid WHERE x.tagtype>0 AND x.tagid=(SELECT tagid FROM tag WHERE tagname='sym-core-9-0-2') ORDER BY x.mtime DESC LIMIT 1"] 0]
check "tag: [list $tktimeline::query]" {$tktaalik::active eq "timeline" && $tktimeline::query eq "hash:[string range $tagged 0 15]"}
go core-8-6-branch
check "branch: [.branches.main.list.t selection]" {$tktaalik::active eq "branches" && [.branches.main.list.t selection] eq "core-8-6-branch"}

# A ticket id; a change of a ticket: the ticket.
set tkt [lindex [sql1 "SELECT tkt_uuid FROM ticket ORDER BY tkt_mtime DESC LIMIT 1 OFFSET 5"] 0]
go [string range $tkt 0 9]
check "ticket: $tktsearch::shownTicket" {$tktaalik::active eq "tickets" && $tktsearch::shownTicket eq $tkt}
lassign [sql1 "SELECT b.uuid, t.tagname FROM event e JOIN blob b ON b.rid=e.objid JOIN tagxref x ON x.rid=e.objid JOIN tag t ON t.tagid=x.tagid AND t.tagname GLOB 'tkt-*' WHERE e.type='t' ORDER BY e.mtime DESC LIMIT 1 OFFSET 3"] chg tag
go [string range $chg 0 11]
check "ticket change: its ticket" {$tktsearch::shownTicket eq [string range $tag 4 end]}

# An old version of a wiki page: the page at that version.
lassign [sql1 "SELECT b.uuid, t.tagname FROM tag t JOIN tagxref x ON x.tagid=t.tagid JOIN blob b ON b.rid=x.rid WHERE t.tagname='wiki-Migrating scripts to Tk 9' ORDER BY x.mtime LIMIT 1 OFFSET 1"] old page
go [string range $old 0 11]
after 300 {set ::w 1}; vwait ::w; update
set n [lindex [sql1 "SELECT count(*) FROM tagxref WHERE tagid=(SELECT tagid FROM tag WHERE tagname='wiki-Migrating scripts to Tk 9')"] 0]
check "wiki version: $tkwiki::shown, [list $tkwiki::version]" {$tktaalik::active eq "wiki" && $tkwiki::shown eq $page && [string match "2  *" $tkwiki::version]}

# A file's content: the Files tab at the first check-in with it.
set blob [lindex [sql1 "SELECT b.uuid FROM mlink m JOIN blob b ON b.rid=m.fid JOIN filename n ON n.fnid=m.fnid WHERE n.name='README.md' ORDER BY m.mid DESC LIMIT 1"] 0]
go [string range $blob 0 11]
after 500 {set ::w 1}; vwait ::w; update
check "file: $tkfiles::file" {$tktaalik::active eq "files" && $tkfiles::file eq "README.md" && [.files.main.right.nb select] eq ".files.main.right.nb.content"}

# An attachment: the ticket it is on.
lassign [sql1 "SELECT src, target FROM attachment WHERE src<>'' AND isLatest AND target IN (SELECT tkt_uuid FROM ticket) AND src IN (SELECT uuid FROM blob WHERE size>=0) ORDER BY mtime DESC LIMIT 1"] src target
go [string range $src 0 11]
check "attachment: its ticket" {$tktaalik::active eq "tickets" && $tktsearch::shownTicket eq $target}

# A forum post.
set post [lindex [sql1 "SELECT b.uuid FROM forumpost f JOIN blob b ON b.rid=f.fpid LIMIT 1"] 0]
if {$post ne ""} {
    go [string range $post 0 11]
    check "forum post" {$tktaalik::active eq "forum" && $tkforum::selected ne ""}
}

# Fossil's other names, through "fossil whatis".
set tip [lindex [sql1 "SELECT b.uuid FROM event e JOIN blob b ON b.rid=e.objid WHERE e.type='ci' ORDER BY e.mtime DESC LIMIT 1"] 0]
go tip
check "tip: [list $tktimeline::query]" {$tktaalik::active eq "timeline" && $tktimeline::query eq "hash:[string range $tip 0 15]"}
go 2026-09-01
set dated [lindex [sql1 "SELECT b.uuid FROM event e JOIN blob b ON b.rid=e.objid WHERE e.type='ci' AND e.mtime<=julianday('2026-09-01 23:59:59') ORDER BY e.mtime DESC LIMIT 1"] 0]
check "a date: the check-in of that day ([string range $dated 0 9])" {$tktimeline::query eq "hash:[string range $dated 0 15]"}
tktaalik::show tickets
goto::window; update
set goto::text root:core-8-6-branch
goto::go; update
check "root:core-8-6-branch: [list $tktimeline::query]" {$tktaalik::active eq "timeline" && [string match hash:* $tktimeline::query]}
set items [goto::find tip]
check "named as asked: [lindex $items 0 1]" {[string match "tip (*)" [lindex $items 0 1]]}
check "an option-like name: nothing, nothing run" {[goto::find -R] eq ""}
wm withdraw .goto

# Several: listed to choose.
set amb [lindex [sql1 "SELECT substr(uuid,1,4) FROM blob WHERE uuid IN (SELECT uuid FROM blob b JOIN event e ON e.objid=b.rid WHERE e.type='ci') GROUP BY substr(uuid,1,4) HAVING count(*)>1 LIMIT 1"] 0]
tktaalik::show tickets
go $amb
set rows [.goto.list.t children {}]
check "several: [llength $rows] listed, $goto::status" {[llength $rows] > 1 && [winfo ismapped .goto] && $tktaalik::active eq "tickets"}
set first [lindex $rows 0]
set want [.goto.list.t set $first name]
goto::choose $first; update
check "chosen: $want" {![winfo ismapped .goto]}
# Nothing.
go no-such-name-at-all
check "nothing: $goto::status" {[string match "Nothing named*" $goto::status] && [winfo ismapped .goto]}
wm withdraw .goto
# History: Back returns to where we were.
set before $tktaalik::active
tktaalik::show tickets; update
go [string range $ci 0 11]
tktaalik::goBack; update; update
check "Back: $tktaalik::active" {$tktaalik::active eq "tickets"}
check "history of texts: [lrange $goto::history 0 1]" {[lindex $goto::history 0] eq [string range $ci 0 11]}
done
