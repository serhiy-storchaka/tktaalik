# The Wiki tab of tktaalik: the wiki pages, the
# technotes and the notes Fossil keeps as wiki pages (of branches,
# check-ins, tags, tickets), each shown rendered (wiki, Markdown or plain
# text, by Fossil), with its earlier versions.  Links to other pages open
# them here, links to tickets in the Tickets tab, others in the browser.
# A version can be saved to a file (its source or HTML).  Pages and
# technotes can be edited and created ("fossil wiki commit|create"), as the
# default user, after a confirmation; that changes the local repository
# only (it does not sync, even with autosync on).  So can files be attached
# to them ("fossil attachment add"); the attachments of the page shown are
# listed under it, to view or save.

source [file join [file dirname [file normalize [info script]]] fossil.tcl]
source [file join [file dirname [file normalize [info script]]] tablecols.tcl]
source [file join [file dirname [file normalize [info script]]] htmltext.tcl]
source [file join [file dirname [file normalize [info script]]] formattext.tcl]

namespace eval tkwiki {
    variable repo ""
    variable root ""
    variable remote ""        ;# the server, for the browser
    variable pages            ;# array: tag name -> dict of the page
    variable view all         ;# all wiki technotes notes
    variable filter ""
    variable showDeleted 0    ;# pages saved empty (fossil wiki list --all)
    variable shown ""         ;# the tag name of the page shown (also its
                              ;# item: a list of one, it can have spaces)
    variable versions {}      ;# of the page shown: {uuid date user} newest first
    variable version ""       ;# the version chosen in the menu
    variable status ""
    variable hashes {}        ;# [hash] in the page shown -> link
    variable config {}
    variable configFile [config::path wiki]
    variable current {}       ;# the version shown: index uuid cards text mimetype
    # The editor: what it does (edit newpage newnote), its fields.
    variable editMode ""
    variable editName ""
    variable editComment ""
    variable editDate ""
    variable editTags ""
    variable editColor ""
    variable editFormat ""
    variable editDone ""
    variable editCrlf 0       ;# the text had CRLF line ends (from the web)
    variable attached         ;# array: attachment item -> dict src name here
    variable formats {
        "Fossil wiki" text/x-fossil-wiki
        Markdown      text/x-markdown
        "Plain text"  text/plain
    }
}

proc tkwiki::loadConfig {} {
    variable configFile
    variable config
    set config [config::get $configFile wiki]
}

proc tkwiki::saveConfig {} {
    variable configFile
    variable config
    variable view
    variable filter
    variable showDeleted
    if {[winfo exists .wiki.main.list.t]} {
        dict set config table [tablecols::state .wiki.main.list.t]
    }
    dict set config view $view
    dict set config filter $filter
    dict set config showDeleted $showDeleted
    config::put $configFile $config {table}
}

proc tkwiki::build {} {
    variable config
    variable view
    variable filter
    variable showDeleted
    menu .wiki.menu
    .wiki.menu add cascade -label File -underline 0 -menu [menu .wiki.menu.file]
    tktaalik::fileMenu .wiki.menu.file
    .wiki.menu.file add command -label "New page\u2026" -underline 0 -command {tkwiki::editor newpage}
    .wiki.menu.file add command -label "New technote\u2026" -underline 4 -command {tkwiki::editor newnote}
    .wiki.menu.file add command -label Refresh -underline 0 -accelerator F5 -command tkwiki::reload
    tktaalik::quitEntry .wiki.menu.file
    .wiki.menu add cascade -label Page -underline 0 -menu [menu .wiki.menu.page \
        -postcommand {popup::fill .wiki.menu.page tkwiki::popupMenu [lindex [.wiki.main.list.t selection] 0]}]
    loadConfig
    set view [tktaalik::getdef $config view all]
    set filter [tktaalik::getdef $config filter ""]
    set showDeleted [tktaalik::getdef $config showDeleted 0]

    ttk::frame .wiki.top -padding {6 6 6 2}
    ttk::label .wiki.top.fl -text "Find:"
    ttk::entry .wiki.top.filter -textvariable tkwiki::filter -width 30
    pack .wiki.top.fl .wiki.top.filter -side left -padx {0 6}
    foreach {v label} {all All wiki "Wiki pages" technotes Technotes notes Notes} {
        ttk::radiobutton .wiki.top.$v -style Toolbutton -text $label \
            -variable tkwiki::view -value $v -command {tktaalik::navigate; tkwiki::showList}
        pack .wiki.top.$v -side left -padx {0 4}
    }
    ttk::checkbutton .wiki.top.deleted -text "Show deleted" -variable tkwiki::showDeleted \
        -command {tktaalik::navigate; tkwiki::showList}
    pack .wiki.top.deleted -side right
    trace add variable ::tkwiki::filter write {::apply {args {
        tktaalik::typing .wiki.top.filter
        after cancel tkwiki::showList
        after 200 tkwiki::showList
    }}}

    ttk::panedwindow .wiki.main -orient horizontal
    ui::splitByWeights .wiki.main
    ttk::frame .wiki.main.list
    set t .wiki.main.list.t
    ttk::treeview $t -show headings -selectmode browse -yscrollcommand {.wiki.main.list.y set}
    ttk::scrollbar .wiki.main.list.y -command [list $t yview]
    grid $t .wiki.main.list.y -sticky news
    grid columnconfigure .wiki.main.list 0 -weight 1
    grid rowconfigure .wiki.main.list 0 -weight 1
    $t tag configure deleted -foreground gray50
    tablecols::setup $t {
        title    {heading Page width 30 stretch 1}
        kind     {heading Kind width 13}
        date     {heading Date width 16 dir desc}
        user     {heading User width 12}
        count    {heading Versions width 8 type integer dir desc anchor e}
        id       {heading "Technote ID" width 14}
    } -fixed {title} -defaults {kind date user} \
        -shown [tktaalik::getdef [tktaalik::getdef $config table {}] shown {}] \
        -order [tktaalik::getdef [tktaalik::getdef $config table {}] order {}] \
        -sort [tktaalik::getdef [tktaalik::getdef $config table {}] sort {date desc}]

    set p .wiki.main.page
    ttk::frame $p
    ttk::frame $p.head -padding {8 6 8 4}
    ttk::label $p.head.title -font TkHeadingFont
    ttk::label $p.head.meta -foreground gray35
    ttk::frame $p.head.v
    ttk::frame $p.head.a
    ttk::label $p.head.vl -text "Version:"
    ttk::combobox $p.head.version -textvariable tkwiki::version -state readonly -width 30
    ttk::button $p.head.changes -text Changes -style Small.TButton \
        -command {tkwiki::diff changes}
    ttk::button $p.head.since -text "Since" -style Small.TButton \
        -command {tkwiki::diff since}
    icons::tooltip $p.head.changes "What this version changed (a diff with the one before)"
    icons::tooltip $p.head.since "What changed after this version (a diff with the newest)"
    ttk::button $p.head.edit -text "Edit\u2026" -style Small.TButton -command {tkwiki::editor edit}
    ttk::button $p.head.save -text "Save\u2026" -style Small.TButton -command tkwiki::save
    icons::tooltip $p.head.edit "Edit this version: commit it as the newest one"
    ttk::button $p.head.attach -text "Attach\u2026" -style Small.TButton -command tkwiki::attach
    icons::tooltip $p.head.save "Save this version to a file: its source, or HTML"
    icons::tooltip $p.head.attach "Attach files to this page or technote"
    # The versions on their row; what can be done with the page by its
    # date, on the right.
    pack $p.head.vl $p.head.version $p.head.changes $p.head.since -in $p.head.v \
        -side left -padx {0 6}
    pack $p.head.edit $p.head.save $p.head.attach -in $p.head.a -side left -padx {6 0}
    grid $p.head.title - -sticky ew
    grid $p.head.meta $p.head.a -sticky w
    grid $p.head.a -sticky e
    grid $p.head.v - -sticky w -pady {2 0}
    # A long title wraps.
    bind $p.head <Configure> {.wiki.main.page.head.title configure -wraplength [expr {max(0, %w - 16)}]}
    grid columnconfigure $p.head 0 -weight 1
    set d $p.text
    text $d -wrap word -width 70 -height 30 -padx 10 -pady 6 -font TkTextFont \
        -state disabled -yscrollcommand [list $p.y set]
    ttk::scrollbar $p.y -command [list $d yview]
    $d tag configure body -lmargin1 4 -lmargin2 4
    $d tag configure missing -foreground gray45
    grid $p.head - -sticky ew
    grid $d $p.y -sticky news
    # The attachments, under the page (only if it has some).
    buildAttachments $p.att
    grid $p.att - -sticky news
    grid remove $p.att
    grid columnconfigure $p 0 -weight 1
    grid rowconfigure $p 1 -weight 1
    .wiki.main add .wiki.main.list -weight 2
    .wiki.main add $p -weight 3

    ttk::frame .wiki.b -padding 6
    ttk::label .wiki.b.status -textvariable tkwiki::status -anchor w
    ttk::button .wiki.b.newpage -text "New page\u2026" -command {tkwiki::editor newpage}
    ttk::button .wiki.b.newnote -text "New technote\u2026" -command {tkwiki::editor newnote}
    ttk::button .wiki.b.browse -text "Open in browser" -command tkwiki::browsePage
    pack .wiki.b.browse .wiki.b.newnote .wiki.b.newpage -side right -padx {4 0}
    ttk::style configure Small.TButton -padding {8 0} -width 0
    pack .wiki.b.status -side left -fill x -expand 1
    pack .wiki.top -fill x
    pack .wiki.b -side bottom -fill x
    pack .wiki.main -fill both -expand 1

    bind $t <<TreeviewSelect>> {tkwiki::showPage [lindex [.wiki.main.list.t selection] 0]}
    bind $p.head.version <<ComboboxSelected>> tkwiki::showVersion
    tktaalik::shortcut wiki <F5> tkwiki::reload
    tktaalik::shortcut wiki <Control-f> {focus .wiki.top.filter; .wiki.top.filter selection range 0 end}
    popup::attach .wiki.main.list.t tkwiki::popupMenu
}

proc tkwiki::setRepository {path newRoot} {
    variable repo $path
    variable root $newRoot
    variable remote [fossil::remoteUrl $path]
    tktaalik::setTitle wiki "Wiki \u2014 [file rootname [file tail $repo]]"
    reload
}

proc tkwiki::activate {} {
    if {[tktaalik::changed wiki]} { reload }
    focus .wiki.main.list.t
}

# Where we are (tktaalik::location): the view and filter of the list, the
# page, the version shown and how far it is scrolled.
proc tkwiki::here {} {
    variable view
    variable filter
    variable showDeleted
    variable shown
    variable version
    set values [.wiki.main.page.head.version cget -values]
    list $view $filter $showDeleted $shown [lsearch -exact $values $version] \
        [.wiki.main.page.text index @0,0]
}

# Back or Forward to a place of here.
proc tkwiki::goTo {place} {
    variable view
    variable filter
    variable showDeleted
    variable shown
    lassign $place v f deleted page i top
    set view $v
    set filter $f
    set showDeleted $deleted
    set shown $page
    showList
    after cancel tkwiki::showList
    # After the page is shown (on the selection event): its version, scroll.
    after idle [list apply {{i top} {
        set values [.wiki.main.page.head.version cget -values]
        if {$i > 0 && $i < [llength $values]} {
            set tkwiki::version [lindex $values $i]
            tkwiki::showVersion
        }
        if {$top ne ""} { .wiki.main.page.text yview $top }
    }} $i $top]
}

# The kind of a page by its tag: wiki-NAME, wiki-branch/NAME, ...,
# event-ID (a technote).
proc tkwiki::kind {tag} {
    if {[string match event-* $tag]} { return Technote }
    switch -glob -- [string range $tag 5 end] {
        branch/* { return "Branch note" }
        checkin/* { return "Check-in note" }
        tag/*    { return "Tag note" }
        ticket/* { return "Ticket note" }
        default  { return Wiki }
    }
}

# A wiki or technote artifact: its cards (L title, C title of a technote,
# E date and id of a technote, N mimetype, U user, D date) and its text.
proc tkwiki::artifact {uuid} {
    variable repo
    set p [fossil::pipe [list artifact $uuid -R $repo] rb]
    set data [read $p]
    close $p
    set cards {}
    set text ""
    set pos 0
    while {$pos < [string length $data]} {
        set end [string first \n $data $pos]
        if {$end < 0} { set end [string length $data] }
        set line [string range $data $pos [expr {$end - 1}]]
        set pos [expr {$end + 1}]
        set card [string index $line 0]
        set value [string range $line 2 end]
        if {$card eq "T"} {
            # Tags (and the color of a technote): there can be several.
            dict lappend cards T [encoding convertfrom utf-8 $value]
            continue
        }
        if {$card eq "W"} {
            # The text: its length in bytes, then the bytes.
            set n [string trim $value]
            set text [encoding convertfrom utf-8 [string range $data $pos [expr {$pos + $n - 1}]]]
            set pos [expr {$pos + $n + 1}]
            continue
        }
        dict set cards $card [encoding convertfrom utf-8 \
            [string map {\\s " " \\n \n \\r \r \\t \t \\\\ \\} $value]]
    }
    list $cards $text
}

# A technote title as text: it can have HTML in it, and line breaks.
proc tkwiki::plain {html} {
    regsub -all {<[^>]*>} $html "" text
    regsub -all {\s+} [htmltext::decode $text] " " text
    string trim $text
}

# All pages: the latest version of each, how many there are.
proc tkwiki::reload {} {
    variable repo
    variable pages
    variable status
    array unset pages
    try {
        set rows [fossil::sql $repo "WITH v AS (SELECT t.tagname AS tag, x.rid AS rid,\
                x.mtime AS mtime, row_number() OVER (PARTITION BY t.tagid ORDER BY x.mtime DESC) AS n,\
                count(*) OVER (PARTITION BY t.tagid) AS versions\
                FROM tag t JOIN tagxref x ON x.tagid=t.tagid\
                WHERE t.tagname GLOB 'wiki-*' OR t.tagname GLOB 'event-*')\
            SELECT [fossil::outcol v.tag], b.uuid, strftime('%Y-%m-%d %H:%M', v.mtime),\
                [fossil::outcol "coalesce(e.user,'')"], [fossil::outcol "coalesce(e.comment,'')"],\
                v.versions, coalesce(strftime('%Y-%m-%d %H:%M', e.mtime),'')\
            FROM v JOIN blob b ON b.rid=v.rid LEFT JOIN event e ON e.objid=v.rid WHERE v.n=1"]
    } trap {FOSSIL DB} msg {
        set status "Cannot read the pages: $msg"
        set rows {}
    }
    foreach row $rows {
        lassign $row tag uuid date user comment count edate
        set kind [kind $tag]
        set deleted 0
        if {$kind eq "Technote"} {
            # The title and date of a technote are in the artifact.
            lassign [artifact $uuid] cards text
            set title [expr {[dict exists $cards C] ? [plain [dict get $cards C]] : [string range $tag 6 15]}]
            if {[dict exists $cards E]} {
                set date [string map {T " "} [string range [lindex [dict get $cards E] 0] 0 15]]
            }
            if {[dict exists $cards U]} { set user [dict get $cards U] }
            # (Never "deleted": fossil wiki list shows empty technotes too.)
        } else {
            set title [string range $tag 5 end]
            # A wiki change is "+NAME" (new), ":NAME" (edited) or "-NAME" (deleted).
            set deleted [string match -* $comment]
        }
        set pages($tag) [dict create title $title kind $kind date $date user $user \
            count $count uuid $uuid deleted $deleted]
    }
    showList
}

proc tkwiki::showList {} {
    variable pages
    variable view
    variable filter
    variable shown
    variable status
    variable showDeleted
    set f [string tolower [string trim $filter]]
    set items {}
    set n 0
    set hidden 0
    foreach tag [array names pages] {
        set p $pages($tag)
        set kind [dict get $p kind]
        switch -- $view {
            wiki      { if {$kind ne "Wiki"} continue }
            technotes { if {$kind ne "Technote"} continue }
            notes     { if {$kind in {Wiki Technote}} continue }
        }
        if {$f ne "" && [string first $f [string tolower [dict get $p title]]] < 0} continue
        if {[dict get $p deleted] && !$showDeleted} {
            incr hidden
            continue
        }
        incr n
        set title [dict get $p title]
        if {[dict get $p deleted]} { append title " (deleted)" }
        set id [expr {$kind eq "Technote" ? [string range $tag 6 end] : ""}]
        lappend items [list $tag [dict create title $title kind $kind date [dict get $p date] \
            user [dict get $p user] count [dict get $p count] id $id] \
            [dict create title [string tolower [dict get $p title]]] \
            [expr {[dict get $p deleted] ? "deleted" : ""}]]
    }
    set t .wiki.main.list.t
    tablecols::fill $t $items
    set status "$n of [array size pages] pages"
    if {$hidden} { append status ", $hidden deleted not shown" }
    if {$shown ne "" && [$t exists $shown]} {
        $t selection set [list $shown]
        $t see $shown
    } elseif {[llength [$t children {}]]} {
        $t selection set [lrange [$t children {}] 0 0]
    } else {
        showPage ""
    }
}

# Show a page: its newest version, and the list of the others.
proc tkwiki::showPage {tag} {
    variable repo
    variable pages
    variable shown
    variable versions
    variable version
    set shown $tag
    set p .wiki.main.page
    if {$tag eq "" || ![info exists pages($tag)]} {
        variable current {}
        foreach b {changes since edit save attach} { $p.head.$b state disabled }
        fillAttachments ""
        $p.head.title configure -text ""
        $p.head.meta configure -text ""
        $p.head.version configure -values {}
        set version ""
        fill "" "" ""
        return
    }
    set rows [fossil::sql $repo "SELECT b.uuid, strftime('%Y-%m-%d %H:%M', x.mtime),\
        [fossil::outcol "coalesce(e.user,'')"]\
        FROM tag t JOIN tagxref x ON x.tagid=t.tagid JOIN blob b ON b.rid=x.rid\
        LEFT JOIN event e ON e.objid=x.rid\
        WHERE t.tagname=[fossil::sqlstr $tag] ORDER BY x.mtime DESC"]
    set versions $rows
    set n [llength $rows]
    set labels {}
    foreach row $rows {
        lassign $row uuid date user
        lappend labels "$n  $date[expr {$user ne "" ? "  $user" : ""}]"
        incr n -1
    }
    $p.head.version configure -values $labels
    set version [lindex $labels 0]
    $p.head.attach state !disabled
    fillAttachments $tag
    showVersion
}

# Show the version chosen in the menu.
proc tkwiki::showVersion {} {
    variable pages
    variable shown
    variable versions
    variable version
    set p .wiki.main.page
    set i [lsearch -exact [$p.head.version cget -values] $version]
    if {$i < 0} return
    # (The versions are newest first.)
    $p.head.changes state [expr {$i < [llength $versions] - 1 ? "!disabled" : "disabled"}]
    $p.head.since state [expr {$i > 0 ? "!disabled" : "disabled"}]
    lassign [lindex $versions $i] uuid
    lassign [artifact $uuid] cards text
    set page $pages($shown)
    $p.head.title configure -text [dict get $page title]
    set meta [dict get $page kind]
    if {[dict exists $cards E]} {
        append meta " for [string map {T " "} [string range [lindex [dict get $cards E] 0] 0 15]]"
    }
    if {[dict exists $cards U]} { append meta "  \u2014  [dict get $cards U]" }
    if {[dict exists $cards D]} { append meta ", [string map {T " "} [string range [dict get $cards D] 0 15]]" }
    $p.head.meta configure -text $meta
    set mimetype [expr {[dict exists $cards N] ? [dict get $cards N] : "text/x-fossil-wiki"}]
    variable current [dict create index $i uuid $uuid cards $cards text $text mimetype $mimetype]
    $p.head.edit state !disabled
    $p.head.save state !disabled
    fill $shown $mimetype $text
}

# A diff of the source of two versions of the page shown (fossil xdiff), in
# a diff window: "changes" made by the version chosen (from the one before),
# or the changes "since" it (to the newest).
proc tkwiki::diff {how} {
    variable pages
    variable shown
    variable versions
    variable version
    set i [lsearch -exact [.wiki.main.page.head.version cget -values] $version]
    if {$i < 0 || $shown eq ""} return
    set n [llength $versions]
    if {$how eq "changes"} {
        set old [expr {$i + 1}]
        set new $i
    } else {
        set old $i
        set new 0
    }
    if {$old >= $n || $old == $new} return
    set title [dict get $pages($shown) title]
    set files {}
    try {
        foreach which [list $old $new] {
            lassign [lindex $versions $which] uuid date user
            lassign [artifact $uuid] cards text
            # (Without the CRs of web edits: they are not shown.)
            set text [string map {"\r\n" "\n"} $text]
            set f [file tempfile name]
            lappend files $name
            fconfigure $f -encoding utf-8
            puts -nonewline $f $text
            close $f
            # The label of the version, as in the menu.
            lappend labels "version [expr {$n - $which}], $date[expr {$user ne "" ? ", $user" : ""}]"
        }
        set p [fossil::pipe [list xdiff {*}$files 2>@1]]
        fconfigure $p -encoding utf-8
        set out [read $p]
        close $p
    } on error msg {
        tk_messageBox -parent .wiki -icon error -title Wiki -message "Cannot compare the versions:" \
            -detail $msg
        return
    } finally {
        foreach name $files { file delete $name }
    }
    if {[string trim $out] eq ""} {
        tk_messageBox -parent .wiki -icon info -title Wiki -message "The versions have the same text."
        return
    }
    # The page and the versions in the header, not the temporary files.
    set lines [split $out \n]
    set i [lsearch -glob $lines "--- *"]
    if {$i >= 0 && [string match "+++ *" [lindex $lines $i+1]]} {
        lset lines $i "--- $title\t[lindex $labels 0]"
        lset lines $i+1 "+++ $title\t[lindex $labels 1]"
    }
    diffview::show "$title: [lindex $labels 0] \u2192 [lindex $labels 1]" [join $lines \n]
}

# The text of a page, rendered.
proc tkwiki::fill {tag mimetype text} {
    variable repo
    variable hashes
    set d .wiki.main.page.text
    $d configure -state normal
    $d delete 1.0 end
    htmltext::reset $d
    if {$tag ne "" && [string trim $text] eq ""} {
        $d insert end [expr {[string match event-* $tag] ? "(empty)"
            : "(empty: the page was deleted)"}] missing
    } elseif {$tag ne ""} {
        set hashes [fossil::hashLinks $repo [list $text]]
        set html [fossil::render $repo $mimetype $text]
        if {$html eq ""} {
            set html "<pre>[string map {& &amp; < &lt; > &gt;} $text]</pre>"
        }
        htmltext::insert $d $html -tags body -margin 4 -command tkwiki::followLink \
            -external tkwiki::isExternal \
            -autolink [list {\[([0-9a-fA-F]{4,40})\]} tkwiki::hashLink]
        $d tag raise sel
    }
    $d configure -state disabled
    $d yview moveto 0
}

proc tkwiki::hashLink {match hash} {
    variable hashes
    set hash [string tolower $hash]
    expr {[dict exists $hashes $hash] ? [dict get $hashes $hash] : ""}
}

# The page a link names, if it is one of the wiki: "/wiki?name=NAME",
# "wiki?name=NAME" or a plain name (Markdown links); "" if not.
proc tkwiki::linkedPage {href} {
    variable pages
    if {[regexp {^/?wiki\?name=([^&#]+)} $href -> name]} {
        set name [fossil::urlDecode $name]
    } elseif {![regexp {[:/?#]} $href]} {
        set name [fossil::urlDecode $href]
    } else {
        return ""
    }
    expr {[info exists pages(wiki-$name)] ? "wiki-$name" : ""}
}

# A link that followLink opens in the browser: not a page or a ticket; a
# URL, or a page of the server if the repository has one.
proc tkwiki::isExternal {href} {
    variable remote
    if {[linkedPage $href] ne "" || [string match tkt:* $href] || [string match #* $href]} { return 0 }
    if {[goto::linkTarget $href] ne ""} { return 0 }
    if {[regexp {^[a-zA-Z][a-zA-Z0-9+.-]*://|^mailto:} $href]} { return 1 }
    expr {$remote ne ""}
}

proc tkwiki::followLink {href} {
    variable remote
    variable view
    variable filter
    set page [linkedPage $href]
    if {$page ne ""} {
        # Another page: here.  Back returns to this one.
        tktaalik::navigate
        set t .wiki.main.list.t
        if {![$t exists $page]} {
            set view all
            set filter ""
            showList
            after cancel tkwiki::showList
        }
        $t selection set [list $page]
        $t see $page
        return
    }
    # A check-in and the like: in its tab.
    if {![string match tkt:* $href] && [goto::openLink $href]} return
    switch -glob -- $href {
        tkt:* {
            # A ticket: in the Tickets tab of the main window.
            tktaalik::show tickets
            tktsearch::showTicket [string range $href 4 end]
        }
        info:*           { if {$remote ne ""} { fossil::browse $remote/info/[string range $href 5 end] } }
        *://* - mailto:* { fossil::browse $href }
        "#*"             {}
        /*               { if {$remote ne ""} { fossil::browse $remote$href } }
        default          { if {$remote ne ""} { fossil::browse $remote/$href } }
    }
}

# The page shown, on the server.
proc tkwiki::browsePage {} {
    variable remote
    variable shown
    if {$remote eq "" || $shown eq ""} return
    if {[string match event-* $shown]} {
        fossil::browse $remote/technote/[string range $shown 6 end]
    } else {
        set name [string range $shown 5 end]
        set q ""
        foreach c [split [encoding convertto utf-8 $name] ""] {
            append q [expr {[regexp {[A-Za-z0-9._~/-]} $c] ? $c : [format %%%02X [scan $c %c]]}]
        }
        fossil::browse $remote/wiki?name=$q
    }
}

# ------------------------------------------------------------- save, edit

# Save the version shown: its source, or (.html) the page rendered.
proc tkwiki::save {} {
    variable repo
    variable pages
    variable shown
    variable current
    if {$current eq ""} return
    set mimetype [dict get $current mimetype]
    set title [dict get $pages($shown) title]
    set ext [dict get {text/x-fossil-wiki .wiki text/x-markdown .md text/plain .txt} $mimetype]
    regsub -all {[^A-Za-z0-9._-]+} $title _ base
    set file [tk_getSaveFile -parent .wiki -title "Save the page" -initialfile $base$ext \
        -defaultextension $ext -filetypes [list [list Source $ext] {HTML .html} {{All files} *}]]
    if {$file eq ""} return
    set text [dict get $current text]
    if {[string tolower [file extension $file]] in {.html .htm}} {
        set html [fossil::render $repo $mimetype $text]
        if {$html eq ""} { set html "<pre>[string map {& &amp; < &lt; > &gt;} $text]</pre>" }
        set text "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\">\
            <title>[string map {& &amp; < &lt; > &gt;} $title]</title></head><body>\n$html\n</body></html>\n"
    }
    try {
        set f [open $file w]
        fconfigure $f -encoding utf-8 -translation lf
        puts -nonewline $f $text
        close $f
    } on error msg {
        tk_messageBox -parent .wiki -icon error -title Wiki -message "Cannot save the page:" -detail $msg
    }
}

# ------------------------------------------------------------ attachments

# What an attachment of a page names: the page name, or a technote's ID.
proc tkwiki::target {tag} {
    expr {[string match event-* $tag] ? [string range $tag 6 end] : [string range $tag 5 end]}
}

proc tkwiki::buildAttachments {f} {
    ttk::frame $f
    set tv $f.tv
    # (The icon of the kind of file in the tree column.)
    ttk::treeview $tv -columns {file size user date comment} -show {tree headings} \
        -style [imageview::listStyle] -selectmode browse -height 4 -yscrollcommand [list $f.y set]
    ttk::scrollbar $f.y -command [list $tv yview]
    $tv column #0 -width [expr {[icons::rowSize] + 8}] -stretch 0 -anchor center
    set char [font measure TkDefaultFont 0]
    foreach {col heading chars anchor} {
        file Attachment 24 w  size Size 9 e  user User 12 w  date Date 16 w  comment Comment 20 w
    } {
        $tv heading $col -text $heading -anchor $anchor
        $tv column $col -width [expr {$chars * $char}] -anchor $anchor \
            -stretch [expr {$col in {file comment}}]
    }
    $tv tag configure missing -foreground gray50
    grid $tv $f.y -sticky news -pady {4 0}
    grid columnconfigure $f 0 -weight 1
    bind $tv <Double-1> {
        if {[%W identify region %x %y] in {cell tree}} {
            tkwiki::openAttachment [%W identify item %x %y]
        }
    }
    bind $tv <Return> {tkwiki::openAttachment [lindex [%W selection] 0]}
    if {[tk windowingsystem] eq "aqua"} {
        bind $tv <2> {tkwiki::attachmentMenu %W %x %y %X %Y}
        bind $tv <Control-1> {tkwiki::attachmentMenu %W %x %y %X %Y}
    } else {
        bind $tv <3> {tkwiki::attachmentMenu %W %x %y %X %Y}
    }
    icons::tooltip $tv "Double-click to view; right-click to save"
}

# The attachments of a page (TAG; "" for none): the latest of each, not
# deleted ones.
proc tkwiki::fillAttachments {tag} {
    variable repo
    variable attached
    array unset attached
    set f .wiki.main.page.att
    set tv $f.tv
    $tv delete [$tv children {}]
    set rows {}
    if {$tag ne ""} {
        set rows [fossil::sql $repo "SELECT a.src, [fossil::outcol a.filename],\
            [fossil::outcol "coalesce(a.user,'')"], strftime('%Y-%m-%d %H:%M', a.mtime),\
            [fossil::outcol "coalesce(a.comment,'')"], coalesce(b.size,-1),\
            [imageview::binarySql a.src]\
            FROM attachment a LEFT JOIN blob b ON b.uuid=a.src\
            WHERE a.target=[fossil::sqlstr [target $tag]] AND a.isLatest AND a.src<>''\
            ORDER BY a.mtime"]
    }
    set i 0
    foreach row $rows {
        lassign $row src name user date comment size binary
        # The content can be missing: the attachment arrived, the file not.
        set here [expr {$size >= 0}]
        set kind [imageview::fileKind $name $binary]
        set attached($i) [dict create src $src name $name here $here kind $kind]
        $tv insert {} end -id $i -tags [expr {$here ? "" : "missing"}] -image [icons::get a-$kind row] \
            -values [list $name [expr {$here ? [tktsearch::sizeText $size] : "not local"}] \
                $user $date [fossil::oneLine $comment]]
        incr i
    }
    if {$i} { grid $f } else { grid remove $f }
}

proc tkwiki::openAttachment {i} {
    variable attached
    if {$i eq "" || ![info exists attached($i)]} return
    set a $attached($i)
    # (One that cannot be viewed here: on the server, as one not here.)
    if {[dict get $a here] && [imageview::canView [dict get $a kind]]} {
        viewAttachment [dict get $a src] [dict get $a name]
    } else {
        browseAttachment [dict get $a name]
    }
}

proc tkwiki::attachmentMenu {tv x y X Y} {
    variable attached
    variable remote
    set i [$tv identify item $x $y]
    if {$i eq "" || ![info exists attached($i)]} return
    $tv selection set $i
    set a $attached($i)
    lassign [list [dict get $a src] [dict get $a name]] src name
    set here [expr {[dict get $a here] ? "normal" : "disabled"}]
    set m .wiki.attctx
    if {![winfo exists $m]} { menu $m }
    $m delete 0 end
    set canView [expr {$here eq "normal" && [imageview::canView [dict get $a kind]] ? "normal" : "disabled"}]
    $m add command -label View -state $canView -command [list tkwiki::viewAttachment $src $name]
    $m add command -label Save\u2026 -state $here -command [list tkwiki::saveAttachment $src $name]
    $m add separator
    $m add command -label "Open in browser" -state [expr {$remote ne "" ? "normal" : "disabled"}] \
        -command [list tkwiki::browseAttachment $name]
    $m add command -label "Copy file name" -command [list ui::copy $name]
    $m add separator
    $m add command -label "Delete\u2026" -command [list tkwiki::deleteAttachment $name]
    popup::default $m [expr {$canView eq "normal" ? "View" : "Open in browser"}]
    tk_popup $m $X $Y
}

# Delete the attachment NAME of the page or technote shown, after a
# confirmation: a record without content, as the web page's Delete writes
# (no command does it).  The file stays in the history.
proc tkwiki::deleteAttachment {name} {
    variable repo
    variable pages
    variable shown
    if {$shown eq "" || ![info exists pages($shown)]} return
    set user [user]
    if {$user eq ""} {
        ui::infoBox -parent .wiki -title "Delete attachment" "Deleting needs a user." \
            "This repository has no default user to record it as (fossil user default)."
        return
    }
    set what [expr {[string match event-* $shown] ? "the technote" : "the page"}]
    if {![ui::confirm -parent .wiki -title "Delete attachment" \
            "Delete the attachment $name of $what [dict get $pages($shown) title]?" \
            "Recorded in [file tail $repo] as $user.  The file stays in the history: attaching\
            a file of that name again brings it back.  Nothing is pushed."]} return
    try {
        ui::busy { fossil::attachRecord $repo $name [target $shown] "" "" $user }
    } trap {FOSSIL ARTIFACT} msg {
        ui::errorBox -parent .wiki -title "Delete attachment" "Not deleted." $msg
    }
    fillAttachments $shown
}

proc tkwiki::viewAttachment {src name} {
    variable repo
    if {[imageview::kind $name] ne ""} {
        imageview::showArtifact $repo $src $name -parent .wiki
        return
    }
    lassign [fossil::run artifact -R $repo $src] code out
    if {$code} {
        tk_messageBox -parent .wiki -icon error -title Attachment -message "Cannot read the attachment:" \
            -detail $out
        return
    }
    if {[string first \0 $out] >= 0} {
        tk_messageBox -parent .wiki -icon info -title Attachment -message "This is not a text file." \
            -detail "Save it to look at it."
        return
    }
    diffview::show $name $out
}

proc tkwiki::saveAttachment {src name} {
    variable repo
    set file [tk_getSaveFile -parent .wiki -title "Save attachment" -initialfile $name]
    if {$file eq ""} return
    lassign [fossil::run artifact -R $repo $src [file normalize $file]] code out
    if {$code} {
        tk_messageBox -parent .wiki -icon error -title Attachment -message "Cannot save the attachment:" \
            -detail $out
    }
}

# The attachment on the server.
proc tkwiki::browseAttachment {name} {
    variable remote
    variable shown
    if {$remote eq "" || $shown eq ""} return
    set what [expr {[string match event-* $shown] ? "technote" : "page"}]
    fossil::browse $remote/attachview?$what=[fossil::urlquery [target $shown]]&file=[fossil::urlquery $name]
}

# Attach files to the page or technote shown ("fossil attachment add"), as
# the default user, after a confirmation.  A file with the name of an
# attachment replaces it.
proc tkwiki::attach {} {
    variable repo
    variable pages
    variable shown
    variable attached
    if {$shown eq "" || ![info exists pages($shown)]} return
    set user [user]
    if {$user eq ""} {
        tk_messageBox -parent .wiki -icon info -title Attach -message "Attaching needs a user." \
            -detail "This repository has no default user to record it as (fossil user default)."
        return
    }
    if {![string match event-* $shown] && [catch {fossil::arg [target $shown]}]} {
        tk_messageBox -parent .wiki -icon info -title Attach \
            -message "\"[target $shown]\" cannot be passed to fossil."
        return
    }
    set files [tk_getOpenFile -parent .wiki -title "Attach files" -multiple 1]
    if {![llength $files]} return
    set note [string match event-* $shown]
    set title [dict get $pages($shown) title]
    set what [expr {$note ? "the technote \"$title\"" : "the page $title"}]
    set names [lmap f $files { file tail $f }]
    set old [lmap i [array names attached] { dict get $attached($i) name }]
    set replaced [lmap n $names { if {$n in $old} { set n } else continue }]
    set detail "As $user, in [file tail $repo].  Nothing is pushed."
    if {[llength $replaced]} {
        set detail "Replaces [join $replaced {, }] (the earlier ones stay in the history).\n\n$detail"
    }
    if {![ui::confirm -parent .wiki -title Attach \
            "Attach [join $names {, }] to $what?" $detail]} return
    foreach file $files {
        # (A technote by its ID: its date need not be unique.)
        set args [expr {$note ? [list -t [target $shown]] : [list [fossil::arg [target $shown]]]}]
        lassign [fossil::run attachment add {*}$args [file normalize $file] -R $repo] code out
        if {$code} {
            tk_messageBox -parent .wiki -icon error -title Attach \
                -message "fossil attachment add failed:" -detail [string trim $out]
            break
        }
    }
    fillAttachments $shown
}

# The default user: changes are recorded as this user ("" if none).
proc tkwiki::user {} {
    variable repo
    lassign [fossil::run user default -R $repo] code out
    expr {$code ? "" : [string trim $out]}
}

# A technote's tags and color from its T cards.
proc tkwiki::noteTags {cards} {
    set tags {}
    set color ""
    foreach t [expr {[dict exists $cards T] ? [dict get $cards T] : {}}] {
        if {[regexp {^\+sym-(\S+)} $t -> tag]} { lappend tags $tag }
        if {[regexp {^\+bgcolor \S+ (\S+)} $t -> c]} { set color $c }
    }
    list [join [lsort $tags] ", "] $color
}

# The editor: edit the version shown (and commit it as the newest), or a
# new page or technote.
proc tkwiki::editor {mode} {
    variable pages
    variable shown
    variable current
    variable formats
    variable editMode $mode
    variable editName ""
    variable editComment ""
    variable editDate ""
    variable editTags ""
    variable editColor ""
    variable editFormat ""
    variable editDone ""
    variable editCrlf 0
    set user [user]
    if {$user eq ""} {
        tk_messageBox -parent .wiki -icon info -title Wiki -message "Changes need a user." \
            -detail "This repository has no default user to record them as (fossil user default)."
        return
    }
    if {$mode eq "edit" && $current eq ""} return
    set text ""
    set mimetype text/x-fossil-wiki
    set note [expr {$mode eq "newnote" || ($mode eq "edit" && [string match event-* $shown])}]
    if {$mode eq "edit"} {
        set cards [dict get $current cards]
        set text [dict get $current text]
        # Pages edited on the web have CRLF line ends: edited without the
        # CRs, committed with them again (so that only the lines changed
        # differ).
        set editCrlf [expr {[string first "\r\n" $text] >= 0}]
        set text [string map {"\r\n" "\n"} $text]
        set mimetype [dict get $current mimetype]
        if {$note} {
            set editComment [dict get $pages($shown) title]
            if {[dict exists $cards E]} {
                set editDate [string map {T " "} [lindex [dict get $cards E] 0]]
            }
            lassign [noteTags $cards] editTags editColor
        } else {
            set editName [dict get $pages($shown) title]
        }
    } elseif {$mode eq "newnote"} {
        set editDate [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S" -gmt 1]
    }
    set editFormat [lindex $formats [expr {[lsearch -exact $formats $mimetype] - 1}]]

    set w .wiki.edit
    destroy $w
    toplevel $w
    wm title $w [dict get {edit "Edit" newpage "New page" newnote "New technote"} $mode]
    wm transient $w .
    wm geometry $w 800x600
    set f $w.f
    ttk::frame $f -padding 8
    set row 0
    if {$note} {
        ttk::label $f.lc -text "Comment:"
        ttk::entry $f.comment -textvariable tkwiki::editComment
        ttk::label $f.ld -text "Date (UTC):"
        ttk::entry $f.date -textvariable tkwiki::editDate -width 20
        ttk::label $f.lt -text "Tags:"
        ttk::entry $f.tags -textvariable tkwiki::editTags
        ttk::label $f.lk -text "Color:"
        ttk::entry $f.color -textvariable tkwiki::editColor -width 10
        # (The date is how fossil finds the technote: not changed here.)
        if {$mode eq "edit"} { $f.date state readonly }
        grid $f.lc $f.comment - - -sticky ew -pady 2
        grid $f.ld $f.date $f.lk $f.color -sticky w -pady 2
        grid $f.lt $f.tags - - -sticky ew -pady 2
    } else {
        ttk::label $f.ln -text "Page:"
        ttk::entry $f.name -textvariable tkwiki::editName
        if {$mode eq "edit"} { $f.name state readonly }
        grid $f.ln $f.name - - -sticky ew -pady 2
    }
    # The text with its preview, the format chosen above it (as tickets).
    formattext::create $f.editor -formats $formats -variable tkwiki::editFormat \
        -repo $::tkwiki::repo -text $text
    grid $f.editor - - - -sticky news -pady {6 0}
    ttk::frame $f.b
    ttk::label $f.b.who -text "As $user; nothing is pushed." -foreground gray35
    ttk::button $f.b.commit -text Commit -command {set tkwiki::editDone ok}
    ttk::button $f.b.cancel -text Cancel -command {set tkwiki::editDone cancel}
    pack $f.b.who -side left
    pack $f.b.cancel $f.b.commit -side right -padx {4 0}
    grid $f.b - - - -sticky ew -pady {8 0}
    grid columnconfigure $f 1 -weight 1
    grid columnconfigure $f 3 -weight 1
    grid rowconfigure $f [expr {$note ? 3 : 1}] -weight 1
    pack $f -fill both -expand 1
    wm protocol $w WM_DELETE_WINDOW {set tkwiki::editDone cancel}
    bind $w <Escape> {set tkwiki::editDone cancel}
    focus [expr {$mode eq "newpage" ? "$f.name" : $mode eq "newnote" ? "$f.comment" : [formattext::widget $f.editor]}]
    while 1 {
        vwait tkwiki::editDone
        if {$editDone ne "ok"} break
        if {[commit [formattext::get $f.editor]]} break
    }
    destroy $w
}

# Commit what the editor has: checks, a confirmation, fossil wiki
# create|commit.  1 if done.
proc tkwiki::commit {text} {
    variable repo
    variable pages
    variable shown
    variable formats
    variable editMode
    variable editName
    variable editComment
    variable editDate
    variable editTags
    variable editColor
    variable editFormat
    variable editCrlf
    set w .wiki.edit
    set mimetype [dict get $formats $editFormat]
    set note [expr {$editMode eq "newnote" || ($editMode eq "edit" && [string match event-* $shown])}]
    set name [string trim $editName]
    set comment [string trim $editComment]
    set date [string trim $editDate]
    set tags [string trim $editTags]
    set color [string trim $editColor]
    set problem ""
    if {$note} {
        if {$comment eq ""} {
            set problem "The comment is missing: it is the title of the technote."
        } elseif {![regexp {^\d{4}-\d\d-\d\d \d\d:\d\d(:\d\d)?$} $date]} {
            set problem "The date: YYYY-MM-DD HH:MM:SS."
        } elseif {$color ne "" && ![regexp {^#[0-9A-Fa-f]{6}$} $color]} {
            set problem "The color: #RRGGBB, or none."
        } else {
            # Fossil finds a technote by its date: it must be the only one.
            set same 0
            foreach tag [array names pages event-*] {
                if {[string range [dict get $pages($tag) date] 0 15] eq [string range $date 0 15]
                        && !($editMode eq "edit" && $tag eq $shown)} { incr same }
            }
            if {$same} { set problem "Another technote has the date $date." }
        }
    } else {
        if {$name eq ""} {
            set problem "The name of the page is missing."
        } elseif {$editMode eq "newpage" && [info exists pages(wiki-$name)]} {
            set problem "There is a page named $name already."
        }
    }
    if {$problem eq ""} {
        foreach value [list $name $comment $tags] {
            if {$value ne "" && [catch {fossil::arg $value}]} {
                set problem "\"$value\" cannot be passed to fossil."
            }
        }
    }
    if {$problem ne ""} {
        tk_messageBox -parent $w -icon info -title Wiki -message $problem
        return 0
    }
    set what [expr {$note ? "the technote \"$comment\"" : "the page $name"}]
    set message [expr {$editMode eq "edit" ? "Commit $what?" : "Create $what?"}]
    set detail "As [user], in [file tail $repo] ($editFormat).  Nothing is pushed."
    if {$editMode eq "edit" && [string trim $text] eq "" && !$note} {
        append detail "\n\nThe text is empty: that deletes the page."
    }
    if {![ui::confirm -parent $w -title Wiki $message $detail]} { return 0 }
    set file ""
    try {
        set fh [file tempfile file]
        fconfigure $fh -encoding utf-8 -translation lf
        if {$editCrlf} { set text [string map {"\n" "\r\n"} $text] }
        puts -nonewline $fh $text
        close $fh
        set command [expr {$editMode eq "edit" ? "commit" : "create"}]
        set args [list wiki $command [expr {$note ? $comment : $name}] $file -M $mimetype]
        if {$note} {
            lappend args -t $date
            if {$tags ne ""} { lappend args --technote-tags $tags }
            if {$color ne ""} { lappend args --technote-bgcolor $color }
        }
        lassign [fossil::run {*}$args -R $repo] code out
    } finally {
        if {$file ne ""} { file delete $file }
    }
    if {$code} {
        tk_messageBox -parent $w -icon error -title Wiki -message "fossil wiki $command failed:" \
            -detail [string trim $out]
        return 0
    }
    # Show what was committed.
    reload
    set tag ""
    if {!$note} {
        set tag wiki-$name
    } elseif {$editMode eq "edit"} {
        set tag $shown
    } else {
        foreach t [array names pages event-*] {
            if {[dict get $pages($t) title] eq $comment
                    && [string range [dict get $pages($t) date] 0 15] eq [string range $date 0 15]} {
                set tag $t
            }
        }
    }
    set t .wiki.main.list.t
    if {$tag ne "" && [$t exists $tag]} {
        $t selection set [list $tag]
        $t see $tag
    }
    return 1
}

# The context menu of a page: the buttons of the page shown.
proc tkwiki::popupMenu {m item} {
    set p .wiki.main.page.head
    popup::button $m $p.edit
    popup::button $m $p.changes "Changes of the version shown"
    popup::button $m $p.since "Changes since the version shown"
    popup::button $m $p.save
    popup::button $m $p.attach
    popup::separator $m
    popup::button $m .wiki.b.browse
    popup::separator $m
    popup::copy $m "Copy name" [expr {$item eq "" ? "" : [.wiki.main.list.t set $item title]}]
}
