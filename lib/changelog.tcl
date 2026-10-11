# The Timeline's release comparison and changelog (sourced by
# tktimeline.tcl, in its namespace): the check-ins of one release that
# another has not (in:NEW -in:OLD, a search like any other), and a
# changelog of what the search finds, grouped by the tickets the
# check-ins name, as Tcl's and Tk's changes.md are: Bug fixes, New
# features, Other tickets, then the other check-ins.  Nothing is written
# to the repository; the text can be edited, copied and saved.
#
#   tktimeline::compareReleases     the window to choose the two releases
#   tktimeline::changelog           the changelog of the search shown
#   tktimeline::changelogData QUERY {checkins tickets}: the check-ins the
#                                   search finds, oldest first (dicts:
#                                   uuid date user comment merge tickets),
#                                   and the tickets they name (uuid ->
#                                   dict: title type status)
#   tktimeline::changelogText DATA MERGES OTHERS BASE
#                                   the Markdown: with merges, with the
#                                   check-ins naming no ticket; links to
#                                   the server BASE ("": relative)

namespace eval tktimeline {
    variable cl                 ;# array: the changelog window's choices
}

# ------------------------------------------------------------ compare

# The tags given to single check-ins (releases are), the newest first.
proc tktimeline::releaseTags {} {
    lmap row [sql "SELECT [fossil::outcol substr(t.tagname,5)] FROM tag t JOIN tagxref x ON x.tagid=t.tagid
        WHERE x.tagtype=1 AND t.tagname GLOB 'sym-*'
        GROUP BY t.tagname ORDER BY max(x.mtime) DESC LIMIT 500"] { lindex $row 0 }
}

proc tktimeline::compareReleases {} {
    variable cl
    variable repo
    if {$repo eq ""} return
    set tags [releaseTags]
    set cl(to) [lindex $tags 0]
    set cl(from) [lindex $tags 1]
    set w .timeline.compare
    set f [ui::dialog $w "Compare releases" -escape [list destroy $w] -help timeline#releases-and-changelogs]
    ttk::label $f.intro -wraplength 460 -justify left -text "The check-ins in the newer release that\
        the older one does not have (in:NEWER -in:OLDER): a search of the Timeline, from which a\
        changelog can be made.  Any check-in name will do: a tag, a branch, a hash."
    ttk::label $f.lto -text "Newer:"
    ttk::combobox $f.to -textvariable tktimeline::cl(to) -values [linsert $tags 0 main trunk] -width 30
    ttk::label $f.lfrom -text "Older:"
    ttk::combobox $f.from -textvariable tktimeline::cl(from) -values $tags -width 30
    grid $f.intro - -sticky w -pady {0 8}
    grid $f.lto $f.to -sticky w -pady 2
    grid $f.lfrom $f.from -sticky w -pady 2
    grid $f.to $f.from -sticky ew
    grid columnconfigure $f 1 -weight 1
    ttk::frame $f.b
    ttk::button $f.b.log -text "Changelog\u2026" -command {tktimeline::compareDone 1}
    ttk::button $f.b.show -text Show -default active -command {tktimeline::compareDone 0}
    ttk::button $f.b.cancel -text Cancel -command [list destroy $w]
    pack $f.b.cancel $f.b.show $f.b.log -side right -padx {4 0}
    grid $f.b - -sticky e -pady {10 0}
    bind $w <Return> {tktimeline::compareDone 0}
    focus $f.to
}

proc tktimeline::compareDone {log} {
    variable cl
    variable query
    set w .timeline.compare
    set to [string trim $cl(to)]
    set from [string trim $cl(from)]
    # Each name: the check-in it means here (as the search takes it).
    set rids {}
    foreach {name label} [list $to Newer $from Older] {
        set problem [fossil::valueProblem $label $name version]
        if {$problem eq ""} {
            if {[catch {lindex [sql "SELECT [checkin $name]"] 0 0} rid]} {
                set problem $rid
            } elseif {$rid eq ""} {
                set problem "$label: \"$name\" is no check-in of this repository."
            }
        }
        if {$problem ne ""} {
            ui::errorBox -parent $w -title "Compare releases" $problem
            return
        }
        lappend rids $rid
    }
    if {[lindex $rids 0] == [lindex $rids 1]} {
        ui::infoBox -parent $w -title "Compare releases" "$to and $from are the same check-in: nothing between them."
        return
    }
    destroy $w
    tktaalik::navigate
    # (Quoted if need be: a name is a term's value.)
    set q [lmap {key name} [list in $to -in $from] {
        string cat $key : [expr {[regexp {[\s",]} $name] ? "\"$name\"" : $name}]
    }]
    set query "[join $q] kind:ci"
    after cancel tktimeline::search
    search 1
    if {$log} { changelog }
}

# ---------------------------------------------------------- changelog

proc tktimeline::changelogData {query} {
    variable repo
    lassign [splitView $query] view rest
    set where [where $rest]
    set rows [sql "SELECT b.uuid, date(e.mtime), [fossil::outcol coalesce(e.euser,e.user)],
        [fossil::outcol coalesce(e.ecomment,e.comment)],
        EXISTS(SELECT 1 FROM plink p WHERE p.cid=e.objid AND NOT p.isprim)
        FROM event e JOIN blob b ON b.rid=e.objid
        WHERE e.type='ci' AND ($where) AND [viewCondition $view]
        ORDER BY e.mtime"]
    set links [fossil::hashLinks $repo [lmap row $rows { lindex $row 3 }]]
    set checkins {}
    set uuids {}
    foreach row $rows {
        lassign $row uuid date user comment merge
        set named {}
        foreach {- hash} [regexp -all -inline {\[([0-9a-fA-F]{4,40})\]} $comment] {
            set hash [string tolower $hash]
            if {[dict exists $links $hash] && [string match tkt:* [dict get $links $hash]]} {
                set t [string range [dict get $links $hash] 4 end]
                if {$t ni $named} { lappend named $t }
                if {$t ni $uuids} { lappend uuids $t }
            }
        }
        lappend checkins [dict create uuid $uuid date $date user $user comment $comment \
            merge $merge tickets $named]
    }
    set tickets {}
    if {[llength $uuids]} {
        ::tickets::useRepository $repo
        set cols [join [lmap f {title type status} { fossil::outcol "coalesce([::tickets::field $f],'')" }] ,]
        foreach row [::tickets::sql "SELECT tkt_uuid, $cols FROM ticket\
                WHERE tkt_uuid IN ([join [lmap u $uuids { fossil::sqlstr $u }] ,])"] {
            lassign $row uuid title type status
            dict set tickets $uuid [dict create title $title type $type status $status]
        }
    }
    list $checkins $tickets
}

# A text for a Markdown link's text: its brackets and backslashes escaped.
proc tktimeline::MarkdownText {text} {
    string map {\\ \\\\ [ \\[ ] \\]} $text
}

proc tktimeline::changelogText {data merges others base} {
    lassign $data checkins tickets
    set sections {bugs {} features {} tickets {} others {}}
    set seen {}
    foreach c $checkins {
        if {[dict get $c merge] && !$merges} continue
        if {![llength [dict get $c tickets]]} {
            if {!$others} continue
            set first [string trim [lindex [split [dict get $c comment] \n] 0]]
            set h [string range [dict get $c uuid] 0 9]
            dict lappend sections others " - [MarkdownText $first] (\[$h\]($base/info/$h))"
            continue
        }
        # Each ticket once, where its first check-in is.
        foreach t [dict get $c tickets] {
            if {$t in $seen || ![dict exists $tickets $t]} continue
            lappend seen $t
            set tk [dict get $tickets $t]
            set h [string range $t 0 9]
            set line " - \[[MarkdownText [dict get $tk title]]\]($base/tktview/$h)"
            if {![tktsearch::isClosed [dict get $tk status]]} { append line " (still [string tolower [dict get $tk status]])" }
            set type [string tolower [string trim [dict get $tk type]]]
            set section [expr {$type in {bug code_defect} ? "bugs"
                : $type in {rfe "feature request" feature} ? "features" : "tickets"}]
            dict lappend sections $section $line
        }
    }
    set text ""
    foreach {key heading} {bugs "Bug fixes" features "New features" tickets "Other tickets"
            others "Other changes"} {
        if {![llength [dict get $sections $key]]} continue
        append text "# $heading\n" [join [dict get $sections $key] \n] \n\n
    }
    string trimright $text \n
}

proc tktimeline::changelog {} {
    variable cl
    variable repo
    variable query
    if {$repo eq ""} return
    try {
        set data [ui::busy { changelogData $query }]
    } trap {TKFOSSIL QUERY} msg {
        showError $msg
        return
    }
    set cl(data) $data
    set cl(query) $query
    if {![info exists cl(merges)]} { set cl(merges) 0 }
    if {![info exists cl(others)]} { set cl(others) 1 }
    set cl(base) [fossil::remoteUrl $repo]
    set w .timeline.changelog
    set f [ui::dialog $w "Changelog" -escape [list destroy $w] -help timeline#releases-and-changelogs]
    lassign $data checkins tickets
    ttk::label $f.what -wraplength 640 -justify left -text "[llength $checkins] check-ins\
        ([string trim $query]), naming [dict size $tickets] tickets.  The text is yours to edit;\
        nothing is written to the repository."
    ttk::frame $f.opts
    ttk::checkbutton $f.opts.others -text "Check-ins that name no ticket" -variable tktimeline::cl(others) \
        -command tktimeline::changelogAgain
    ttk::checkbutton $f.opts.merges -text "Merges too" -variable tktimeline::cl(merges) \
        -command tktimeline::changelogAgain
    ttk::label $f.opts.lbase -text "Links to:"
    ttk::entry $f.opts.base -textvariable tktimeline::cl(base) -width 36
    bind $f.opts.base <Return> {tktimeline::changelogAgain; break}
    icons::tooltip $f.opts.base "The server the links go to (empty: links relative to the page)"
    pack $f.opts.others $f.opts.merges -side left -padx {0 10}
    pack $f.opts.base $f.opts.lbase -side right
    formattext::create $f.editor -formats {Markdown text/x-markdown} -fixed Markdown -repo $repo -height 20
    ttk::frame $f.b
    ttk::button $f.b.save -text "Save\u2026" -command tktimeline::changelogSave
    ttk::button $f.b.copy -text Copy -command {ui::copy [formattext::get .timeline.changelog.f.editor]}
    ttk::button $f.b.close -text Close -command [list destroy $w]
    pack $f.b.close $f.b.save $f.b.copy -side right -padx {4 0}
    pack $f.what -fill x -pady {0 4}
    pack $f.opts -fill x -pady {0 6}
    pack $f.b -side bottom -fill x -pady {8 0}
    pack $f.editor -fill both -expand 1
    set cl(edited) 0
    changelogFill
    focus [formattext::widget $f.editor]
}

# The text made again (the options changed): over the edits only if asked.
proc tktimeline::changelogAgain {} {
    set t [formattext::widget .timeline.changelog.f.editor]
    if {[$t edit modified] && ![ui::confirm -parent .timeline.changelog -title Changelog \
            "Make the text again?" "Your edits are lost."]} return
    changelogFill
}

proc tktimeline::changelogFill {} {
    variable cl
    set t [formattext::widget .timeline.changelog.f.editor]
    set text [changelogText $cl(data) $cl(merges) $cl(others) [string trimright [string trim $cl(base)] /]]
    $t delete 1.0 end
    $t insert end [expr {$text eq "" ? "" : "$text\n"}]
    $t edit reset
    $t edit modified 0
    $t mark set insert 1.0
}

proc tktimeline::changelogSave {} {
    set w .timeline.changelog
    set file [tk_getSaveFile -parent $w -title "Save the changelog" -initialfile changes.md \
        -defaultextension .md -filetypes {{Markdown .md} {"All files" *}}]
    if {$file eq ""} return
    try {
        set f [open $file w]
        fconfigure $f -encoding utf-8
        puts -nonewline $f [formattext::get $w.f.editor]
        close $f
    } on error msg {
        ui::errorBox -parent $w -title Changelog "Not saved." $msg
    }
}
