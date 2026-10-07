# A context menu for every list: a right-click on a row selects it and
# posts the menu (entries mirror the window's buttons); on a scratch copy
# (only menus are made, nothing is changed).
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
set ::posted {}
proc tk_popup {m x y args} { set ::posted $m }
start tickets $W/co
proc rclick {w {item ""}} {
    set ::posted {}
    update
    if {[winfo class $w] eq "Listbox"} {
        lassign [$w bbox 0] x y
    } else {
        if {$item eq ""} { set item [lindex [$w children {}] 0] }
        $w see $item; update
        set n 0
        while {[$w bbox $item] eq "" && [incr n] < 50} { update; after 20 }
        lassign [$w bbox $item] x y
    }
    event generate $w <ButtonPress-3> -x [expr {$x + 5}] -y [expr {$y + 3}] -rootx 10 -rooty 10
    update
    return $::posted
}
proc labels {m} {
    set r {}
    if {$m eq ""} { return $r }
    for {set i 0} {$i <= [$m index end]} {incr i} {
        if {[$m type $i] eq "command"} { lappend r [$m entrycget $i -label] }
    }
    return $r
}
proc menuCheck {name w want {item ""}} {
    set m [rclick $w $item]
    set l [labels $m]
    set missing [lmap x $want { if {$x in $l} continue; set x }]
    check "$name: [join $l /]" {$m ne "" && ![llength $missing]}
}
# Tabs.
tktaalik::show tags; update
menuCheck Tags .tags.main.list.t {"Show in Timeline" "Copy name" "Copy check-in"}
set first [lindex [.tags.main.list.t children {}] 0]
check "the row clicked is selected" {[.tags.main.list.t selection] eq [list $first]}
tktaalik::show wiki; update
menuCheck Wiki .wiki.main.list.t {"Edit…" "Open in browser" "Copy name"}
tktaalik::show forum; update
if {[llength [.forum.main.list.t children {}]]} {
    menuCheck Forum .forum.main.list.t {"Open in browser" "Copy title"}
}
tktaalik::show stash; update
if {[llength [.stash.main.list.t children {}]]} {
    menuCheck Stash .stash.main.list.t {"Copy comment"}
}
tktaalik::show branches; update
.branches.main.list.t selection set [list core-8-6-branch]; update
set nb .branches.main.details.nb
$nb select $nb.tickets; update
if {[llength [$nb.tickets.t children {}]]} {
    menuCheck "Branch tickets" $nb.tickets.t {"Show the ticket" "Copy ticket id"}
}
# Windows.
tkusers::window; update
menuCheck Users .users.main.list.t {"Edit…" "Copy user name"}
# The menu mirrors the buttons: a special user cannot be the default.
set m [rclick .users.main.list.t nobody]
set i [lsearch -exact [labels $m] "Make default user…"]
check "Users: the state of the button" {[$m entrycget [expr {$i}] -state] eq "disabled"}
wm withdraw .users
exec fossil remote https://example.invalid/tk -R $W/tk.fossil
tkremotes::window; update
menuCheck Remotes .remotes.list.t {"Open in browser" "Copy URL"}
wm withdraw .remotes
tksettings::window; update
menuCheck Settings .settings.main.list.t {"Set for this repository" "Copy name"}
wm withdraw .settings
ticketreports::window; update
menuCheck "Reports list" .reports.main.list {Run}
.reports.main.list selection clear 0 end; .reports.main.list selection set 3; event generate .reports.main.list <<ListboxSelect>>; update
menuCheck "Report rows" .reports.main.out.t {"Show the ticket" "Copy row"}
wm withdraw .reports
help::show index; update
menuCheck "Manual contents" .help.main.toc.t {"Open all" "Copy link"}
wm withdraw .help
goto::window; update
set goto::text [lindex [fossil::sql $W/tk.fossil "SELECT substr(uuid,1,4) FROM blob GROUP BY substr(uuid,1,4) HAVING count(*)>2 LIMIT 1"] 0 0]
goto::go; update
menuCheck "Go to" .goto.list.t {"Go to it" "Copy name"}
wm withdraw .goto
set w [diffview::show "x" "--- a\n+++ a\n@@ -1 +1 @@\n-x\n+y\n--- b\n+++ b\n@@ -1 +1 @@\n-x\n+y\n"]
update
menuCheck "Diff files" $w.p.files.t {"Copy file name" "Copy its diff"}
destroy $w
# Dialogs with check lists: Check all, Uncheck all.
set f [open $W/co/zz-extra.txt w]; puts $f x; close $f
tktaalik::show commit; update
whenOpen .commit.clean {
    set t .commit.clean.f.opts.list.t
    menuCheck "Delete unmanaged files" $t {"Check all" "Uncheck all" "Copy path"}
    tkcommit::cleanAll 1; update
    set ::unchecked [llength [array names tkcommit::cleanSkip]]
    tkcommit::cleanAll 0; update
    set ::rechecked [llength [array names tkcommit::cleanSkip]]
    # (Cancel: nothing deleted.)
    set tkcommit::answer(.commit.clean) 0
}
tkcommit::cleanFiles
check "Uncheck all: $::unchecked unchecked; Check all: $::rechecked" {$::unchecked >= 1 && $::rechecked == 0 && [file exists $W/co/zz-extra.txt]}
# A heading: the menu of the columns, not of a row.
tktaalik::show tags; update
set ::posted {}
lassign [.tags.main.list.t bbox [lindex [.tags.main.list.t children {}] 0]] x y
event generate .tags.main.list.t <ButtonPress-3> -x 20 -y 5 -rootx 10 -rooty 10; update
check "heading: not the row menu ($::posted)" {$::posted ne ".tags.main.list.t.popup"}
done
