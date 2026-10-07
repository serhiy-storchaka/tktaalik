# Files: the history of a file under its earlier names too, its context
# menu (diff, content and blame of a version, browser, copy), the menu
# entry, Back.
source [file join [file dirname [info script]] common.tcl]
set ::browsed {}
start files "" 1300x800
tktaalik::show files; update
set tkfiles::version main; tkfiles::showVersion; update
set tree .files.main.tree.t
set h .files.main.right.nb.history.t
$tree selection set [list f:README.md]; update
.files.main.right.nb select .files.main.right.nb.history; update
set names [lsort -unique [dict values $tkfiles::names]]
check "names: $names" {$names eq {README README.md}}
set n [lindex [fossil::sql $T(repo) "SELECT count(DISTINCT m.mid) FROM mlink m WHERE NOT m.isaux AND m.fnid=(SELECT fnid FROM filename WHERE name='README.md')"] 0 0]
check "more than the versions as README.md: [llength [$h children {}]] > $n" {[llength [$h children {}]] > $n}
check "the name column shown" {"name" in [$h cget -displaycolumns]}
set dates [lmap i [$h children {}] {$h set $i date}]
check "newest first" {$dates eq [lsort -decreasing $dates]}
set old [lindex [$h children {}] end]
check "the oldest: README, [$h set $old how]" {[$h set $old name] eq "README" && [$h set $old how] eq "added"}
set ren [lmap i [$h children {}] {expr {[$h set $i how] eq "renamed" ? $i : [continue]}}]
check "renamed: [llength $ren] ([$h set [lindex $ren end] name])" {[llength $ren] > 0 && [$h set [lindex $ren end] name] eq "README.md"}

# The context menu (tk_popup stubbed).
rename tk_popup realPopup
proc tk_popup {m args} { set ::menu $m }
proc menuFor {item} {
    global h
    $h see $item; update
    for {set i 0} {$i < 20 && [$h bbox $item] eq ""} {incr i} { after 50 {set ::w 1}; vwait ::w; update }
    lassign [$h bbox $item] x y
    tkfiles::historyMenu [expr {$x + 5}] [expr {$y + 5}] 0 0
    set labels {}
    for {set i 0} {$i <= [$::menu index end]} {incr i} {
        if {[$::menu type $i] eq "command"} { lappend labels [$::menu entrycget $i -label] }
    }
    return $labels
}
set labels [menuFor $old]
check "menu: [join $labels /]" {$labels eq [list "Diff against the previous version" "Show the check-in in Timeline" "Content of this version" "Blame of this version" "Save this version\u2026" "Open in browser" "Copy check-in" "Copy file hash"]}
set ::diffs {}
proc diffview::run {title args} { lappend ::diffs [list $title $args] }
$::menu invoke 0
check "diff under the old name: [lindex $::diffs end]" {[string match "README in *" [lindex $::diffs end 0]] && [lindex $::diffs end 1 end] eq "README"}
$::menu invoke [$::menu index "Copy check-in"]
check "copied: [clipboard get]" {[clipboard get] eq $old}

# Save an old version (the file dialog stubbed).
proc tk_getSaveFile {args} { set ::saveArgs $args; return $::T(tmp)/saved-README }
$::menu invoke [$::menu index "Save this version*"]
set f [open $T(tmp)/saved-README]; set saved [read $f]; close $f
set want [lindex [fossil::run cat -R $T(repo) -r $old README] 1]
check "saved README at [string range $old 0 9]: [string length $saved] bytes" {$saved ne "" && [string trim $saved] eq [string trim $want] && [dict get $::saveArgs -initialfile] eq "README"}

# Content of an old version: README at that check-in.
menuFor $old
$::menu invoke [$::menu index "Content of this version"]; update
set c .files.main.right.nb.content.t
check "title: [.files.main.right.title cget -text]" {[.files.main.right.title cget -text] eq "README at [string range $old 0 9]"}
check "content tab shown, the old text" {[.files.main.right.nb select] eq [winfo parent $c] && [$c get 1.0 end] ne "" && [string first README [$c get 1.0 end]] >= 0}
set oldText [$c get 1.0 end]
# Back: the newest content again; Forward: the old one.
tktaalik::goBack; update
check "Back: the history, README.md" {[.files.main.right.title cget -text] eq "README.md" && [.files.main.right.nb select] eq ".files.main.right.nb.history"}
.files.main.right.nb select [winfo parent $c]; update
check "  its content: the tree's" {[$c get 1.0 end] ne $oldText}
tktaalik::goForward; update
check "Forward: the old version again" {[.files.main.right.title cget -text] eq "README at [string range $old 0 9]" && [$c get 1.0 end] eq $oldText}

# Browser.
set newest [lindex [$h children {}] 0]
menuFor $newest
if {$tkfiles::remote ne ""} {
    $::menu invoke [$::menu index "Open in browser"]
    check "browser: [lindex $::browsed end]" {[lindex $::browsed end] eq "$tkfiles::remote/file?name=README.md&ci=$newest"}
}

# The File menu entry: back to the history at the tree's version.
.files.menu.file invoke [.files.menu.file index "History of the file"]; update
check "File \u25b8 History of the file" {[.files.main.right.nb select] eq ".files.main.right.nb.history" && [.files.main.right.title cget -text] eq "README.md"}

# The tree's context menu.
$tree see f:README.md; update
for {set i 0} {$i < 20 && [$tree bbox f:README.md] eq ""} {incr i} { after 50 {set ::w 1}; vwait ::w; update }
lassign [$tree bbox f:README.md] x y
tkfiles::treeMenu [expr {$x + 5}] [expr {$y + 5}] 0 0
check "tree menu: [$::menu entrycget 0 -label]" {[$::menu entrycget 0 -label] eq "History of README.md"}

# A file never renamed: no name column.
$tree selection set [list f:generic/tk.h]; update
.files.main.right.nb select .files.main.right.nb.history; update
check "generic/tk.h: one name, no name column ([llength [$h children {}]] versions)" {"name" ni [$h cget -displaycolumns] && [llength [$h children {}]] > 10}
done
