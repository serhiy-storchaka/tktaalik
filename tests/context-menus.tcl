# What the context menu of a tab's main list does, its menu bar does too
# (for the row selected), but for the filters (Search ..., Exclude ...):
# they only change the rows shown.  On a scratch copy, with a change and a
# stash.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
set f [open $W/co/README.md a]; puts $f "context menus"; close $f
fossilIn $W/co stash snapshot -m "context menus"
proc tk_popup {m x y args} { set ::posted $m }
# The labels of M and of its cascades.
proc entries {m} {
    catch {uplevel #0 [$m cget -postcommand]}
    set r {}
    if {[$m index end] eq "none"} { return $r }
    for {set i 0} {$i <= [$m index end]} {incr i} {
        switch [$m type $i] {
            command - checkbutton - radiobutton { lappend r [$m entrycget $i -label] }
            cascade { lappend r {*}[entries [$m entrycget $i -menu]] }
        }
    }
    return $r
}
# The same action under another label in the menu bar (where the menu
# says whose: "these files" of the menu of a file...).
set same {
    "Undo for these files…" "Undo for the selected files…"
    "Redo for these files…" "Redo for the selected files…"
    "Copy names" "Copy names of the selected files"
    Content "Content of the file"
    Blame "Blame of the file"
    "Open in browser" "Open the file in browser"
    "Copy path" "Copy the file's path"
    "Find in its history…" "Find in the file's history…"
}
start timeline $W/co 1300x900
foreach {tab w} {timeline .timeline.main.list.t tickets .tickets.main.list.t branches .branches.main.list.t
        tags .tags.main.list.t files .files.main.tree.t commit .commit.main.files.t stash .stash.main.list.t
        wiki .wiki.main.list.t forum .forum.main.list.t} {
    tktaalik::show $tab; update
    waitUntil {[winfo exists $w] && [llength [$w children {}]]}
    # (Files: a file, not a directory.)
    set item [lindex [lsearch -all -inline -glob [$w children {}] [expr {$tab eq "files" ? "f:*" : "*"}]] 0]
    $w see $item; update
    waitUntil {[llength [$w bbox $item]]}
    lassign [$w bbox $item] x y bw
    set ::posted ""
    event generate $w <ButtonPress-3> -x [expr {$x + $bw / 2}] -y [expr {$y + 3}] -rootx 10 -rooty 10; update
    if {$::posted eq ""} { check "$tab: a context menu" 0; continue }
    set bar {}
    for {set i 0} {$i <= [.menubar index end]} {incr i} {
        if {[.menubar type $i] eq "cascade"} { lappend bar {*}[entries [.menubar entrycget $i -menu]] }
    }
    set missing {}
    set filters {}
    foreach label [entries $::posted] {
        set filter [regexp {^(Search|Exclude|Filter|Threads started by) } $label]
        set other [expr {[dict exists $same $label] ? [dict get $same $label] : ""}]
        set inBar [expr {$label in $bar || ($other ne "" && $other in $bar)}]
        if {$filter && $inBar} { lappend filters $label }
        if {!$filter && !$inBar} {
            # (A label with the row's name: History of README.md...)
            if {![string match "History of *" $label] || "History of the file" ni $bar} { lappend missing $label }
        }
    }
    check "$tab: in the menu bar too: missing [list $missing]" {![llength $missing]}
    check "$tab: no filters there: [list $filters]" {![llength $filters]}
}
done
