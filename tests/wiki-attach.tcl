# The Wiki tab: attachments of pages and technotes (fossil attachment add,
# on a scratch copy), listed under the page; view, save, browse.
source [file join [file dirname [info script]] common.tcl]
proc lseq0 {n} { set r {}; for {set i 0} {$i <= $n} {incr i} { lappend r $i }; return $r }
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set R $W/tk.fossil
fossil::run remote https://example.invalid/tk -R $R
set ::boxes {}
set ::answer ok
proc tk_getOpenFile {args} { return $::openFiles }
set ::browsed {}
set ::viewed {}
rename diffview::show realShow
proc diffview::show {title text args} { lappend ::viewed [list $title $text $args] }
file mkdir $T(tmp)/in
foreach {name text} {notes.txt "first notes\n" data.patch "--- a\n+++ b\n"} {
    set f [open $T(tmp)/in/$name w]; puts -nonewline $f $text; close $f
}
set f [open $T(tmp)/in/blob.bin wb]; puts -nonewline $f "x\0y"; close $f
# A technote to attach to (its ID is the attachment's target).
set f [open $T(tmp)/note.txt w]; puts $f "A note"; close $f
fossil::run wiki create "Release notes" $T(tmp)/note.txt -t "2026-10-01 10:00:00" -R $R

start tickets $R 1000x700
tktaalik::show wiki; update
set t .wiki.main.list.t
set p .wiki.main.page
set att $p.att.tv
set page "wiki-Migrating scripts to Tk 9"
$t selection set [list $page]; update
check "a page without attachments: no list" {![winfo ismapped $p.att] && [$p.head.attach instate !disabled]}

# Attach two files (cancelled first).
set ::openFiles [list $T(tmp)/in/notes.txt $T(tmp)/in/data.patch]
set ::answer cancel
tkwiki::attach; update
check "cancelled: nothing attached" {[llength [$att children {}]] == 0}
set ::answer ok
set ::boxes {}
tkwiki::attach; update
check "confirmation: [lindex $::boxes 0]" {[string match "Attach notes.txt, data.patch to the page Migrating scripts to Tk 9?" [lindex $::boxes 0]]}
set rows [lmap i [$att children {}] {$att item $i -values}]
check "listed: $rows" {[llength $rows] == 2 && [lindex $rows 0 0] eq "notes.txt" && [lindex $rows 1 0] eq "data.patch" && [winfo ismapped $p.att]}
set user [string trim [lindex [fossil::run user default -R $R] 1]]
check "as the default user ($user)" {[lindex $rows 0 2] eq $user}
set db [fossil::sql $R "SELECT target, filename FROM attachment WHERE isLatest AND src<>'' AND target='Migrating scripts to Tk 9' ORDER BY filename"]
check "in the repository: $db" {[llength $db] == 2}

# View, save, browse.
tkwiki::openAttachment 0; update
check "viewed: $::viewed" {[lindex $::viewed end 0] eq "notes.txt" && [string trim [lindex $::viewed end 1]] eq "first notes"}
check "kept above the main window: [lindex $::viewed end 2]" {[lindex $::viewed end 2] eq {-transient .}}
set ::saveTo $T(tmp)/saved.txt
set a $tkwiki::attached(0)
tkwiki::saveAttachment [dict get $a src] [dict get $a name]
set f [open $::saveTo]; set saved [read $f]; close $f
check "saved" {$saved eq "first notes\n"}
tkwiki::browseAttachment notes.txt
check "browse: [lindex $::browsed end]" {[lindex $::browsed end] eq "https://example.invalid/tk/attachview?page=Migrating%20scripts%20to%20Tk%209&file=notes.txt"}
# The context menu.
rename tk_popup realPopup
proc tk_popup {m args} { set ::menu $m }
set bbox [$att bbox 0]
tkwiki::attachmentMenu $att [expr {[lindex $bbox 0] + 5}] [expr {[lindex $bbox 1] + 5}] 0 0
check "menu: [lmap i {0 1 3 4} {$::menu entrycget $i -label}]" {[$::menu entrycget 0 -label] eq "View" && [$::menu entrycget 3 -label] eq "Open in browser"}

# The same name again: replaces it (asked).
set f [open $T(tmp)/in/notes.txt w]; puts -nonewline $f "second notes\n"; close $f
set ::openFiles [list $T(tmp)/in/notes.txt]
set ::boxes {}
tkwiki::attach; update
check "replacing said: [lindex $::boxes 0]" {[llength $::boxes] == 1}
set rows [lmap i [$att children {}] {$att item $i -values}]
check "still two: [lmap r $rows {lindex $r 0}]" {[llength $rows] == 2}
set i [lsearch -index 0 $rows notes.txt]
tkwiki::openAttachment $i
check "the new content" {[string trim [lindex $::viewed end 1]] eq "second notes"}

# A binary file: its icon; not viewed (View disabled), a double-click
# opens it on the server.
set ::openFiles [list $T(tmp)/in/blob.bin]
tkwiki::attach; update
set i [lsearch -index 0 [lmap i [$att children {}] {$att item $i -values}] blob.bin]
check "binary: its kind and icon" {[dict get $tkwiki::attached($i) kind] eq "binary"
    && [$att item $i -image] eq [icons::get a-binary row]}
check "the text file's icon" {[$att item [lsearch -index 0 [lmap i [$att children {}] {$att item $i -values}] notes.txt] -image] eq [icons::get a-text row]}
set ::boxes {}
set ::browsed {}
set n [llength $::viewed]
tkwiki::openAttachment $i
check "binary: not shown, the server instead: [lindex $::browsed end]" \
    {[llength $::viewed] == $n && [string match "*attachview?page=*&file=blob.bin" [lindex $::browsed end]]}
set bbox [$att bbox $i]
tkwiki::attachmentMenu $att [expr {[lindex $bbox 0] + 5}] [expr {[lindex $bbox 1] + 5}] 0 0
check "binary: View disabled" {[$::menu entrycget View -state] eq "disabled"}

# Another page: its own (none).
$t selection set [list "wiki-Fixing old binary attachments"]; update
check "another page: none" {![winfo ismapped $p.att]}

# A technote: by its ID.
tkwiki::reload; update
set note [lindex [lmap i [$t children {}] {if {[string match event-* $i]} {set i} else continue}] 0]
check "a technote: $note" {$note ne ""}
$t selection set [list $note]; update
set ::openFiles [list $T(tmp)/in/data.patch]
set ::boxes {}
tkwiki::attach; update
check "confirmation: [lindex $::boxes 0]" {[lindex $::boxes 0] eq "Attach data.patch to the technote \"Release notes\"?"}
set id [string range $note 6 end]
set db [fossil::sql $R "SELECT filename FROM attachment WHERE target=[fossil::sqlstr $id] AND isLatest"]
check "attached to the technote: $db" {$db eq "data.patch" && [llength [$att children {}]] == 1}
tkwiki::browseAttachment data.patch
check "browse: [lindex $::browsed end]" {[lindex $::browsed end] eq "https://example.invalid/tk/attachview?technote=$id&file=data.patch"}

# No page shown: disabled.
$t selection set {}; tkwiki::showPage ""; update
check "nothing shown: disabled, no list" {[$p.head.attach instate disabled] && ![winfo ismapped $p.att]}
# Back to the page: its attachments.
$t selection set [list $page]; update
check "back: [llength [$att children {}]] attachments" {[llength [$att children {}]] == 3}

# Deleted (Delete... in the menu): no longer listed, a record without
# content; first cancelled.
check "Delete... in the menu" {"Delete\u2026" in [lmap i [lseq0 [.wiki.attctx index end]] {
    expr {[.wiki.attctx type $i] eq "separator" ? "--" : [.wiki.attctx entrycget $i -label]}}]}
set before [llength [$att children {}]]
set gone [$att set [lindex [$att children {}] 0] file]
set ::answer cancel
tkwiki::deleteAttachment $gone
check "cancelled: still $before" {[llength [$att children {}]] == $before}
set ::answer ok
set ::boxes {}
tkwiki::deleteAttachment $gone
check "asked: [lindex $::boxes end]" {[string match "Delete the attachment $gone of the page*" [lindex $::boxes end]]}
check "deleted: [lmap i [$att children {}] {$att set $i file}]" \
    {[llength [$att children {}]] == $before - 1 && $gone ni [lmap i [$att children {}] {$att set $i file}]}
set db [fossil::sql $R "SELECT count(*) FROM attachment WHERE target='Migrating scripts to Tk 9'
    AND filename=[fossil::sqlstr $gone] AND isLatest AND coalesce(src,'')=''"]
check "a record without content: $db" {$db == 1}
done
