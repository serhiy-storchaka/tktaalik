# Ctrl+C in the lists copies what their selected rows are, and the copy
# buttons of the details copy what they follow; the menus have no Copy
# entries for them.  On a scratch copy, with a change and a stash (only
# read).
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
set f [open $W/co/README.md a]; puts $f "copy keys"; close $f
fossilIn $W/co stash snapshot -m "copy keys"
start timeline $W/co 1300x900
# Ctrl+C in W with ITEMS selected (the first row by default): what it
# copied, or "" for nothing.
proc ctrlC {w {items ""}} {
    if {$items eq ""} { set items [lrange [$w children {}] 0 0] }
    $w selection set $items
    clipboard clear
    focus -force $w; update
    event generate $w <Control-c>; update
    if {[catch {clipboard get} s]} { return "" }
    return $s
}
proc pressCopy {b} {
    clipboard clear
    $b invoke
    if {[catch {clipboard get} s]} { return "" }
    return $s
}
proc rows {w} { waitUntil {[llength [$w children {}]]}; $w children {} }

# Timeline: the hash; the button after it in the details.
set t .timeline.main.list.t
set rid [lindex [rows $t] 0]
set uuid [dict get $tktimeline::rows($rid) uuid]
check "Timeline: Ctrl+C, the hash" {[ctrlC $t] eq $uuid}
check "Timeline: the details' button" {[pressCopy .timeline.main.details.text.copyhash] eq $uuid}

# The ticket details' check-ins.
tktaalik::show tickets; update
set tktsearch::query {checkins:>=1}; tktsearch::search; update
.tickets.main.list.t selection set [lindex [rows .tickets.main.list.t] 0]; update
set nb .tickets.main.details.nb
$nb select $nb.checkins; update
set tv $nb.checkins.tv
check "Tickets: a check-in's hash" {[ctrlC $tv] eq [lindex [rows $tv] 0] && [string length [lindex [rows $tv] 0]] >= 40}

# Files: the path in the tree (also of a directory); the title's button.
tktaalik::show files; update
set tr .files.main.tree.t
rows $tr
set file [lindex [lsearch -all -inline -glob [$tr children {}] f:*] 0]
set dir [lindex [lsearch -all -inline -glob [$tr children {}] d:*] 0]
check "Files: Ctrl+C, a file's path" {[ctrlC $tr [list $file]] eq [string range $file 2 end]}
check "Files: a directory's path" {$dir eq "" || [ctrlC $tr [list $dir]] eq [string range $dir 2 end]}
$tr selection set [list $file]; update
check "Files: the title's button" {[.files.main.right.copy instate !disabled] && [pressCopy .files.main.right.copy] eq [string range $file 2 end]}

# Wiki: the name in the list and the title's button.
tktaalik::show wiki; update
set wl .wiki.main.list.t
set page [lindex [rows $wl] 0]
set name [$wl set $page title]
check "Wiki: Ctrl+C, the name: $name" {[ctrlC $wl] eq $name}
check "Wiki: the title's button" {[pressCopy .wiki.main.page.head.copy] eq $name}

# Forum (if the repository has one): the title; the title and link buttons.
tktaalik::show forum; update
set fl .forum.main.list.t
if {[llength [$fl children {}]]} {
    set th [lindex [$fl children {}] 0]
    set title [dict get $tkforum::threads($th) title]
    check "Forum: Ctrl+C, the title" {[ctrlC $fl] eq $title}
    update
    check "Forum: the title's button" {[pressCopy .forum.main.thread.text.copytitle] eq $title}
    set lb .forum.main.thread.text.copylink
    if {$tkforum::remote eq ""} {
        check "Forum: no remote, the link's button disabled" {[$lb instate disabled]}
    } else {
        check "Forum: the link's button" {[string match "$tkforum::remote/forumpost/*" [pressCopy $lb]]}
    }
}

# Stash: the comment; the button after its check-in.
tktaalik::show stash; update
set sl .stash.main.list.t
set id [lindex [rows $sl] 0]
check "Stash: Ctrl+C, the comment" {[ctrlC $sl] eq [$sl set $id comment]}
check "Stash: the check-in's button" {[pressCopy .stash.main.details.text.copyhash] eq [dict get $tkstash::stashes($id) hash]}

# Commit: the paths of the files selected.
tktaalik::show commit; update
set cl .commit.main.files.t
check "Commit: Ctrl+C, the paths" {[ctrlC $cl] eq [lindex [rows $cl] 0] && [string match *README.md [ctrlC $cl]]}

# The windows of the Repository menu.
tkusers::window; update
set ul .users.main.list.t
set login [lindex [rows $ul] 0]
check "Users: Ctrl+C, the name" {[ctrlC $ul] eq $login}
check "Users: the name's button" {[pressCopy .users.main.details.text.copylogin] eq $login}
wm withdraw .users
tksettings::window; update
set sl .settings.main.list.t
set s [lindex [rows $sl] 0]
check "Settings: Ctrl+C, the name" {[ctrlC $sl] eq $s}
check "Settings: the name's button" {[pressCopy .settings.main.details.help.copyname] eq $s}
.settings.main.details.edit.value delete 1.0 end
.settings.main.details.edit.value insert end "some value"
check "Settings: the value's button" {[pressCopy .settings.main.details.edit.copy] eq "some value"}
wm withdraw .settings
exec fossil remote https://example.invalid/tk -R $W/tk.fossil
tkremotes::window; update
check "Remotes: Ctrl+C, the URL" {[ctrlC .remotes.list.t] eq "https://example.invalid/tk"}
wm withdraw .remotes
ticketreports::window; update
.reports.main.list selection clear 0 end; .reports.main.list selection set 3
event generate .reports.main.list <<ListboxSelect>>; update
set rl .reports.main.out.t
set r [lindex [rows $rl] 0]
check "Reports: Ctrl+C, the row" {[ctrlC $rl] eq [join [$rl item $r -values] \t]}
wm withdraw .reports
help::show index; update
set hl .help.main.toc.t
set h [lindex [rows $hl] 0]
check "Manual contents: the link: [ctrlC $hl]" {[string match *.md* [ctrlC $hl]]}
wm withdraw .help
goto::window; update
set goto::text [lindex [fossil::sql $W/tk.fossil "SELECT substr(uuid,1,4) FROM blob GROUP BY substr(uuid,1,4) HAVING count(*)>2 LIMIT 1"] 0 0]
goto::go; update
set gl .goto.list.t
set g [lindex [rows $gl] 0]
check "Go to: Ctrl+C, the name" {[ctrlC $gl] eq [lindex [dict get $goto::found $g] 1]}
wm withdraw .goto
set w [diffview::show "x" "--- a\n+++ a\n@@ -1 +1 @@\n-x\n+y\n--- b\n+++ b\n@@ -1 +1 @@\n-x\n+y\n"]
update
check "Diff: Ctrl+C, the file names" {[ctrlC $w.p.files.t [rows $w.p.files.t]] eq "a\nb"}
destroy $w
done
