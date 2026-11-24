# The Forum tab: threads, the posts of one threaded, links, Back.
source [file join [file dirname [info script]] common.tcl]
need forum
set ::browsed {}
start tickets $T(forum) 1000x800
check "a tab: [.nb tab .forum -text]" {[.nb tab .forum -text] eq "Forum"}
tktaalik::show forum; update
set t .forum.main.list.t
set n [lindex [fossil::sql $T(forum) "SELECT count(DISTINCT froot) FROM forumpost"] 0 0]
check "threads: [llength [$t children {}]] of $n, $tkforum::status" {[llength [$t children {}]] == min($n, 1000) && [string match "*$n threads" $tkforum::status]}
set lasts [lmap i [$t children {}] {$t set $i last}]
check "newest activity first" {$lasts eq [lsort -decreasing $lasts]}
check "the first selected, shown" {[$t selection] eq [lrange [$t children {}] 0 0] && $tkforum::selected eq [$t selection]}
if {$n > 1000} {
    .forum.b.more invoke; update
    check "More: [llength [$t children {}]]" {[llength [$t children {}]] == min($n, 2000)}
}

# The thread of the Fossil forum's tests (rid 7 there), as its copy in the
# repository the tests make has it: its posts by their number in it, in
# the order they were posted.
set root [lindex [fossil::sql $T(forum) "SELECT f.froot FROM forumpost f JOIN event e ON e.objid=f.fpid
    WHERE e.comment LIKE '%New thread for testing%' ORDER BY f.fmtime LIMIT 1"] 0 0]
set order [concat {*}[fossil::sql $T(forum) "SELECT fpid FROM forumpost WHERE froot=$root ORDER BY fmtime"]]
proc numbered {posts} { lmap p $posts { lreplace $p 0 0 [lsearch $::order [lindex $p 0]] } }

# The filter: the title or the starter.
set tkforum::filter "new thread for testing"; after 400 {set ::w 1}; vwait ::w
check "filter: [lmap i [$t children {}] {$t set $i title}]" {[$t exists $root] && [llength [lsearch -all -inline -not [lmap i [$t children {}] {string tolower [$t set $i title]}] "*new thread for testing*"]] == 0}

# A thread with replies to replies and edits (also edits of the post a
# reply answers): each post once, as its newest version, after the post it
# answers, in the order they were first posted.
$t selection set $root; update
set d .forum.main.thread.text
check "the title: [$d get 1.0 1.end]" {[$d get 1.0 1.end] eq [$t set $root title]}
# (In the Fossil forum: {13 0 1} {8 1 0} {12 2 1} {15 3 1} {21 3 1} {19 4 0}
# {20 3 0} {22 4 0} {10 1 0} {17 1 0}, by rid.)
check "posts: [numbered $tkforum::posts]" {[numbered $tkforum::posts] eq {{5 0 1} {1 1 0} {4 2 1} {7 3 1} {12 3 1} {10 4 0} {11 3 0} {13 4 0} {3 1 0} {8 1 0}}}
set started [lindex [fossil::sql $T(forum) "SELECT strftime('%Y-%m-%d %H:%M', fmtime) FROM forumpost WHERE fpid=$root"] 0 0]
check "started: [$t set $root started], when the first post was ($started), not its edit" {[$t set $root started] eq $started}
check "posts in the list: [$t set $root posts]" {[$t set $root posts] == 10}
set m [lsort -unique [lmap p $tkforum::posts {lindex [$d tag cget head[lindex $p 1] -lmargin1] 0}]]
check "indented by depth: $m" {[llength $m] == 5}
check "edited marked" {[llength [$d search -all ", edited " 1.0 end]] == 4}
set text [$d get 1.0 end]
check "no artifact cards left" {![regexp -line {^[DHNUWZ] } $text]}

# Open in browser: the thread.
.forum.b.browse invoke
set uuid [lindex [fossil::sql $T(forum) "SELECT uuid FROM blob WHERE rid=$root"] 0 0]
check "browse: $::browsed" {[string match "*/forumpost/[string range $uuid 0 15]" [lindex $::browsed end]]}

# A link to a post of another thread opens it here, at that post; Back.
set other [lindex [fossil::sql $T(forum) "SELECT f.froot, b.uuid FROM forumpost f JOIN blob b ON b.rid=f.fpid
    WHERE f.froot<>$root AND f.firt IS NOT NULL AND f.fpid NOT IN (SELECT fprev FROM forumpost WHERE fprev IS NOT NULL)
    ORDER BY f.fpid DESC LIMIT 1"] 0]
lassign $other froot puuid
tkforum::followLink /forumpost/[string range $puuid 0 15]; update
check "linked thread: $tkforum::selected (filter cleared)" {$tkforum::selected == $froot && [$t selection] eq $froot && $tkforum::filter eq ""}
check "at the post" {[dict exists $tkforum::marks $puuid] && [$d compare @0,0 <= [dict get $tkforum::marks $puuid]] && [$d bbox [dict get $tkforum::marks $puuid]] ne ""}
tktaalik::goBack; update; update
check "Back: thread $root, filter [list $tkforum::filter]" {$tkforum::selected == $root && $tkforum::filter eq "new thread for testing"}
tktaalik::goForward; update; update
check "Forward: $tkforum::selected" {$tkforum::selected == $froot}
tkforum::followLink https://example.org/x
check "other links: the browser" {[lindex $::browsed end] eq "https://example.org/x"}

# (htmltext: an ordered list's number, not a number from expr.)
text .ol
htmltext::insert .ol "<ol><li>one</li><li>two</li></ol>"
check "ordered list: [string map [list \t <TAB>] [.ol get 1.0 end-1c]]" {[string match "1.\tone\n2.\ttwo*" [.ol get 1.0 end-1c]]}

# A repository without a forum.
tktaalik::openPath $T(repo); update
tktaalik::show forum; update
check "no forum: $tkforum::status" {[llength [$t children {}]] <= 1}
done
