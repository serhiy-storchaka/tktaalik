# The Search tab of tktaalik: full-text search across check-in comments,
# tickets, wiki pages, technotes and forum posts at once, with Fossil's own
# search ("fossil search": its matching, scores and snippets), run through
# "fossil sql --readonly": its functions search_init, search_match,
# search_score, search_snippet, title and body.  (The command itself
# prints no ids for tickets and forum posts, searches only the kinds the
# repository's search settings turn on, and -a covers check-ins only;
# these functions work without the settings and change nothing.)  Each
# kind is searched by a query of its own, in the background, side by
# side; the results are ranked together by Fossil's score.  A result opens
# where it belongs (as Go to does).

source [file join [file dirname [file normalize [info script]]] fossil.tcl]
source [file join [file dirname [file normalize [info script]]] config.tcl]

namespace eval tkfulltext {
    variable repo ""
    variable root ""
    variable query ""
    variable searched ""      ;# the query of the results shown
    # kind -> {check box, label of a result, in the counts}
    variable kinds {
        c {Check-ins Check-in check-ins}
        t {Tickets Ticket tickets}
        w {Wiki Wiki {wiki pages}}
        e {Technotes Technote technotes}
        f {Forum {Forum post} {forum posts}}
        d {Docs Document documents}
        h {{Fossil help} {Fossil help} {help topics}}
    }
    variable docGlob ""       ;# the files of the docs when doc-glob is not set
    variable docVersion ""    ;# the check-in of the docs searched
    variable use              ;# array: kind -> searched (1/0)
    variable limit 200        ;# results of each kind
    variable running {}       ;# kind -> channel
    variable generation 0
    variable results {}       ;# {kind id title date score snippet} each
    variable status ""
    variable warned 0         ;# the warning of a Fossil without search shown
    variable history {}       ;# earlier queries, newest first
    variable config {}
    variable configFile [config::path search]
}

proc tkfulltext::loadConfig {} {
    variable configFile
    variable config
    set config [config::get $configFile search]
}

proc tkfulltext::saveConfig {} {
    variable configFile
    variable config
    variable kinds
    variable use
    variable history
    dict set config kinds [lmap k [dict keys $kinds] { if {$use($k)} { set k } else continue }]
    dict set config history $history
    variable docGlob
    dict set config docGlob $docGlob
    config::put $configFile $config {}
}

proc tkfulltext::build {} {
    variable config
    variable kinds
    variable use
    variable history
    menu .search.menu
    .search.menu add cascade -label File -underline 0 -menu [menu .search.menu.file]
    tktaalik::fileMenu .search.menu.file
    tktaalik::quitEntry .search.menu.file
    .search.menu add cascade -label Help -underline 0 -menu [menu .search.menu.help]
    .search.menu.help add command -label "Search syntax" -underline 0 \
        -command {help::show search search-syntax}
    loadConfig
    # (The docs only when chosen: most repositories have no doc-glob.)
    set chosen [tktaalik::getdef $config kinds [lsearch -all -inline -not -regexp [dict keys $kinds] {^[dh]$}]]
    set history [tktaalik::getdef $config history {}]
    variable docGlob [tktaalik::getdef $config docGlob ""]

    ttk::frame .search.top -padding {6 6 6 2}
    ttk::combobox .search.top.q -textvariable tkfulltext::query -font TkFixedFont -values $history
    ttk::button .search.top.go -text Search -command {tktaalik::navigate; tkfulltext::search}
    icons::button .search.top.help help "Search syntax (the manual)" {help::show search search-syntax}
    pack .search.top.help .search.top.go -side right -padx {4 0}
    pack .search.top.q -side left -fill x -expand 1
    ttk::frame .search.kinds -padding {6 0 6 4}
    ttk::label .search.kinds.l -text "In:"
    pack .search.kinds.l -side left
    dict for {k spec} $kinds {
        set use($k) [expr {$k in $chosen}]
        ttk::checkbutton .search.kinds.$k -text [lindex $spec 0] -variable tkfulltext::use($k) \
            -command {tktaalik::navigate; tkfulltext::search}
        pack .search.kinds.$k -side left -padx {6 0}
    }
    # The documents: the repository's doc-glob, or these.
    ttk::entry .search.kinds.docglob -textvariable tkfulltext::docGlob -width 22
    pack .search.kinds.docglob -side left -padx {2 0}
    icons::tooltip .search.kinds.docglob "The files of the docs (doc-glob), like *.md, doc/*;\
        \nthe repository's own doc-glob when it has one"
    bind .search.kinds.docglob <Return> {tktaalik::navigate; tkfulltext::search}
    # More of each kind than the 200 shown.
    ttk::button .search.kinds.more -text More -command tkfulltext::more -state disabled
    ttk::button .search.kinds.index -text "Search index\u2026" -command tkfulltext::indexWindow
    pack .search.kinds.index .search.kinds.more -side right -padx {4 0}
    icons::tooltip .search.kinds.index "Fossil's search index (fossil fts-config): for its web pages\
        and fossil search; this tab does not need it"
    icons::tooltip .search.kinds.more "Twice as many of each kind"

    ttk::frame .search.main
    set d .search.main.text
    text $d -wrap word -padx 10 -pady 6 -font TkTextFont -state disabled -cursor arrow \
        -yscrollcommand {.search.main.y set}
    ttk::scrollbar .search.main.y -command [list $d yview]
    grid $d .search.main.y -sticky news
    grid columnconfigure .search.main 0 -weight 1
    grid rowconfigure .search.main 0 -weight 1
    $d tag configure kind -font TkDefaultFont -foreground gray40
    $d tag configure title -font TkHeadingFont -foreground blue4 -spacing1 8
    $d tag configure date -font TkDefaultFont -foreground gray40
    $d tag configure snippet -lmargin1 16 -lmargin2 16 -spacing3 2
    # (A mark at the start of a line: not its margin too.)
    $d tag configure mark -background #fff3a0 -lmargincolor [$d cget -background]
    $d tag configure current -background gray92
    $d tag bind title <Enter> [list $d configure -cursor hand2]
    $d tag bind title <Leave> [list $d configure -cursor arrow]

    ttk::label .search.status -textvariable tkfulltext::status -padding {6 2} -anchor w
    pack .search.top -fill x
    pack .search.kinds -fill x
    pack .search.status -side bottom -fill x
    pack .search.main -fill both -expand 1

    bind .search.top.q <Return> {tktaalik::navigate; tkfulltext::search}
    bind .search.top.q <<ComboboxSelected>> {tktaalik::navigate; tkfulltext::search}
    bind .search.top.q <Down> {
        if {[llength $tkfulltext::results]} { focus .search.main.text; tkfulltext::move 1; break }
    }
    bind $d <Down> {tkfulltext::move 1; break}
    bind $d <Up> {tkfulltext::move -1; break}
    bind $d <Return> {tkfulltext::openResult $tkfulltext::current; break}
    tktaalik::shortcut search <F5> tkfulltext::search
    tktaalik::shortcut search <Control-f> {focus .search.top.q; .search.top.q selection range 0 end}
}

proc tkfulltext::setRepository {path newRoot} {
    variable repo $path
    variable root $newRoot
    variable query
    # The repository's doc-glob (the web setting), if it has one.
    variable docGlob
    set glob [lindex [fossil::sql $repo "SELECT coalesce((SELECT value FROM config\
        WHERE name='doc-glob'),'')"] 0 0]
    if {$glob ne ""} { set docGlob $glob }
    tktaalik::setTitle search "Search \u2014 [file rootname [file tail $repo]]"
    clear
    if {[string trim $query] ne ""} search
}

proc tkfulltext::activate {} {
    if {[tktaalik::changed search]} { search }
    focus .search.top.q
}

# Search from another tab (the global shortcut).
proc tkfulltext::focusSearch {} {
    if {![tktaalik::show search]} return
    focus .search.top.q
    .search.top.q selection range 0 end
}

# The query of one kind: rows {kind id title date score snippet}.
# (Materialized, so that the score and snippet are those of each row's
# match, before the rows are sorted.)
proc tkfulltext::kindQuery {k} {
    variable limit
    set hits {}
    switch -- $k {
        c {
            set hits "SELECT b.uuid AS id, [fossil::outcol "coalesce(e.comment,'')"] AS title,\
                e.mtime AS mtime, search_score() AS score, search_snippet() AS snip\
                FROM event e JOIN blob b ON b.rid=e.objid\
                WHERE e.type='ci' AND search_match('', body('c',e.objid,NULL))"
        }
        t {
            set hits "SELECT tkt_uuid AS id, title('t',tkt_id,NULL) AS title, tkt_mtime AS mtime,\
                search_score() AS score, search_snippet() AS snip FROM ticket\
                WHERE search_match(title('t',tkt_id,NULL), body('t',tkt_id,NULL))"
        }
        w - e {
            # The newest version of each page (technote).
            set glob [expr {$k eq "w" ? "wiki-*" : "event-*"}]
            set hits "SELECT t.tagname AS id,\
                [expr {$k eq "w" ? "substr(t.tagname,6)" : "coalesce((SELECT comment FROM event WHERE objid=x.rid),substr(t.tagname,7))"}] AS title,\
                x.mtime AS mtime, search_score() AS score, search_snippet() AS snip\
                FROM tag t JOIN tagxref x ON x.tagid=t.tagid\
                WHERE t.tagname GLOB '$glob'\
                AND x.rid=(SELECT y.rid FROM tagxref y WHERE y.tagid=t.tagid ORDER BY y.mtime DESC LIMIT 1)\
                AND search_match(title('$k',x.rid,NULL), body('$k',x.rid,NULL))"
        }
        d {
            # The files of the docs at the check-in of doc-branch.
            variable docVersion
            variable docGlob
            set globs [lmap g [split $docGlob ", "] { if {$g eq ""} continue; set g }]
            set cond [join [lmap g $globs { string cat "f.filename GLOB " [fossil::sqlstr $g] }] " OR "]
            set hits "SELECT f.filename AS id, f.filename AS title,\
                (SELECT mtime FROM event WHERE objid=(SELECT rid FROM blob WHERE uuid=[fossil::sqlstr $docVersion])) AS mtime,\
                search_score() AS score, search_snippet() AS snip\
                FROM files_of_checkin([fossil::sqlstr $docVersion]) f JOIN blob b ON b.uuid=f.uuid\
                WHERE ($cond) AND search_match(title('d',b.rid,f.filename), body('d',b.rid,f.filename))"
        }
        h {
            # Fossil's own help: commands, settings, web pages.
            set hits "SELECT name AS id, name || ' (' || type || ')' AS title, NULL AS mtime,\
                search_score() AS score, search_snippet() AS snip FROM helptext\
                WHERE search_match(name, helptext)"
        }
        f {
            # The posts not replaced by an edit.
            set hits "SELECT b.uuid AS id, coalesce((SELECT comment FROM event WHERE objid=f.fpid),'') AS title,\
                f.fmtime AS mtime, search_score() AS score, search_snippet() AS snip\
                FROM forumpost f JOIN blob b ON b.rid=f.fpid\
                WHERE f.fpid NOT IN (SELECT fprev FROM forumpost WHERE fprev IS NOT NULL)\
                AND search_match(title('f',f.fpid,NULL), body('f',f.fpid,NULL))"
        }
    }
    return "WITH hits AS MATERIALIZED ($hits)\
        SELECT '$k', [fossil::outcol id], [fossil::outcol "replace(replace(coalesce(title,''),char(10),' '),char(13),'')"],\
        strftime('%Y-%m-%d %H:%M', mtime), score,\
        [fossil::outcol "replace(replace(coalesce(snip,''),char(10),' '),char(13),'')"]\
        FROM hits ORDER BY score DESC, mtime DESC LIMIT $limit"
}

# Search: each kind chosen in the background; the results shown as they
# come.
proc tkfulltext::search {} {
    variable repo
    variable query
    variable searched
    variable kinds
    variable use
    variable running
    variable generation
    variable results
    variable status
    variable history
    stop
    clear
    set q [string trim $query]
    # (Another search: 200 of each kind again; More: the same, more.)
    variable limit
    if {$q ne $searched} { set limit 200 }
    set searched $q
    if {$q eq "" || $repo eq ""} {
        set status ""
        return
    }
    set history [lrange [linsert [lsearch -all -inline -not -exact $history $q] 0 $q] 0 29]
    .search.top.q configure -values $history
    if {![fossil::hasSearch $repo]} {
        noSearch
        return
    }
    incr generation
    # Fossil's marks around the matches: control characters, not in text.
    set init "SELECT search_init([fossil::sqlstr $q], char(2), char(3), ' \u2026 ', 0)"
    foreach k [dict keys $kinds] {
        if {!$use($k)} continue
        # (A forum or a ticket table may be missing: an empty kind.)
        if {![hasTable $k]} continue
        if {$k eq "d" && ![docsReady]} continue
        dict set running $k [fossil::sqlStart $repo "$init; [kindQuery $k]"]
        fileevent [dict get $running $k] readable [list tkfulltext::finish $generation $k]
    }
    if {![dict size $running]} {
        set status [expr {[info exists ::tkfulltext::failed] ? [summary] : "Nothing to search in: choose what to search"}]
        return
    }
    set status "Searching\u2026"
}

# This Fossil cannot search (fossil::hasSearch): said in the status line,
# and once in a warning.
proc tkfulltext::noSearch {} {
    variable status
    variable warned
    set v [lindex [tktaalik::fossilVersion] 0]
    set status "Fossil $v cannot search here: its \"fossil sql\" has no search functions"
    if {$warned} return
    set warned 1
    ui::infoBox -icon warning -title Search "Fossil $v cannot search here." \
        "With a repository, its \"fossil sql\" has no search functions (search_init,\
        title, body...), and the Search tab runs Fossil's search through them.  This is a\
        bug of Fossil 2.28 and newer, reported to the Fossil developers.  Fossil 2.27 or\
        older can search, as will a Fossil with the bug fixed."
}

# The docs: which files (doc-glob) at which check-in (doc-branch, else
# trunk or main); "" with a message if they cannot be searched.
proc tkfulltext::docsReady {} {
    variable repo
    variable docGlob
    variable docVersion ""
    if {[string trim $docGlob] eq ""} {
        lappend ::tkfulltext::failed "docs: this repository has no doc-glob; type which files (like *.md, doc/*)"
        return 0
    }
    set branch [lindex [fossil::sql $repo "SELECT coalesce((SELECT value FROM config\
        WHERE name='doc-branch'),'')"] 0 0]
    foreach b [list $branch trunk main] {
        if {$b eq ""} continue
        set uuid [lindex [fossil::sql $repo "SELECT b.uuid FROM tagxref x JOIN blob b ON b.rid=x.rid\
            WHERE x.tagtype>0 AND x.tagid=(SELECT tagid FROM tag WHERE tagname=[fossil::sqlstr sym-$b])\
            ORDER BY x.mtime DESC LIMIT 1"] 0 0]
        if {$uuid ne ""} { set docVersion $uuid; return 1 }
    }
    lappend ::tkfulltext::failed "docs: no doc-branch, trunk or main here"
    return 0
}

proc tkfulltext::more {} {
    variable limit
    set limit [expr {$limit * 2}]
    tktaalik::navigate
    search
}

proc tkfulltext::hasTable {k} {
    variable repo
    # (Fossil's help: a table of fossil itself, not of the repository.)
    if {$k eq "h"} { return 1 }
    set table [dict get {c event t ticket w tag e tag f forumpost d blob} $k]
    llength [fossil::sql $repo "SELECT 1 FROM sqlite_schema WHERE type='table' AND name='$table'"]
}

proc tkfulltext::stop {} {
    variable running
    dict for {k chan} $running { catch {close $chan} }
    set running {}
}

# A kind's query has finished: its results among the others.
proc tkfulltext::finish {gen k} {
    variable generation
    variable running
    variable results
    variable status
    if {$gen != $generation || ![dict exists $running $k]} return
    set chan [dict get $running $k]
    if {![eof $chan]} {
        # (The output in one piece: read it all at the end.)
        fconfigure $chan -blocking 1
    }
    dict unset running $k
    try {
        set rows [fossil::sqlFinish $chan]
    } trap {FOSSIL DB} msg {
        set rows {}
        lappend ::tkfulltext::failed "[kindName $k]: $msg"
    }
    # The first row is search_init's (NULL).
    foreach row $rows {
        if {[llength $row] == 6} { lappend results $row }
    }
    set results [lsort -decreasing -real -index 4 [lsort -decreasing -index 3 $results]]
    show
    if {![dict size $running]} { set status [summary] }
}

proc tkfulltext::kindName {k} {
    variable kinds
    lindex [dict get $kinds $k] 2
}

proc tkfulltext::summary {} {
    variable results
    variable searched
    variable kinds
    variable limit
    set counts {}
    foreach row $results { dict incr counts [lindex $row 0] }
    .search.kinds.more state disabled
    if {![dict size $counts]} {
        set text "Nothing found for \"$searched\""
    } else {
        set parts {}
        foreach k [dict keys $kinds] {
            if {![dict exists $counts $k]} continue
            set n [dict get $counts $k]
            lappend parts "$n[expr {$n >= $limit ? "+" : ""}] [kindName $k]"
        }
        # More: when a kind has as many as the limit.
        .search.kinds.more state [expr {[llength [lsearch -all -glob $parts {*+ *}]] ? "!disabled" : "disabled"}]
        set text "[join $parts {, }]; best first.  Click a title (or Return) to open it"
    }
    if {[info exists ::tkfulltext::failed]} {
        append text ".  Failed: [join $::tkfulltext::failed {; }]"
        unset ::tkfulltext::failed
    }
    return $text
}

proc tkfulltext::clear {} {
    variable results {}
    variable current -1
    set d .search.main.text
    $d configure -state normal
    $d delete 1.0 end
    $d configure -state disabled
}

# The results as a page: the kind, the title (a link), the date, the
# snippet with the matches marked.
proc tkfulltext::show {} {
    variable results
    variable current
    set d .search.main.text
    set top [$d yview]
    $d configure -state normal
    $d delete 1.0 end
    foreach tag [$d tag names] { if {[string match r* $tag]} { $d tag delete $tag } }
    set i 0
    foreach row $results {
        lassign $row k id title date score snippet
        set tag r$i
        # (A check-in's comment can be long: its start.)
        if {[string length $title] > 120} {
            set title [string range $title 0 [string wordstart $title 117]-1]\u2026
        }
        set snippet [string trim $snippet]
        $d insert end [lindex [dict get $::tkfulltext::kinds $k] 1] [list kind $tag] "  " $tag \
            $title [list title $tag] "  $date\n" [list date $tag]
        # The snippet: the marks between char(2) and char(3).
        foreach {- before marked} [regexp -all -inline {([^\x02]*)(?:\x02([^\x03]*)\x03)?} $snippet] {
            if {$before ne ""} { $d insert end $before [list snippet $tag] }
            if {$marked ne ""} { $d insert end $marked [list snippet mark $tag] }
        }
        $d insert end "\n" [list snippet $tag]
        $d tag bind $tag <1> [list tkfulltext::openResult $i]
        incr i
    }
    if {$current >= 0 && $current < [llength $results]} { $d tag add current r$current.first r$current.last }
    $d tag raise sel
    $d configure -state disabled
    $d yview moveto [lindex $top 0]
}

# Up and Down through the results; Return opens.
proc tkfulltext::move {step} {
    variable results
    variable current
    if {![llength $results]} return
    set current [expr {max(0, min([llength $results] - 1, $current + $step))}]
    set d .search.main.text
    $d tag remove current 1.0 end
    $d tag add current r$current.first r$current.last
    $d see r$current.last
    $d see r$current.first
}

# Open a result where it belongs.
proc tkfulltext::openResult {i} {
    variable results
    variable current
    if {$i < 0 || $i >= [llength $results]} return
    set current $i
    lassign [lindex $results $i] k id
    switch -- $k {
        c { goto::checkin $id }
        t { goto::ticket $id }
        w - e { goto::wiki $id "" }
        f { tktaalik::navigate; goto::forum $id }
        d { variable docVersion; goto::file $docVersion $id }
        h { helpTopic $id }
    }
}

# A topic of Fossil's help (a command, a setting, a web page), in a window.
proc tkfulltext::helpTopic {name} {
    lassign [fossil::run help [fossil::arg $name]] code out
    set w .search.fossilhelp
    if {![winfo exists $w]} {
        toplevel $w
        wm geometry $w 760x560
        text $w.t -wrap none -font TkFixedFont -padx 8 -pady 6 -yscrollcommand [list $w.y set] \
            -xscrollcommand [list $w.x set]
        ttk::scrollbar $w.y -command [list $w.t yview]
        ttk::scrollbar $w.x -orient horizontal -command [list $w.t xview]
        ttk::button $w.close -text Close -command [list destroy $w]
        grid $w.t $w.y -sticky news
        grid $w.x -sticky ew
        grid $w.close - -sticky e -padx 6 -pady 6
        grid columnconfigure $w 0 -weight 1
        grid rowconfigure $w 0 -weight 1
        bind $w <Escape> [list destroy $w]
    }
    wm title $w "fossil help $name"
    $w.t configure -state normal
    $w.t delete 1.0 end
    $w.t insert end [string trim $out]
    $w.t configure -state disabled
    raise $w
}

# ---------------------------------------------------------- search index

# Fossil's search index (fossil fts-config): its state and the changes,
# each after a confirmation.  It is for Fossil's web search and "fossil
# search"; the Search tab reads the texts itself (Fossil fills the index
# lazily, when it searches, which a read-only reader cannot do).
proc tkfulltext::indexWindow {} {
    variable repo
    set w .search.fts
    if {![winfo exists $w]} {
        toplevel $w
        wm title $w "Search index"
        wm transient $w .
        ttk::frame $w.f -padding 10
        ttk::label $w.f.about -wraplength 520 -justify left -text "Fossil's full-text index\
            serves its web search and \"fossil search\".  This tab does not use it: it\
            searches the texts themselves.  The settings are of this repository (not\
            synced)."
        text $w.f.state -height 13 -width 64 -font TkFixedFont -state disabled
        ttk::frame $w.f.b
        foreach {b label args} {
            reindex "Reindex\u2026"     reindex
            on      "Index on\u2026"    {index on}
            off     "Index off\u2026"   {index off}
        } {
            ttk::button $w.f.b.$b -text $label -command [list tkfulltext::ftsChange $args]
            pack $w.f.b.$b -side left -padx {0 4}
        }
        foreach {b label sub} {enable "Enable" enable disable "Disable" disable} {
            ttk::menubutton $w.f.b.$b -text $label -menu $w.f.b.$b.m
            menu $w.f.b.$b.m -tearoff 0
            foreach type {check-in document ticket wiki technote forum help all} {
                $w.f.b.$b.m add command -label $type\u2026 -command [list tkfulltext::ftsChange [list $sub $type]]
            }
            pack $w.f.b.$b -side left -padx {0 4}
        }
        ttk::menubutton $w.f.b.tok -text Tokenizer -menu $w.f.b.tok.m
        menu $w.f.b.tok.m -tearoff 0
        foreach tok {porter unicode61 trigram off} {
            $w.f.b.tok.m add command -label $tok\u2026 -command [list tkfulltext::ftsChange [list tokenizer $tok]]
        }
        pack $w.f.b.tok -side left
        ttk::button $w.f.close -text Close -command [list destroy $w]
        grid $w.f.about -sticky w -pady {0 6}
        grid $w.f.state -sticky news
        grid $w.f.b -sticky w -pady {6 0}
        grid $w.f.close -sticky e -pady {8 0}
        grid columnconfigure $w.f 0 -weight 1
        grid rowconfigure $w.f 1 -weight 1
        pack $w.f -fill both -expand 1
        bind $w <Escape> [list destroy $w]
    }
    ftsState
    raise $w
}

proc tkfulltext::ftsState {{out ""}} {
    variable repo
    if {$out eq ""} {
        lassign [fossil::run fts-config -R $repo] code out
    }
    set t .search.fts.f.state
    $t configure -state normal
    $t delete 1.0 end
    $t insert end [string trim $out]
    $t configure -state disabled
}

# A change of the index (fts-config ARGS), after a confirmation.
proc tkfulltext::ftsChange {argv} {
    variable repo
    set what [dict get {
        reindex "Rebuild the search index?"
        index "Turn the search index @ARG@?"
        enable "Enable the search of @ARG@?"
        disable "Disable the search of @ARG@?"
        tokenizer "Use the tokenizer @ARG@ (the index is rebuilt)?"
    } [lindex $argv 0]]
    set what [string map [list @ARG@ [lindex $argv 1]] $what]
    if {![ui::confirm -parent .search.fts \
            -title "Search index" $what "fossil fts-config $argv\n\nIt changes\
                this repository's settings and index only; nothing is synced.  On a big\
                repository rebuilding the index takes a while."]} return
    set busy [ui::busyHold]
    try {
        lassign [fossil::run fts-config -R $repo {*}$argv] code out
    } finally {
        ui::busyRelease $busy
    }
    if {$code} {
        tk_messageBox -parent .search.fts -icon error -title "Search index" \
            -message "fossil fts-config failed:" -detail [string trim $out]
        ftsState
        return
    }
    # (It prints the settings after the change.)
    ftsState $out
}

# Back and Forward: the query, the kinds, how far down.
proc tkfulltext::here {} {
    variable searched
    variable use
    list $searched [array get use] [lindex [.search.main.text yview] 0]
}

proc tkfulltext::goTo {place} {
    variable query
    variable use
    lassign $place q kinds top
    set query $q
    array set use $kinds
    search
    variable pendingTop $top
    after 1500 [list apply {{top} { .search.main.text yview moveto $top }} $top]
}
