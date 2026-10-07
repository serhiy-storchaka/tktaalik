# The manual (docs/*.md) and F1: the pages, their links, and the page and
# section F1 opens for what has the focus.
source [file join [file dirname [info script]] common.tcl]
start tickets "" 1100x800
set pages [help::pages]
set required {
    index {getting-started the-window opening-a-repository back-and-forward what-tktaalik-changes contents}
    timeline {views search-syntax details editing-check-ins tags-on-check-ins bisect pull}
    tickets {search-syntax the-list details comments editing-tickets attachments history reports}
    branches {views search-syntax merge-state details update-and-merge managing-branches changes-between-releases}
    tags {the-list history adding-and-cancelling-tags}
    files {versions content blame file-history}
    commit {changed-files committing commit-options diffs file-operations delete-unmanaged-files undo-and-redo merges patches}
    stash {search-syntax applying-stashes go-to-and-go-back stashing-changes}
    wiki {pages-and-technotes versions-and-changes editing attachments}
    forum {threads posts}
    search {search-syntax results}
    repository {information settings users remotes unversioned-files}
    goto {what-it-accepts several-matches}
    diffs {the-diff-window diff-options}
    keys {global-keys keys-in-the-tabs mouse}
    configuration {settings-files columns-and-sorting running-tktaalik}
}
set missing {}
dict for {page anchors} $required {
    if {![dict exists $pages $page]} { lappend missing $page.md; continue }
    set have [lmap h [lindex [dict get $pages $page] 1] {help::slug $h}]
    foreach a $anchors { if {$a ni $have} { lappend missing $page#$a } }
}
check "every page and required section: missing [list $missing]" {![llength $missing]}
# Every link between pages: to a page and a section that exist.
set bad {}
dict for {page info} $pages {
    set f [open [file join $help::dir $page.md]]; fconfigure $f -encoding utf-8; set text [read $f]; close $f
    foreach {- target} [regexp -all -inline {\]\(([^)\s]+)\)} $text] {
        if {[regexp {^https?://} $target]} continue
        if {![regexp {^(?:([a-z0-9_-]+)\.md)?(?:#(.*))?$} $target -> to anchor]} { lappend bad "$page: $target"; continue }
        if {$to eq ""} { set to $page }
        if {![dict exists $pages $to]} { lappend bad "$page: $target"; continue }
        if {$anchor ne "" && $anchor ni [lmap h [lindex [dict get $pages $to] 1] {help::slug $h}]} {
            # (A ### section: looked for in the rendered page below.)
            lappend deep [list $page $to $anchor]
        }
    }
}
check "links to pages: bad [list $bad]" {![llength $bad]}
# Every target of F1 exists (a section: ## or ###).
proc headings {page} {
    set f [open [file join $help::dir $page.md]]; fconfigure $f -encoding utf-8
    set r [lmap line [split [read $f] \n] { if {![regexp {^###? (.+)$} $line -> h]} continue; help::slug $h }]
    close $f
    return $r
}
set bad {}
foreach {prefix target} $help::contexts {
    lassign [split $target #] page anchor
    if {![dict exists $pages $page] || ($anchor ne "" && $anchor ni [headings $page])} {
        lappend bad $target
    }
}
check "F1 targets exist: bad [list $bad]" {![llength $bad]}

# F1 in the tabs and their search boxes.
proc f1 {w} {
    focus -force $w; update
    event generate $w <F1>; update
    list $help::page [help::context $w]
}
lassign [f1 .tickets.top.q] page ctx
check "F1 in the ticket search: $ctx" {$ctx eq "tickets#search-syntax" && $page eq "tickets" && [winfo ismapped .help]}
set d .help.main.text
set top [$d index @0,0]
check "at the section: [$d get $top "$top lineend"]" {[string match "Search syntax*" [$d get $top "$top lineend"]]}
wm withdraw .help
tktaalik::show timeline; update
lassign [f1 .timeline.main.list.t] page ctx
check "F1 in the Timeline list: $ctx" {$ctx eq "timeline" && $page eq "timeline"}
tktaalik::show branches; update
check "the Branches search: [help::context .branches.top.q]" {[help::context .branches.top.q] eq "branches#search-syntax"}
# A window: the Users window.
tkusers::window; update
lassign [f1 .users.main.list.t] page ctx
check "F1 in Users: $ctx" {$ctx eq "repository#users" && $page eq "repository"}
wm withdraw .users
check "a diff window: [help::context .diffview3.p.files.t]" {[help::context .diffview3.p.files.t] eq "diffs"}
# The Help menu.
set hm [.menubar entrycget [.menubar index end] -menu]
check "Help ▸ Manual" {[$hm entrycget 0 -label] eq "Manual"}

# The viewer: contents, links, Back, find.
help::show index; update
set t .help.main.toc.t
check "contents: [llength [$t children {}]] pages" {[llength [$t children {}]] == [dict size $pages] && [lindex [$t children {}] 0] eq "index"}
# A link in the page: the first one to another page.
set link ""
foreach tag [$d tag names] {
    if {[regexp {^ht-href-(\d+)$} $tag -> n] && [llength [$d tag ranges $tag]]
            && [string match *.md* $htmltext::links($d,$n)] && ![string match index.md* $htmltext::links($d,$n)]} {
        set link $tag
        break
    }
}
set i [lindex [$d tag ranges $link] 0]
$d see $i; update
lassign [$d bbox $i] x y
# (Tag bindings follow the mouse: it moves there first.)
event generate $d <Motion> -x [expr {$x + 1}] -y [expr {$y + 1}]; update
event generate $d <1> -x [expr {$x + 1}] -y [expr {$y + 1}]
event generate $d <ButtonRelease-1> -x [expr {$x + 1}] -y [expr {$y + 1}]; update
check "a link: $help::page" {$help::page ne "index"}
help::goBack; update
check "Back: $help::page" {$help::page eq "index"}
help::go commit
set help::find "dry run"
help::findNext; update
check "find: $help::status" {[llength [$d tag ranges found]] > 0}
# Tables: aligned (tab stops), not separated by bars.
set tables [lsearch -all -inline -glob [$d tag names] ht-table*]
check "tables aligned: [llength $tables]" {[llength $tables] > 0 && [string first "│" [$d get 1.0 end]] < 0}
# Sections deeper than ##: the links to them work.
set bad {}
foreach item [expr {[info exists deep] ? $deep : {}}] {
    lassign $item from to anchor
    help::go $to $anchor
    if {$help::status ne ""} { lappend bad "$from -> $to#$anchor" }
}
check "links to ### sections: bad [list $bad]" {![llength $bad]}
done
