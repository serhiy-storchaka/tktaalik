# The Tickets tab of tktaalik: ticket search, a Tk version of the /ext page
# "tickets", with the same query language (lib/ticketquery.tcl), and
# comments, edits and new tickets (lib/ticketwrite.tcl).
#
# Settings (search, columns, sort order) are kept in
# ~/.config/tktaalik/tickets.conf.

source [file join [file dirname [file normalize [info script]]] config.tcl]
source [file join [file dirname [file normalize [info script]]] ticketquery.tcl]
source [file join [file dirname [file normalize [info script]]] ticketwrite.tcl]
source [file join [file dirname [file normalize [info script]]] formattext.tcl]
source [file join [file dirname [file normalize [info script]]] ticketreports.tcl]

namespace eval tktsearch {
    variable query is:open         ;# the search box
    variable history {}            ;# earlier searches, newest first
    variable saved {}              ;# the user's searches: name query ...
    variable state ""              ;# the Open/Pending/Closed/All buttons
    variable stateCounts {}
    variable status ""             ;# the status line
    variable project ""
    variable remote ""             ;# the server, for "Open in browser"
    variable rows                  ;# array: uuid -> dict of the row's values
    variable menuItem ""           ;# the row under the context menu
    variable menuKey ""            ;# and its column
    variable order {}              ;# the column order, title and id included
    variable shownTicket ""        ;# the ticket in the details pane
    variable drafts {}             ;# ticket -> unposted comment
    variable hashes {}             ;# [hash] in the shown ticket -> link
    variable chngMime {}           ;# repository -> has ticketchng.mimetype
    variable searched ""           ;# the query of the list shown
    variable format "Fossil wiki"  ;# of new comments and descriptions
    variable formats {
        "Fossil wiki" text/x-fossil-wiki  Markdown text/x-markdown
        {Plain text} text/plain  HTML text/html
    }
    variable configFile [config::path tickets]

}

# ------------------------------------------------------------- settings

proc tktsearch::loadConfig {} {
    variable configFile
    config::get $configFile tickets tktsearch.conf
}

proc tktsearch::saveConfig {} {
    variable configFile
    variable query
    variable saved
    set config [dict create query $query \
        table [dict create shown $::tickets::shown \
            order [.tickets.main.list.t cget -displaycolumns] \
            sort [list $::tickets::sortkey $::tickets::sortdir]] \
        saved $saved]
    config::put $configFile $config {table saved}
}

# ------------------------------------------------------------ repository

proc tktsearch::openRepository {repo} {
    variable project
    variable remote
    set repo [file normalize $repo]
    if {![file isfile $repo]} {
        tk_messageBox -icon error -message "No such repository:\n$repo"
        return 0
    }
    try {
        # Its ticket fields decide the columns and filters.
        ::tickets::useRepository $repo
        set project [lindex [::tickets::sql \
            "SELECT value FROM config WHERE name='project-name'"] 0 0]
    } trap {FOSSIL DB} msg {
        tk_messageBox -icon error -message "Cannot read $repo:\n$msg"
        return 0
    }
    if {$project eq ""} { set project [file rootname [file tail $repo]] }
    # "@me" is the default user; the server without a user name in it.
    lassign [fossil::run user default -R $repo] code ::tickets::me
    if {$code} { set ::tickets::me "" }
    set ::tickets::me [string trim $::tickets::me]
    set remote [fossil::remoteUrl $repo]
    tktaalik::setTitle tickets "Tickets \u2014 $project"
    setupColumns
    buildPresets
    return 1
}

# ----------------------------------------------------------------- search

proc tktsearch::search {} {
    variable query
    variable searched
    variable history
    variable state
    variable stateCounts
    variable status
    variable rows
    set searched $query

    # Control characters out (see lib/ticketquery.tcl).
    set query [string trim [regsub -all {[[:cntrl:]]} $query " "]]
    set q $query

    . configure -cursor watch
    .tickets.status configure -foreground ""
    update idletasks
    try {
        set where [::tickets::buildQuery $q 1]
        set base [::tickets::stripState $q]
        set stateCounts {}
        foreach row [::tickets::sql "SELECT [::tickets::stateExpr], count(*) FROM ticket\
                WHERE [::tickets::buildQuery $base 1] GROUP BY 1"] {
            dict set stateCounts {*}$row
        }
        set exprs {}
        foreach key $::tickets::shown {
            lappend exprs [fossil::outcol [dict get $::tickets::columns $key expr]]
            if {[dict exists $::tickets::extra $key]} {
                lappend exprs [fossil::outcol [dict get $::tickets::extra $key]]
            }
        }
        set result [::tickets::sql "SELECT tkt_uuid, [fossil::outcol title],\
            [::tickets::stateExpr], [join $exprs {, }] FROM ticket\
            WHERE $where ORDER BY [::tickets::orderBy]"]
    } trap {TICKETS QUERY} msg {
        showError $msg
        return
    } trap {FOSSIL DB} msg {
        showError "Database error: $msg"
        return
    } finally {
        . configure -cursor ""
    }

    set history [lrange [linsert [lsearch -all -inline -not -exact $history $q] 0 $q] 0 29]
    .tickets.top.q configure -values $history
    set state [::tickets::queryState $q]
    if {$state eq "" && $base eq $q} { set state all }
    updateStateButtons

    fillTable $result
    set n [llength $result]
    set status "$n [expr {$n == 1 ? "ticket" : "tickets"}]"
    if {$::tickets::me ne ""} { append status "  \u00b7  you are $::tickets::me" }
    append status "  \u00b7  $::tickets::repo"
    if {![catch {::tickets::unsent} n] && $n > 0} {
        append status "  \u00b7  $n unpushed"
    }
}

proc tktsearch::showError {msg} {
    variable status
    set status $msg
    .tickets.status configure -foreground red3
    bell
}

proc tktsearch::updateStateButtons {} {
    variable stateCounts
    set all 0
    foreach s {open pending closed} {
        set n [::tickets::getdef $stateCounts $s 0]
        .tickets.tabs.$s configure -text "[string totitle $s] ($n)"
    }
    dict for {s n} $stateCounts { incr all $n }
    .tickets.tabs.all configure -text "All ($all)"
}

# The Open/Pending/Closed/All buttons: the same search with another state.
proc tktsearch::setState {} {
    variable query
    variable state
    tktaalik::navigate
    set query [::tickets::stripState $query]
    if {$state ne "all"} { set query [string trim "$query is:$state"] }
    search
}

proc tktsearch::preset {q} {
    variable query
    tktaalik::navigate
    set query $q
    search
}

# ------------------------------------------------------------------ table

proc tktsearch::cellText {key value} {
    if {$value in {"" None} || ($value eq "nobody" && $key ne "author")} { return "" }
    if {$key in $::tickets::counts && $value == 0} { return "" }
    return $value
}

proc tktsearch::fillTable {result} {
    # Tk 9 shows images in any cell (cell tags), Tk 8.6 only in the tree.
    set cellImages [expr {![catch {.tickets.main.list.t tag cell has {}}]}]
    set iconCells {}
    variable rows
    set t .tickets.main.list.t
    array unset rows
    set items {}
    foreach row $result {
        set values [lassign $row uuid title status]
        set data [dict create id $uuid title $title]
        set cells [dict create title $title id [string range $uuid 0 9]]
        foreach key $::tickets::shown {
            set values [lassign $values value]
            dict set data $key $value
            set text [cellText $key $value]
            set second ""
            if {[dict exists $::tickets::extra $key]} {
                set values [lassign $values second]
                dict set data [dict get $::tickets::extra $key] $second
                if {$second ni {"" None}} {
                    set text [expr {$text eq "" ? $second : "$text \u00b7 $second"}]
                }
            }
            # Status, priority and severity: only the icon, a cell image
            # (Tk 9) or an emoji (Tk 8.6); the value is the cell's tooltip.
            set icon [iconName $key $value $second]
            if {$icon ne "" && $text ne ""} {
                dict set data tip:$key $text
                if {$cellImages} {
                    dict lappend iconCells $icon [list $uuid $key]
                    set text ""
                } else {
                    set text [sign $key $value $second]
                }
            }
            dict set cells $key $text
        }
        set rows($uuid) $data
        lappend items [list $uuid $cells {} [expr {$status eq "open" ? "" : "inactive"}]]
    }
    # In the order of the query.
    tablecols::setSort $t $::tickets::sortkey $::tickets::sortdir
    tablecols::fill $t $items
    dict for {icon cells} $iconCells {
        $t tag configure icon:$icon -image [icons::get $icon row] -imageanchor center
        $t tag cell add icon:$icon $cells
    }
    if {[llength $result]} {
        set first [lindex [$t children {}] 0]
        $t selection set $first
        $t focus $first
        $t see $first
    } else {
        showDetails ""
    }
}

# ---------------------------------------------------------------- columns

# The columns (lib/tablecols.tcl) for the fields of these tickets: title
# and id always, the rest as chosen; Status also sorts by the resolution
# alone.  The query sorts, and fetches only the
# shown columns.
proc tktsearch::setupColumns {} {
    variable order
    set widths {
        title 30  id 11  tip 6  type 7  state 8  subsystem 18  priority 8  severity 8
        version 12  assignee 11  author 11  closer 11
        created 11  updated 11  closed 11  comments 9  checkins 9  attachments 11
    }
    set cols [dict create \
        title [dict create heading Title width 30 stretch 1 dir asc] \
        id [dict create heading "Ticket id" width 11 dir asc]]
    dict for {key col} $::tickets::columns {
        # (The repository's own fields: a width of their own.)
        set spec [dict create heading [dict get $col heading] \
            width [expr {[dict exists $widths $key] ? [dict get $widths $key] : 12}] dir [dict get $col dir]]
        # Icons only, the value in a tooltip; the heading an icon too.
        if {[dict exists {state 1 priority 1 severity 1} $key]} {
            dict set spec anchor center
            dict set spec icon [icons::get [dict get {state st-open priority pr-8
                severity sv-severe} $key] row]
            dict set spec tip [dict get {state "Status and resolution"
                priority Priority severity Severity} $key]
            dict set spec pixels [expr {[icons::rowSize]
                + [font measure TkDefaultFont " \u25bc"] + 12}]
        }
        if {[dict exists $::tickets::extra $key]} {
            set x [dict get $::tickets::extra $key]
            dict set spec extra [list $x [dict get $::tickets::sorts $x heading] \
                [dict get $::tickets::sorts $x dir]]
        }
        dict set cols $key $spec
    }
    tablecols::setup .tickets.main.list.t $cols -fixed {title id} \
        -defaults $::tickets::defaultColumns -shown $::tickets::shown -order $order \
        -defaultorder {id state priority severity title tip type subsystem version assignee updated} \
        -sort [list $::tickets::sortkey $::tickets::sortdir] \
        -command tktsearch::columnsChanged -sortcommand tktsearch::sortChanged \
        -celltip tktsearch::cellTip
}

# The columns were chosen or moved: a column more needs a new query.
proc tktsearch::columnsChanged {} {
    variable order
    set state [tablecols::state .tickets.main.list.t]
    set order [dict get $state order]
    set shown [dict get $state shown]
    set more [lmap key $shown { if {$key in $::tickets::shown} continue; set key }]
    setShown $shown
    if {[llength $more]} search
}

proc tktsearch::sortChanged {} {
    lassign [dict get [tablecols::state .tickets.main.list.t] sort] key dir
    set ::tickets::sortkey $key
    set ::tickets::sortdir $dir
    set ::tickets::wantedSort [list $key $dir]
    search
}

# Show these columns; the preference also keeps the columns these tickets
# do not have.
proc tktsearch::setShown {shown} {
    set ::tickets::wanted [concat $shown [lmap key $::tickets::wanted {
        if {[dict exists $::tickets::columns $key]} continue
        set key
    }]]
    set ::tickets::shown $shown
}

# Right-click on a ticket: the context menu (on a heading: tablecols).
proc tktsearch::rightClick {x y X Y} {
    if {[.tickets.main.list.t identify region $x $y] ne "heading"} {
        contextMenu $x $y $X $Y
    }
}

# ----------------------------------------------------------- context menu

proc tktsearch::contextMenu {x y X Y} {
    variable rows
    variable remote
    variable menuItem
    set t .tickets.main.list.t
    set item [$t identify item $x $y]
    if {$item eq ""} return
    $t selection set $item
    set menuItem $item
    set column [$t identify column $x $y]
    set key [lindex [$t cget -displaycolumns] [expr {[string range $column 1 end] - 1}]]

    set m .tickets.ctx
    $m delete 0 end
    set data $rows($item)
    set facets {}
    if {[dict exists $::tickets::columns $key]} {
        lappend facets $key [dict get $data $key]
        if {[dict exists $::tickets::extra $key]} {
            set second [dict get $::tickets::extra $key]
            lappend facets $second [dict get $data $second]
        }
    }
    foreach {k value} $facets {
        if {[cellText $k $value] eq ""} continue
        set term [::tickets::termText 0 $k $value]
        $m add command -label "Filter $term" -command [list tktsearch::addTerm $k $value 0]
        $m add command -label "Exclude $term" -command [list tktsearch::addTerm $k $value 1]
    }
    if {[$m index end] ne "none"} { $m add separator }
    $m add command -label "Open in browser" -command [list tktsearch::openTicket $item] \
        -state [expr {$remote eq "" ? "disabled" : "normal"}]
    $m add command -label "Copy ticket id" -command [list ui::copy $item]
    $m add command -label "Edit ticket\u2026" -command [list tktsearch::editTicket $item]
    set closable [::tickets::canWrite status]
    if {$closable} {
        set closable [expr {![isClosed [lindex [::tickets::sql "SELECT\
            [fossil::outcol "coalesce([::tickets::field status],'')"] FROM ticket\
            WHERE tkt_uuid=[fossil::sqlstr $item]"] 0 0]]}]
    }
    $m add command -label "Close ticket\u2026" -command [list tktsearch::closeTicket $item] \
        -state [expr {$closable ? "normal" : "disabled"}]
    $m add command -label "Copy title" \
        -command [list ui::copy [dict get $data title]]
    tk_popup $m $X $Y
}

proc tktsearch::addTerm {key value neg} {
    variable query
    tktaalik::navigate
    if {$neg} {
        set query [string trim "$query [::tickets::termText 1 $key $value]"]
    } else {
        set query [::tickets::addTerm $query $key $value]
    }
    search
}

proc tktsearch::openTicket {uuid} {
    if {$uuid ne ""} { openUrl tktview/$uuid }
}

# Open a page of the server in the browser.
proc tktsearch::openUrl {path} {
    variable remote
    if {[string match */ $path]} return
    ui::openServer $remote $path -quiet 1 -browse tktsearch::browse
}

proc tktsearch::browse {url} {
    fossil::browse $url
}

# ----------------------------------------------------------------- window

# The pop-up of the Searches button: the built-in searches that these
# tickets support, the saved ones, and removing a saved one.
proc tktsearch::buildPresets {} {
    variable saved
    set m .tickets.top.searches.m
    $m delete 0 end
    set presets {}
    if {$::tickets::me ne ""} {
        lappend presets {Assigned to me} {is:open assignee:@me} \
            {Involving me} {is:open involves:@me} - -
    }
    lappend presets \
        {Open bugs} {is:open type:bug} \
        {Open patches} {is:open type:patch} \
        {Open RFEs} {is:open type:rfe} \
        Unassigned {is:open no:assignee} \
        {High priority} {is:open priority:>=7} \
        Critical {is:open severity:critical,severe} \
        {Never answered} {is:open no:comments} \
        {In progress} {is:open has:checkins}
    foreach {name q} $presets {
        if {$name eq "-"} {
            $m add separator
        } elseif {[catch {::tickets::buildQuery $q 1}]} {
            # Not for these tickets (e.g. no assignee field).
        } else {
            $m add command -label $name -command [list tktsearch::preset $q]
        }
    }
    if {[dict size $saved]} {
        $m add separator
        dict for {name q} $saved {
            $m add command -label $name -command [list tktsearch::preset $q]
        }
        set r $m.remove
        destroy $r
        menu $r
        dict for {name q} $saved {
            $r add command -label $name -command [list tktsearch::removeSaved $name]
        }
        $m add separator
        $m add cascade -label "Remove saved search" -menu $r
    }
}

# Save the current search under a name.
proc tktsearch::saveSearch {} {
    variable query
    variable saved
    variable answer
    variable saveName
    set q [string trim $query]
    if {$q eq ""} {
        tk_messageBox -icon info -title "Save search" -message "The search is empty."
        return
    }
    set f [dialog .tickets.save "Save search"]
    set saveName $q
    ttk::label $f.l -text "Name:"
    ttk::entry $f.e -textvariable tktsearch::saveName -width 40
    ttk::label $f.q -text "Search: $q" -foreground gray35
    ttk::frame $f.b
    ttk::button $f.b.ok -text Save -default active -command {set tktsearch::answer 1}
    ttk::button $f.b.cancel -text Cancel -command {set tktsearch::answer 0}
    pack $f.b.cancel $f.b.ok -side right -padx {4 0}
    grid $f.l $f.e -sticky ew -pady 2
    grid $f.q - -sticky w -pady 2
    grid $f.b - -sticky e -pady {8 0}
    bind .tickets.save <Return> {set tktsearch::answer 1}
    bind .tickets.save <Escape> {set tktsearch::answer 0}
    wm protocol .tickets.save WM_DELETE_WINDOW {set tktsearch::answer 0}
    $f.e selection range 0 end
    focus $f.e
    set answer 0
    vwait ::tktsearch::answer
    destroy .tickets.save
    set name [string trim $saveName]
    if {!$answer || $name eq ""} return
    if {[dict exists $saved $name] && [dict get $saved $name] ne $q
            && ![ui::confirm -title "Save search" \
                "Replace the saved search \"$name\"?" \
                "It is: [dict get $saved $name]"]} return
    dict set saved $name $q
    buildPresets
    saveConfig
}

proc tktsearch::removeSaved {name} {
    variable saved
    dict unset saved $name
    buildPresets
    saveConfig
}

proc tktsearch::clearSearch {} {
    variable query
    tktaalik::navigate
    set query ""
    search
    focus .tickets.top.q
}

# Build the tab in the frame .tickets, with its menu bar .tickets.menu.
proc tktsearch::build {} {
    menu .tickets.menu
    .tickets.menu add cascade -label File -underline 0 -menu [menu .tickets.menu.file]
    tktaalik::fileMenu .tickets.menu.file
    tktaalik::quitEntry .tickets.menu.file
    .tickets.menu add cascade -label Ticket -underline 0 -menu [menu .tickets.menu.ticket]
    .tickets.menu.ticket add command -label "New ticket\u2026" -underline 0 -accelerator Ctrl+N \
        -command tktsearch::newTicket
    .tickets.menu.ticket add command -label "Edit ticket\u2026" -underline 0 -accelerator Ctrl+E \
        -command {tktsearch::editTicket $tktsearch::shownTicket}
    .tickets.menu.ticket add command -label "Close ticket\u2026" -underline 0 \
        -command {tktsearch::closeTicket $tktsearch::shownTicket}
    .tickets.menu.ticket add separator
    .tickets.menu.ticket add command -label "Reports\u2026" -underline 0 -command ticketreports::window
    .tickets.menu add cascade -label Help -underline 0 -menu [menu .tickets.menu.help]
    .tickets.menu.help add command -label "Search syntax" -underline 0 \
        -command {help::show tickets search-syntax}

    # The search box and the state buttons.
    ttk::frame .tickets.top -padding {6 6 6 2}
    ttk::menubutton .tickets.top.searches -text Searches -menu .tickets.top.searches.m \
        -direction below
    menu .tickets.top.searches.m
    ttk::combobox .tickets.top.q -textvariable tktsearch::query -font TkFixedFont
    icons::button .tickets.top.go search "Search (Return)" {tktaalik::navigate; tktsearch::search}
    icons::button .tickets.top.save save "Save the search\u2026" tktsearch::saveSearch
    icons::button .tickets.top.clear clear "Clear the search (Escape)" tktsearch::clearSearch
    icons::button .tickets.top.help help "Search syntax (the manual)" {help::show tickets search-syntax}
    pack .tickets.top.searches -side left -padx {0 6}
    pack .tickets.top.help .tickets.top.clear .tickets.top.save .tickets.top.go -side right -padx {4 0}
    pack .tickets.top.q -side left -fill x -expand 1
    ttk::frame .tickets.tabs -padding {6 2}
    foreach s {open pending closed all} {
        ttk::radiobutton .tickets.tabs.$s -style Toolbutton -text [string totitle $s] \
            -variable tktsearch::state -value $s -command tktsearch::setState
        pack .tickets.tabs.$s -side left -padx {0 4}
    }

    # The results above the details of the selected ticket.
    ttk::panedwindow .tickets.main -orient vertical
    ttk::frame .tickets.main.list
    ttk::treeview .tickets.main.list.t -show headings -selectmode browse \
        -yscrollcommand {.tickets.main.list.y set} -xscrollcommand {.tickets.main.list.x set}
    ttk::scrollbar .tickets.main.list.y -command {.tickets.main.list.t yview}
    ttk::scrollbar .tickets.main.list.x -orient horizontal -command {.tickets.main.list.t xview}
    grid .tickets.main.list.t .tickets.main.list.y -sticky news
    grid .tickets.main.list.x -sticky ew
    grid columnconfigure .tickets.main.list 0 -weight 1
    grid rowconfigure .tickets.main.list 0 -weight 1
    .tickets.main.list.t tag configure inactive -foreground gray45

    # The details: a header with the fields, above tabs for the comments,
    # the check-ins and the attachments.
    ttk::frame .tickets.main.details
    set h .tickets.main.details.head
    text $h -wrap word -height 2 -padx 8 -pady 4 -font TkTextFont -state disabled \
        -borderwidth 0 -highlightthickness 0 -cursor "" \
        -background [ttk::style lookup TFrame -background]
    # Sizes follow the fonts (negative sizes are pixels).
    $h tag configure title -font TkHeadingFont -spacing3 2
    $h tag configure fields -spacing3 1
    $h tag configure meta -foreground gray40
    $h tag configure label -foreground gray40
    # The values: links to the tickets with them (the hand over them).
    $h tag configure fieldlink -foreground #0b57d0
    $h tag bind fieldlink <Enter> [list $h configure -cursor hand2]
    $h tag bind fieldlink <Leave> [list $h configure -cursor ""]
    ttk::style configure Small.Toolbutton -padding {4 0}
    ttk::style configure Small.TButton -padding {8 0} -width 0
    set nb .tickets.main.details.nb
    ttk::notebook $nb
    ttk::notebook::enableTraversal $nb
    ttk::frame $nb.comments
    set d $nb.comments.text
    text $d -wrap word -height 8 -padx 8 -pady 6 \
        -font TkTextFont -yscrollcommand [list $nb.comments.y set] -state disabled
    ttk::scrollbar $nb.comments.y -command [list $d yview]
    grid $d $nb.comments.y -sticky news
    grid columnconfigure $nb.comments 0 -weight 1
    grid rowconfigure $nb.comments 0 -weight 1
    $nb add $nb.comments -text Comments -underline 0
    $nb add [buildCheckins $nb.checkins] -text Check-ins -underline 6
    $nb add [buildAttachments $nb.attachments] -text Attachments -underline 0
    $nb add [buildHistory $nb.history] -text History -underline 0
    bind $nb <<NotebookTabChanged>> +tktsearch::loadHistory
    grid $h -sticky ew
    grid $nb -sticky news
    grid columnconfigure .tickets.main.details 0 -weight 1
    grid rowconfigure .tickets.main.details 1 -weight 1
    bind $h <Configure> tktsearch::fitHead
    # The panels: a darker header line above a lighter body, with the margins
    # in the panel's colour inside and the window's colour on the right.
    set bg [$d cget -background]
    set pad [font measure TkDefaultFont 0]
    set line [font metrics TkDefaultFont -linespace]
    foreach {tag colour} {cardhead gray86 cardbody gray97} {
        $d tag configure $tag -background $colour -lmargincolor $colour \
            -lmargin1 $pad -lmargin2 $pad -rmargin $pad -rmargincolor $bg
    }
    $d tag configure cardhead -font TkHeadingFont -spacing1 3 -spacing3 3
    $d tag configure cardheadmeta -font TkDefaultFont -foreground gray35
    $d tag configure cardbody -font TkFixedFont
    $d tag configure cardfirst -spacing1 [expr {$line / 3}]
    $d tag configure cardlast -spacing3 [expr {$line / 3}]
    $d tag configure cardgap -font [list {*}[font actual TkDefaultFont] -size -[expr {$line / 2}]]
    # The selection over the panels: tags made later are above it.
    $d tag raise sel
    .tickets.main add .tickets.main.list -weight 3
    .tickets.main add .tickets.main.details -weight 2

    ttk::label .tickets.status -textvariable tktsearch::status -padding {6 2} -anchor w

    pack .tickets.top -fill x
    pack .tickets.tabs -fill x
    pack .tickets.status -side bottom -fill x
    pack .tickets.main -fill both -expand 1

    menu .tickets.ctx

    # Bindings.
    bind .tickets.top.q <Return> {tktaalik::navigate; tktsearch::search}
    bind .tickets.top.q <<ComboboxSelected>> {tktaalik::navigate; tktsearch::search}
    bind .tickets.top.q <Escape> tktsearch::clearSearch
    set t .tickets.main.list.t
    bind $t <<TreeviewSelect>> {tktsearch::showDetails [lindex [.tickets.main.list.t selection] 0]}
    # (The ticket is shown below: double-click edits it; the web page is
    # in the context menu.)
    bind $t <Double-1> {
        if {[.tickets.main.list.t identify region %x %y] eq "cell"} {
            tktsearch::editTicket [.tickets.main.list.t identify item %x %y]
        }
    }
    bind $t <Return> {tktsearch::editTicket [lindex [.tickets.main.list.t selection] 0]}
    if {[tk windowingsystem] eq "aqua"} {
        bind $t <2> {tktsearch::rightClick %x %y %X %Y}
        bind $t <Control-1> {tktsearch::rightClick %x %y %X %Y}
    } else {
        bind $t <3> {tktsearch::rightClick %x %y %X %Y}
    }
    bind .tickets.main.details.nb.comments.text <Configure> {tktsearch::fitReply %W}
    tktaalik::shortcut tickets <Control-n> tktsearch::newTicket
    tktaalik::shortcut tickets <Control-e> {tktsearch::editTicket $tktsearch::shownTicket}
    tktaalik::shortcut tickets <Control-f> {focus .tickets.top.q; .tickets.top.q selection range 0 end}
    tktaalik::shortcut tickets <F5> tktsearch::search

    # The settings.
    variable query
    variable order
    set config [loadConfig]
    set query [::tickets::getdef $config query is:open]
    variable saved [::tickets::getdef $config saved {}]
    if {[catch {dict size $saved}]} { set saved {} }
    # The columns: a table dict of lists, like the other tabs.  The names
    # are checked as in the web page's cols= and sort= parameters.
    set table [::tickets::getdef $config table {}]
    set shown [::tickets::parseColumns [join [::tickets::getdef $table shown {}] ,]]
    if {[llength $shown]} { set ::tickets::wanted $shown }
    set sort [::tickets::parseSort [join [::tickets::getdef $table sort {}] -]]
    if {$sort ne ""} { set ::tickets::wantedSort $sort }
    set order [::tickets::getdef $table order {}]
}

# Use the repository ($root: its checkout, or "").
proc tktsearch::setRepository {repo root} {
    if {[openRepository $repo]} { search }
    if {[winfo exists .reports]} { ticketreports::setRepository }
}

# The tab is shown: search again if the repository has changed.
proc tktsearch::activate {} {
    if {[tktaalik::changed tickets]} { search }
    focus .tickets.top.q
}

# Search for $q (from the command line or another tab).
proc tktsearch::setQuery {q} {
    variable query
    set query $q
    if {$::tickets::repo ne ""} { search }
}

source [file join [file dirname [file normalize [info script]]] ticketdialogs.tcl]
source [file join [file dirname [file normalize [info script]]] ticketdetails.tcl]
source [file join [file dirname [file normalize [info script]]] ticketattach.tcl]
