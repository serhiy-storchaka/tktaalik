# The Wiki tab: pages, technotes, notes, versions, links.
source [file join [file dirname [info script]] common.tcl]
set ::browsed {}
start tickets "" 1000x700
check "a tab: [.nb tab .wiki -text]" {[.nb tab .wiki -text] eq "Wiki"}
tktaalik::show wiki; update
set t .wiki.main.list.t
set n [lindex [fossil::sql $T(repo) "SELECT count(*) FROM tag WHERE tagname GLOB 'wiki-*' OR tagname GLOB 'event-*'"] 0 0]
check "all pages: [llength [$t children {}]] of $n" {[llength [$t children {}]] == $n && $n > 0}
proc kinds {} { lsort -unique [lmap i [$::t children {}] {$::t set $i kind}] }
.wiki.top.notes invoke; update
check "Notes: [kinds]" {[llength [$t children {}]] > 0 && "Wiki" ni [kinds] && "Technote" ni [kinds]}
.wiki.top.wiki invoke; update
check "Wiki pages: [kinds]" {[kinds] eq "Wiki"}
.wiki.top.all invoke; update
set tkwiki::filter migrating; after 400 {set ::w 1}; vwait ::w
check "filter: [lmap i [$t children {}] {$t set $i title}]" {[llength [$t children {}]] >= 1 && [llength [lsearch -all -inline -not [lmap i [$t children {}] {string tolower [$t set $i title]}] *migrating*]] == 0}
set tkwiki::filter ""; after 400 {set ::w 1}; vwait ::w

# A Markdown page with versions.
set page "wiki-Migrating scripts to Tk 9"
$t selection set [list $page]; update
set d .wiki.main.page.text
check "shown: [.wiki.main.page.head.title cget -text], [llength $tkwiki::versions] versions" {[.wiki.main.page.head.title cget -text] eq "Migrating scripts to Tk 9" && [llength $tkwiki::versions] == [$t set $page count] && [llength $tkwiki::versions] > 1}
set heading 0
# (Font tags are ht-font-FONT-BIH: bold, italic, heading level.)
foreach tag [$d tag names] { if {[regexp {^ht-font-.*-[01][01][1-6]$} $tag] && [llength [$d tag ranges $tag]]} { set heading 1 } }
check "Markdown rendered: headings, no ## left" {$heading && ![string match "*\n## *" [$d get 1.0 end]]}
set newest [$d get 1.0 end]
set tkwiki::version [lindex [.wiki.main.page.head.version cget -values] end]
event generate .wiki.main.page.head.version <<ComboboxSelected>>; update
check "the first version: other text" {[$d get 1.0 end] ne $newest}

# Diffs of versions (the diff window stubbed).
set ::diffs {}
rename diffview::show realShow
proc diffview::show {title text args} { lappend ::diffs [list $title $text] }
set h .wiki.main.page.head
set vals [$h.version cget -values]
check "the first version: Changes off, Since on" {[$h.changes instate disabled] && ![$h.since instate disabled]}
$h.since invoke; update
lassign [lindex $::diffs end] title text
check "Since the first: [string range $title 0 70]" {[string match "Migrating scripts to Tk 9: version 1, *version [llength $vals], *" $title] && [string match "*--- Migrating scripts to Tk 9\tversion 1*+++ Migrating scripts to Tk 9\tversion [llength $vals]*" $text] && [regexp -line {^\+[^+]} $text]}
set tkwiki::version [lindex $vals 0]
event generate $h.version <<ComboboxSelected>>; update
check "the newest: Changes on, Since off" {![$h.changes instate disabled] && [$h.since instate disabled]}
$h.changes invoke; update
lassign [lindex $::diffs end] title text
check "Changes of the newest: [string range $title 0 70]" {[string match "*version [expr {[llength $vals] - 1}], *version [llength $vals], *" $title] && [regexp -line {^@@ } $text]}
rename diffview::show {}
rename realShow diffview::show

# Links.
check "a page link: [tkwiki::linkedPage /wiki?name=Migrating+scripts+to+Tk+9]" {[tkwiki::linkedPage /wiki?name=Migrating+scripts+to+Tk+9] eq $page && [tkwiki::linkedPage Migrating%20scripts%20to%20Tk%209] eq $page && [tkwiki::linkedPage /wiki?name=No+such+page] eq ""}
.wiki.top.notes invoke; update
tkwiki::followLink /wiki?name=Migrating+scripts+to+Tk+9; update
check "following it: shown here, in All" {$tkwiki::shown eq $page && $tkwiki::view eq "all"}
set tk [lindex [fossil::sql $T(repo) "SELECT tkt_uuid FROM ticket ORDER BY tkt_mtime DESC LIMIT 1"] 0 0]
tktaalik::show timeline; update
tkwiki::followLink tkt:$tk; update
check "a ticket link: the Tickets tab" {$tktaalik::active eq "tickets" && $tktsearch::shownTicket eq $tk}
set tkwiki::remote https://example.invalid/tk
tkwiki::browsePage
check "Open in browser: [lindex $::browsed end]" {[lindex $::browsed end] eq "https://example.invalid/tk/wiki?name=Migrating%20scripts%20to%20Tk%209"}

# Technotes (in another repository, if given).
if {$T(repo2) ne ""} {
    tktaalik::openPath $T(repo2); update
    .wiki.top.technotes invoke; update
    set notes [$t children {}]
    set listed [llength [lsearch -all -inline -not [split [exec fossil wiki list --technote -R $T(repo2)] \n] ""]]
    check "technotes as fossil wiki list shows them: [llength $notes] of $listed" {[llength $notes] == $listed}
    if {[llength $notes]} {
        set id [lindex $notes 0]
        $t selection set [list $id]; update
        check "technote: [$t set $id title]" {[$t set $id kind] eq "Technote" && ![string match *<* [$t set $id title]] && [string match "Technote for *" [.wiki.main.page.head.meta cget -text]]}
        tkwiki::browsePage
        check "technote in the browser: [lindex $::browsed end]" {[string match */technote/[string range $id 6 end] [lindex $::browsed end]]}
    } else {
        puts "skip technotes (none in TKTAALIK_REPO2)"
    }
} else {
    puts "skip technotes (no TKTAALIK_REPO2)"
}
done
