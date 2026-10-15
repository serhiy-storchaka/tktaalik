# The Tags tab of tktaalik: the tags of check-ins
# (release tags such as core-9-0-4, the CI tags), each with the check-in it
# is on and its history: where it was added and cancelled, with what value.
# Branch names (tags that propagate), cancelled tags and properties (the
# raw tags Fossil keeps: bgcolor, closed, hidden, comment...) are listed on
# request.  A tag's check-in can be shown in the Timeline, a branch in the
# Branches tab.  Tags can be added to check-ins, cancelled on them and
# moved to the newest check-in of their branch (lib/tagwrite.tcl: "fossil
# tag add/cancel", in the local repository).

source [file join [file dirname [file normalize [info script]]] fossil.tcl]
source [file join [file dirname [file normalize [info script]]] tablecols.tcl]
source [file join [file dirname [file normalize [info script]]] tagwrite.tcl]
source [file join [file dirname [file normalize [info script]]] histops.tcl]

namespace eval tktags {
    variable repo ""
    variable root ""
    variable remote ""
    variable tags             ;# array: name -> dict of the tag
    variable tips {}          ;# branch -> its newest check-in, as asked for
    variable filter ""
    variable showBranches 0
    variable showCancelled 0
    variable showProperties 0
    variable selected ""
    variable status ""
    variable shown {}         ;# the filter and options of the list shown
    variable config {}
    variable configFile [config::path tags]
}

proc tktags::loadConfig {} {
    variable configFile
    variable config
    set config [config::get $configFile tags]
}

proc tktags::saveConfig {} {
    variable configFile
    variable config
    variable filter
    variable showBranches
    variable showCancelled
    variable showProperties
    if {[winfo exists .tags.main.list.t]} {
        dict set config table [tablecols::state .tags.main.list.t]
    }
    dict set config filter $filter
    dict set config showBranches $showBranches
    dict set config showCancelled $showCancelled
    dict set config showProperties $showProperties
    config::put $configFile $config {table}
}


proc tktags::build {} {
    variable config
    variable filter
    variable showBranches
    variable showCancelled
    variable showProperties
    menu .tags.menu
    .tags.menu add cascade -label File -underline 0 -menu [menu .tags.menu.file]
    tktaalik::fileMenu .tags.menu.file
    .tags.menu.file add command -label Refresh -underline 0 -accelerator F5 -command tktags::reload
    tktaalik::quitEntry .tags.menu.file
    .tags.menu add cascade -label Tag -underline 0 -menu [menu .tags.menu.tag \
        -postcommand {popup::fill .tags.menu.tag tktags::popupMenu $tktags::selected}]
    loadConfig
    set filter [tktaalik::getdef $config filter ""]
    set showBranches [tktaalik::getdef $config showBranches 0]
    set showCancelled [tktaalik::getdef $config showCancelled 0]
    set showProperties [tktaalik::getdef $config showProperties 0]

    ttk::frame .tags.top -padding {6 6 6 2}
    ttk::label .tags.top.fl -text "Find:"
    ttk::entry .tags.top.filter -textvariable tktags::filter -width 30
    ttk::checkbutton .tags.top.branches -text "Branch names" -variable tktags::showBranches \
        -command {tktaalik::navigate; tktags::showList}
    ttk::checkbutton .tags.top.cancelled -text "Cancelled" -variable tktags::showCancelled \
        -command {tktaalik::navigate; tktags::showList}
    ttk::checkbutton .tags.top.properties -text "Properties" -variable tktags::showProperties \
        -command {tktaalik::navigate; tktags::showList}
    icons::tooltip .tags.top.properties "Fossil's raw tags: bgcolor, closed, hidden, comment..."
    pack .tags.top.fl .tags.top.filter .tags.top.branches .tags.top.cancelled .tags.top.properties \
        -side left -padx {0 6}
    trace add variable ::tktags::filter write {::apply {args {
        tktaalik::typing .tags.top.filter
        after cancel tktags::showList
        after 200 tktags::showList
    }}}

    ttk::panedwindow .tags.main -orient vertical
    ui::splitByWeights .tags.main
    ttk::frame .tags.main.list
    set t .tags.main.list.t
    ttk::treeview $t -show headings -selectmode browse -yscrollcommand {.tags.main.list.y set}
    ttk::scrollbar .tags.main.list.y -command [list $t yview]
    grid $t .tags.main.list.y -sticky news
    grid columnconfigure .tags.main.list 0 -weight 1
    grid rowconfigure .tags.main.list 0 -weight 1
    $t tag configure cancelled -foreground gray50
    $t tag configure branch -foreground #1f5f9f
    $t tag configure property -foreground #7a5a00
    tablecols::setup $t {
        name     {heading Tag width 34}
        kind     {heading Kind width 10}
        hash     {heading Check-in width 11}
        branch   {heading Branch width 18 tip "The branch of the check-in"}
        date     {heading Date width 16 dir desc}
        user     {heading User width 12}
        comment  {heading Comment width 40 stretch 1}
        count    {heading Check-ins width 9 type integer dir desc anchor e}
    } -fixed {name} -defaults {kind hash branch date user comment} \
        -shown [tktaalik::getdef [tktaalik::getdef $config table {}] shown {}] \
        -order [tktaalik::getdef [tktaalik::getdef $config table {}] order {}] \
        -sort [tktaalik::getdef [tktaalik::getdef $config table {}] sort {date desc}]

    ttk::frame .tags.main.details
    set d .tags.main.details.text
    text $d -wrap word -height 8 -padx 8 -pady 6 -font TkTextFont -state disabled \
        -yscrollcommand {.tags.main.details.y set}
    ttk::scrollbar .tags.main.details.y -command [list $d yview]
    $d tag configure title -font TkHeadingFont -spacing3 4
    $d tag configure meta -foreground gray40
    $d tag configure hash -font TkFixedFont
    # The branch of the check-in: a link to it in the Branches tab.
    $d tag configure branchlink -foreground #0b57d0
    $d tag bind branchlink <Enter> [list $d configure -cursor hand2]
    $d tag bind branchlink <Leave> [list $d configure -cursor ""]
    $d tag bind branchlink <ButtonRelease-1> tktags::showBranch
    grid $d .tags.main.details.y -sticky news
    grid columnconfigure .tags.main.details 0 -weight 1
    grid rowconfigure .tags.main.details 0 -weight 1
    .tags.main add .tags.main.list -weight 3
    .tags.main add .tags.main.details -weight 1

    ttk::frame .tags.b -padding 6
    ttk::label .tags.b.status -textvariable tktags::status -anchor w
    ttk::button .tags.b.timeline -text "Show in Timeline" -command tktags::showTimeline
    ttk::button .tags.b.branch -text "Show in Branches" -command tktags::showBranch
    ttk::button .tags.b.browse -text "Open in browser" -command tktags::browse
    ttk::button .tags.b.add -text "Add\u2026" -command tktags::addTag
    ttk::button .tags.b.cancel -text "Cancel\u2026" -command tktags::cancelTag
    ttk::button .tags.b.move -text "Move\u2026" -command tktags::moveTag
    icons::tooltip .tags.b.add "Add the tag to a check-in"
    icons::tooltip .tags.b.cancel "Cancel the tag on a check-in it is on"
    pack .tags.b.browse .tags.b.branch .tags.b.timeline .tags.b.move .tags.b.cancel .tags.b.add \
        -side right -padx {4 0}
    pack .tags.b.status -side left -fill x -expand 1
    pack .tags.top -fill x
    pack .tags.b -side bottom -fill x
    pack .tags.main -fill both -expand 1

    bind $t <<TreeviewSelect>> {tktags::showDetails [lindex [.tags.main.list.t selection] 0]}
    bind $t <Double-1> {
        if {[%W identify region %x %y] eq "cell"} { tktags::showTimeline }
    }
    # (Ctrl+C: the name; the check-in has its button in the details.)
    popup::copyKey $t {string trim}
    tktaalik::shortcut tags <F5> tktags::reload
    tktaalik::shortcut tags <Control-f> {focus .tags.top.filter; .tags.top.filter selection range 0 end}
    tktaalik::shortcut tags <Control-slash> {focus .tags.top.filter; .tags.top.filter selection range 0 end}
    popup::attach .tags.main.list.t tktags::popupMenu
}

proc tktags::setRepository {path newRoot} {
    variable repo $path
    variable root $newRoot
    variable remote [fossil::remoteUrl $path]
    tktaalik::setTitle tags "Tags \u2014 [file rootname [file tail $repo]]"
    reload
}

proc tktags::activate {} {
    if {[tktaalik::changed tags]} { reload }
    focus .tags.main.list.t
}

# Where we are (tktaalik::location): the filter and options of the list,
# the tag.
proc tktags::here {} {
    variable shown
    variable selected
    list {*}$shown $selected
}

# Back or Forward to a place of here.
proc tktags::goTo {place} {
    variable filter
    variable showBranches
    variable showCancelled
    variable selected
    variable showProperties
    lassign $place f branches cancelled properties name
    set filter $f
    if {$branches ne ""} {
        set showBranches $branches
        set showCancelled $cancelled
        set showProperties $properties
    }
    set selected $name
    showList
    after cancel tktags::showList
}

# All symbolic tags and properties: for each, its kind (a tag on
# check-ins, a branch name that propagates, one cancelled everywhere, or a
# property: a raw tag), the newest check-in it is on (of a branch: its
# newest check-in) and that check-in's branch, how many.  (A property's id in the list: its name after
# a space, which a symbolic name cannot have.)
proc tktags::reload {} {
    variable repo
    variable tags
    variable status
    variable tips {}
    array unset tags
    try {
        set rows [fossil::sql $repo "WITH r AS (SELECT x.tagid, x.rid, x.tagtype,\
                max(x.tagtype) OVER (PARTITION BY x.tagid) AS kind,\
                count(*) FILTER (WHERE x.tagtype > 0) OVER (PARTITION BY x.tagid) AS n,\
                row_number() OVER (PARTITION BY x.tagid ORDER BY x.tagtype = 0, e.mtime DESC) AS k\
                FROM tagxref x JOIN event e ON e.objid=x.rid\
                WHERE x.tagid IN (SELECT tagid FROM tag WHERE tagname NOT GLOB 'wiki-*'\
                    AND tagname NOT GLOB 'tkt-*' AND tagname NOT GLOB 'event-*'))\
            SELECT [fossil::outcol "CASE WHEN t.tagname GLOB 'sym-*' THEN substr(t.tagname,5)\
                ELSE ' '||t.tagname END"], r.kind, r.n, b.uuid,\
                strftime('%Y-%m-%d %H:%M', e.mtime), [fossil::outcol "coalesce(e.euser,e.user,'')"],\
                [fossil::outcol "coalesce(e.ecomment,e.comment,'')"],\
                [fossil::outcol "coalesce((SELECT bx.value FROM tagxref bx WHERE bx.rid=r.rid\
                    AND bx.tagtype>0 AND bx.tagid=(SELECT tagid FROM tag WHERE tagname='branch')),'')"]\
            FROM r JOIN tag t ON t.tagid=r.tagid JOIN blob b ON b.rid=r.rid\
            JOIN event e ON e.objid=r.rid WHERE r.k=1"]
    } trap {FOSSIL DB} msg {
        set status "Cannot read the tags: $msg"
        set rows {}
    }
    # The names of branches, now or before (renamed ones): a propagating
    # tag of another name is a tag (and can be cancelled).
    set branches {}
    catch {
        foreach row [fossil::sql $repo "SELECT DISTINCT [fossil::outcol value] FROM tagxref\
                WHERE tagid=(SELECT tagid FROM tag WHERE tagname='branch')"] {
            dict set branches [lindex $row 0] 1
        }
    }
    foreach row $rows {
        lassign $row name kind count uuid date user comment branch
        set propagates [expr {$kind == 2}]
        set kind [expr {[string match " *" $name] ? "Property" : [lindex {Cancelled Tag Branch} $kind]}]
        if {$kind eq "Branch" && ![dict exists $branches $name]} { set kind Tag }
        set tags($name) [dict create kind $kind count $count propagates $propagates \
            uuid $uuid date $date user $user branch $branch \
            comment [fossil::oneLine $comment]]
    }
    showList
}

proc tktags::showList {} {
    variable tags
    variable filter
    variable showBranches
    variable showCancelled
    variable showProperties
    variable selected
    variable status
    variable shown
    set shown [list $filter $showBranches $showCancelled $showProperties]
    set f [string tolower [string trim $filter]]
    set items {}
    set counts {Tag 0 Branch 0 Cancelled 0 Property 0}
    foreach name [array names tags] {
        set g $tags($name)
        set kind [dict get $g kind]
        dict incr counts $kind
        if {$kind eq "Branch" && !$showBranches} continue
        if {$kind eq "Cancelled" && !$showCancelled} continue
        if {$kind eq "Property" && !$showProperties} continue
        if {$f ne "" && [string first $f [string tolower [string trim $name]]] < 0} continue
        lappend items [list $name [dict create name [string trim $name] kind $kind \
            hash [string range [dict get $g uuid] 0 9] branch [branchOf $name] date [dict get $g date] \
            user [dict get $g user] comment [dict get $g comment] count [dict get $g count]] \
            {} [dict get {Tag {} Branch branch Cancelled cancelled Property property} $kind]]
    }
    set t .tags.main.list.t
    tablecols::fill $t $items
    set status "[llength $items] shown; [dict get $counts Tag] tags,\
        [dict get $counts Branch] branch names, [dict get $counts Cancelled] cancelled,\
        [dict get $counts Property] properties"
    if {$selected ne "" && [$t exists $selected]} {
        $t selection set [list $selected]
        $t see $selected
    } elseif {[llength [$t children {}]]} {
        $t selection set [lrange [$t children {}] 0 0]
    } else {
        showDetails ""
    }
}

# A tag's history: each check-in it was added to or cancelled on, when.
proc tktags::showDetails {name} {
    variable repo
    variable tags
    variable selected
    set selected $name
    set d .tags.main.details.text
    $d configure -state normal
    $d delete 1.0 end
    destroy $d.copyname $d.copyhash
    set ok [expr {$name ne "" && [info exists tags($name)]}]
    .tags.b.timeline state [expr {$ok && [dict get $tags($name) kind] ne "Branch" ? "!disabled" : "disabled"}]
    .tags.b.branch state [expr {$ok && [branchOf $name] ne "" ? "!disabled" : "disabled"}]
    icons::tooltip .tags.b.branch [expr {!$ok || [dict get $tags($name) kind] eq "Branch"
        ? "The branch in the Branches tab" : "The branch of its check-in, [branchOf $name], in the Branches tab"}]
    .tags.b.browse state [expr {$ok && [dict get $tags($name) kind] ne "Property" ? "!disabled" : "disabled"}]
    .tags.b.cancel state [expr {$ok && [dict get $tags($name) kind] in {Tag Property} ? "!disabled" : "disabled"}]
    set why [unmovable $name]
    .tags.b.move state [expr {$why eq "" ? "!disabled" : "disabled"}]
    icons::tooltip .tags.b.move [expr {$why eq "" ? "Move the tag to the newest check-in of [branchOf $name]"
        : "Move the tag to the newest check-in of its branch: $why"}]
    if {!$ok} {
        $d configure -state disabled
        return
    }
    set g $tags($name)
    # The name and the check-in, each with its copy button.
    $d insert end [string trim $name] title
    $d window create end -align center -padx 4 -window [icons::copyButton $d.copyname \
        "Copy the tag name" [list ui::copy [string trim $name]]]
    $d insert end \n title
    set uuid [dict get $g uuid]
    $d insert end "Check-in " meta [string range $uuid 0 9] hash
    $d window create end -align center -padx 4 -window [icons::copyButton $d.copyhash \
        "Copy the check-in's hash (all of it)" [list ui::copy $uuid]]
    # (A branch name is its own branch.)
    if {[dict get $g kind] ne "Branch" && [dict get $g branch] ne ""} {
        $d insert end "on branch " meta [dict get $g branch] branchlink
    }
    $d insert end \n
    if {[dict get $g kind] eq "Branch"} {
        $d insert end "A branch name: on [dict get $g count] check-ins, the newest of\
            [dict get $g date] by [dict get $g user].\n" meta
    } else {
        # Where it was set and cancelled (not where it propagated), with
        # what value; the newest 1000.
        set rows [fossil::sql $repo "SELECT * FROM (SELECT x.tagtype, b.uuid,\
            strftime('%Y-%m-%d %H:%M', x.mtime), [fossil::outcol "coalesce(x.value,'')"],\
            [fossil::outcol "coalesce(e.ecomment,e.comment,'')"], x.mtime AS m\
            FROM tagxref x JOIN tag t ON t.tagid=x.tagid JOIN blob b ON b.rid=x.rid\
            LEFT JOIN event e ON e.objid=x.rid\
            WHERE t.tagname=[fossil::sqlstr [rawName $name]] AND (x.tagtype<2 OR x.origid=x.rid)\
            ORDER BY x.mtime DESC LIMIT 1000) ORDER BY m"]
        foreach row $rows {
            lassign $row type uuid date value comment
            set what [expr {$type == 0 ? "cancelled on" : "added to"}]
            $d insert end "$date  " meta "$what " "" [string range $uuid 0 9] hash
            if {$value ne ""} { $d insert end " = [lindex [split $value \n] 0]" "" }
            $d insert end "  [fossil::oneLine $comment]\n" meta
        }
    }
    $d configure -state disabled
}

# The name of a tag in the tag table: "sym-NAME", or a property's own.
proc tktags::rawName {name} {
    expr {[string match " *" $name] ? [string range $name 1 end] : "sym-$name"}
}

# Add the tag shown (or a new one) to a check-in.
proc tktags::addTag {} {
    variable repo
    variable tags
    variable selected
    set name ""
    set checkin ""
    if {$selected ne "" && [info exists tags($selected)]} {
        set name [string trim $selected]
        if {[dict get $tags($selected) kind] eq "Property"} { set name "" }
    }
    # (Then the tag as named in the dialog.)
    tagwrite::addTag $repo $checkin $name {tktags::changed [string trim $tagwrite::f(name)]}
}

# Cancel the tag shown on a check-in it is on (it was added to): which,
# if there are more.
proc tktags::cancelTag {} {
    variable repo
    variable tags
    variable selected
    if {$selected eq "" || ![info exists tags($selected)]} return
    set kind [dict get $tags($selected) kind]
    if {$kind ni {Tag Property}} { bell; return }
    set raw [expr {$kind eq "Property"}]
    set name [string trim $selected]
    set rows [fossil::sql $repo "SELECT b.uuid, strftime('%Y-%m-%d %H:%M', e.mtime),\
        [fossil::outcol "coalesce(e.ecomment,e.comment,'')"]\
        FROM tagxref x JOIN blob b ON b.rid=x.rid LEFT JOIN event e ON e.objid=x.rid\
        WHERE x.tagid=(SELECT tagid FROM tag WHERE tagname=[fossil::sqlstr [rawName $selected]])\
        AND x.tagtype>0 AND x.origid=x.rid ORDER BY x.mtime DESC LIMIT 1000"]
    if {![llength $rows]} {
        tk_messageBox -icon info -title "Cancel tag" -message "$name is on no check-in now."
        return
    }
    set uuid [lindex $rows 0 0]
    if {[llength $rows] > 1} {
        set uuid [chooseCheckin $name $rows]
        if {$uuid eq ""} return
    }
    tagwrite::cancelTag $repo $name $uuid $raw [list tktags::changed $selected]
}

# The newest check-in of BRANCH (as Fossil takes for its name).
proc tktags::tipOf {branch} {
    variable repo
    variable tips
    if {![dict exists $tips $branch]} {
        dict set tips $branch [lindex [fossil::sql $repo "SELECT b.uuid FROM tagxref x\
            JOIN event e ON e.objid=x.rid JOIN blob b ON b.rid=x.rid\
            WHERE x.tagid=(SELECT tagid FROM tag WHERE tagname='branch') AND x.tagtype>0\
            AND x.value=[fossil::sqlstr $branch] ORDER BY e.mtime DESC LIMIT 1"] 0 0]
    }
    dict get $tips $branch
}

# Why the tag NAME cannot be moved to the tip of its branch, or "": only a
# tag on one check-in, that does not propagate (a branch name, or one that
# goes on to the descendants, is on many), on a branch.
proc tktags::unmovable {name} {
    variable tags
    if {$name eq "" || ![info exists tags($name)]} { return "no tag selected" }
    set g $tags($name)
    switch [dict get $g kind] {
        Branch { return "a branch name" }
        Cancelled { return "cancelled" }
        Property { return "a property" }
    }
    if {[dict get $g propagates]} { return "it propagates to the descendants" }
    if {[dict get $g count] != 1} { return "it is on [dict get $g count] check-ins" }
    set branch [dict get $g branch]
    if {$branch eq ""} { return "not on a check-in of a branch" }
    if {[tipOf $branch] eq [dict get $g uuid]} { return "already on the newest check-in of $branch" }
    return ""
}

# Move the tag shown to the newest check-in of its branch.
proc tktags::moveTag {} {
    variable repo
    variable tags
    variable selected
    if {[unmovable $selected] ne ""} { bell; return }
    set g $tags($selected)
    set name [string trim $selected]
    set from [dict get $g uuid]
    set branch [dict get $g branch]
    set value [lindex [fossil::sql $repo "SELECT [fossil::outcol "coalesce(x.value,'')"] FROM tagxref x\
        JOIN blob b ON b.rid=x.rid WHERE b.uuid=[fossil::sqlstr $from] AND x.tagtype=1\
        AND x.tagid=(SELECT tagid FROM tag WHERE tagname=[fossil::sqlstr [rawName $selected]])"] 0 0]
    tagwrite::moveTag $repo $name $from [tipOf $branch] "the tip of $branch" $value \
        [list tktags::changed $selected]
}

# Which of the check-ins ROWS ({uuid date comment} each)?
proc tktags::chooseCheckin {name rows} {
    variable choice
    set w [tagwrite::dialog .tagwrite "Cancel tag"]
    ttk::label $w.l -text "$name is on [llength $rows] check-ins.  Cancel it on:"
    set values [lmap r $rows {
        lassign $r uuid date comment
        string cat [string range $uuid 0 9] "  " $date "  " [fossil::oneLine $comment]
    }]
    set choice [lindex $values 0]
    ttk::combobox $w.c -state readonly -values $values -textvariable tktags::choice -width 70
    grid $w.l -sticky w -pady {0 4}
    grid $w.c -sticky ew
    if {![tagwrite::wait .tagwrite "Cancel tag\u2026"]} { return "" }
    lindex [lindex $rows [lsearch -exact $values $choice]] 0
}

# After a change: the tags again, the tag shown.
proc tktags::changed {name} {
    variable selected
    if {$name ne ""} { set selected $name }
    reload
    # (The same tag selected: no event to show its details again.)
    showDetails $selected
}

# The check-in of a tag in the Timeline tab.
proc tktags::showTimeline {} {
    variable tags
    variable selected
    if {$selected eq "" || ![info exists tags($selected)]} return
    if {[dict get $tags($selected) kind] eq "Branch"} return
    tktaalik::show timeline
    tktimeline::setQuery hash:[string range [dict get $tags($selected) uuid] 0 9]
}

# The branch of tag NAME: a branch name's own, else its check-in's.
proc tktags::branchOf {name} {
    variable tags
    if {$name eq "" || ![info exists tags($name)]} { return "" }
    if {[dict get $tags($name) kind] eq "Branch"} { return $name }
    dict get $tags($name) branch
}

# The branch of the tag shown in the Branches tab.
proc tktags::showBranch {} {
    variable selected
    set branch [branchOf $selected]
    if {$branch eq ""} return
    tktaalik::show branches
    tkbranches::showBranch $branch
}

proc tktags::browse {} {
    variable remote
    variable selected
    if {$remote eq "" || $selected eq ""} return
    set q ""
    foreach c [split [encoding convertto utf-8 $selected] ""] {
        append q [expr {[regexp {[A-Za-z0-9._~-]} $c] ? $c : [format %%%02X [scan $c %c]]}]
    }
    fossil::browse $remote/timeline?t=$q
}

# The context menu of a tag: the buttons below the list.
proc tktags::popupMenu {m item} {
    variable tags
    popup::button $m .tags.b.timeline
    # (Of another tag: the branch of its check-in, named.)
    popup::button $m .tags.b.branch [expr {[info exists tags($item)] && [dict get $tags($item) kind] ne "Branch"
        && [branchOf $item] ne "" ? "Show branch [branchOf $item]" : ""}]
    popup::button $m .tags.b.browse
    $m add command -label "Save as archive\u2026" -command tktags::archive \
        -state [expr {[info exists tags($item)] && [dict get $tags($item) kind] eq "Tag" ? "normal" : "disabled"}]
    $m add command -label "Compare with the previous release\u2026" \
        -command [list tktags::compare [string trim $item]] \
        -state [expr {[info exists tags($item)] && [dict get $tags($item) kind] eq "Tag" ? "normal" : "disabled"}]
    popup::separator $m
    popup::button $m .tags.b.add "Add tag\u2026"
    popup::button $m .tags.b.cancel "Cancel tag\u2026"
    popup::button $m .tags.b.move [expr {[info exists tags($item)] && [branchOf $item] ne ""
        ? "Move to the tip of [branchOf $item]\u2026" : "Move to the tip of its branch\u2026"}]
    popup::default $m [.tags.b.timeline cget -text]
}

# A release (the tag NAME) compared with the one before it, in the
# Timeline (its Compare releases window).
proc tktags::compare {name} {
    if {$name eq ""} return
    tktaalik::show timeline
    update idletasks
    tktimeline::compareReleases $name
}

# The check-in of the tag selected (a release...) as an archive.
proc tktags::archive {} {
    variable repo
    variable tags
    variable selected
    if {$selected eq "" || ![info exists tags($selected)] || [dict get $tags($selected) kind] ne "Tag"} {
        bell
        return
    }
    set name [string trim $selected]
    # (Its check-in by hash: a tag name that looks like a hash prefix would
    # be taken for one.)
    histops::archive $repo [dict get $tags($selected) uuid] $name
}
