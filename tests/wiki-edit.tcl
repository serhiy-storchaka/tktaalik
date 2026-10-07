# The Wiki tab: saving a version; creating and editing pages and
# technotes (fossil wiki create|commit, on a scratch copy).
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set R $W/tk.fossil
set ::boxes {}
tktaalik::main tickets [list $R]
update
tktaalik::show wiki; update
set t .wiki.main.list.t
# Fill in the editor as the user would, then Commit.
proc edit {mode fields text {more {}}} {
    after 300 [list apply {{fields text more} {
        foreach {var value} $fields { set tkwiki::$var $value }
        set s .wiki.edit.f.editor.nb.src.t
        $s delete 1.0 end
        $s insert end $text
        set tkwiki::editDone ok
        if {$more ne ""} { after 300 $more }
    }} $fields $text $more]
    tkwiki::editor $mode
    update
}
proc artifactOf {tag} {
    lindex [tkwiki::artifact [lindex [lindex [fossil::sql $::R "SELECT b.uuid FROM tag t JOIN tagxref x\
        ON x.tagid=t.tagid JOIN blob b ON b.rid=x.rid WHERE t.tagname=[fossil::sqlstr $tag]\
        ORDER BY x.mtime DESC LIMIT 1"] 0] 0]] 0
}

# A new page, then an edit of it.
edit newpage {editName "Test Page" editFormat Markdown} "# Hello\n\nworld"
check "new page: shown, Markdown" {$tkwiki::shown eq "wiki-Test Page" && [dict get [artifactOf "wiki-Test Page"] N] eq "text/x-markdown"}
check "rendered: [string trim [.wiki.main.page.text get 1.0 end]]" {[string match "Hello*world*" [string trim [.wiki.main.page.text get 1.0 end]]]}
edit edit {} "# Hello\n\nchanged"
check "edited: 2 versions, new text" {[llength $tkwiki::versions] == 2 && [string match "*changed*" [.wiki.main.page.text get 1.0 end]]}
# The preview.
whenOpen .wiki.edit {
    .wiki.edit.f.editor.nb.src.t insert end "\n\n**bold**"
    .wiki.edit.f.editor.nb select .wiki.edit.f.editor.nb.pre
    update
    set ::previewed [.wiki.edit.f.editor.nb.pre.t get 1.0 end]
    set tkwiki::editDone cancel
}
tkwiki::editor edit; update
check "preview: rendered, no markup" {[string match "*bold*" $::previewed] && ![string match "*\\*\\*bold*" $::previewed] && [llength $tkwiki::versions] == 2}
# The same name again: refused.
set ::boxes {}
edit newpage {editName "Test Page" editFormat Markdown} "x" {set tkwiki::editDone cancel}
check "same name: refused ([lindex $::boxes 0])" {[string match "*already*" [lindex $::boxes 0]]}

# A technote, then an edit of it: the date, tags and color stay.
edit newnote {editComment "Release notes" editDate "2026-10-01 12:00:00" editTags "release, news"
    editColor "#ffe0e0" editFormat "Fossil wiki"} "Released."
set note $tkwiki::shown
set cards [artifactOf $note]
check "new technote: [dict get $tkwiki::pages($note) title], [dict get $tkwiki::pages($note) date]" {[string match event-* $note] && [dict get $tkwiki::pages($note) title] eq "Release notes" && [dict get $tkwiki::pages($note) date] eq "2026-10-01 12:00" && [tkwiki::noteTags $cards] eq {{news, release} #ffe0e0}}
edit edit {editComment "Release notes, final"} "Released, final."
set cards [artifactOf $note]
check "edited technote: same ID and date, tags and color kept" {$tkwiki::shown eq $note && [llength $tkwiki::versions] == 2 && [lindex [dict get $cards E] 0] eq "2026-10-01T12:00:00" && [lindex [dict get $cards E] 1] eq [string range $note 6 end] && [tkwiki::noteTags $cards] eq {{news, release} #ffe0e0} && [dict get $cards C] eq "Release notes, final"}
set ::boxes {}
edit newnote {editComment "Another" editDate "2026-10-01 12:00:00" editFormat "Fossil wiki"} "x" {set tkwiki::editDone cancel}
check "same date: refused ([lindex $::boxes 0])" {[string match "*Another technote has the date*" [lindex $::boxes 0]]}

# A page with CRLF line ends (as from the web editor): edited without the
# CRs, committed with them; the diff shows only the line changed.
set f [open $T(tmp)/crlf w]
fconfigure $f -translation binary
puts -nonewline $f "line one\r\nline two\r\nline three\r\n"
close $f
exec fossil wiki create "Web Page" $T(tmp)/crlf -R $R
tkwiki::reload; update
$t selection set [list "wiki-Web Page"]; update
whenOpen .wiki.edit {
    set ::edited [.wiki.edit.f.editor.nb.src.t get 1.0 "end - 1 char"]
    .wiki.edit.f.editor.nb.src.t replace 2.0 "2.0 lineend" "line 2"
    set tkwiki::editDone ok
}
tkwiki::editor edit; update
check "edited without CRs" {[string first "\r" $::edited] < 0 && [string match "line one\nline two*" $::edited]}
set stored [lindex [tkwiki::artifact [lindex [lindex $tkwiki::versions 0] 0]] 1]
check "stored with CRLF again" {$stored eq "line one\r\nline 2\r\nline three\r\n"}
set ::diffs {}
rename diffview::show realShow
proc diffview::show {title text args} { lappend ::diffs $text }
.wiki.main.page.head.changes invoke; update
rename diffview::show {}
rename realShow diffview::show
set text [lindex $::diffs end]
check "the diff: only that line, no CRs" {[string first "\r" $text] < 0 && [regexp -all -line {^[-+][^-+]} $text] == 2 && [string match "*-line two\n+line 2*" $text]}

# Saving the version shown.
$t selection set [list "wiki-Test Page"]; update
set ::saveTo $T(tmp)/page.md
tkwiki::save
set f [open $::saveTo]; fconfigure $f -encoding utf-8; set c [read $f]; close $f
check "saved source" {$c eq "# Hello\n\nchanged"}
set ::saveTo $T(tmp)/page.html
tkwiki::save
set f [open $::saveTo]; set c [read $f]; close $f
check "saved HTML: [string length $c] bytes" {[string match "<!DOCTYPE html>*<title>Test Page</title>*<h1*>Hello</h1>*changed*</html>*" $c]}

# Without a default user: refused.
rename tkwiki::user realUser
proc tkwiki::user {} { return "" }
set ::boxes {}
tkwiki::editor newpage; update
check "no default user: refused" {[lindex $::boxes 0] eq "Changes need a user." && ![winfo exists .wiki.edit]}
rename tkwiki::user {}
rename realUser tkwiki::user
done
