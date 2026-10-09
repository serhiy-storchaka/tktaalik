# The Tickets tab (lib/tktsearch.tcl): the details pane of a ticket, Back
# and Forward between the tickets shown, and a ticket's history.

# ---------------------------------------------------------------- details

# A panel: a header line (bold $who, then $what) above $body.
proc tktsearch::card {d who what body {mimetype ""}} {
    $d insert end $who cardhead "  $what\n" {cardhead cardheadmeta}
    set first [$d index "end - 1 char"]
    # Wiki, Markdown and HTML rendered; plain text as written.
    set html [renderHtml $mimetype $body]
    if {$html eq ""} {
        set html "<pre>[string map {& &amp; < &lt; > &gt;} [string trimright $body]]</pre>"
    }
    htmltext::insert $d $html -tags cardbody -margin [font measure TkDefaultFont 0] \
        -command tktsearch::followLink -external tktsearch::isExternal \
        -autolink [list {\[([0-9a-fA-F]{4,40})\]} tktsearch::hashLink]
    # The selection above the rendered text's tags.
    $d tag raise sel
    # Some room above the first and below the last line of the body.
    set last [$d index "end - 2 chars linestart"]
    $d tag add cardfirst $first "$first lineend"
    $d tag add cardlast $last "$last lineend"
    $d insert end \n cardgap
}

# A comment as HTML: Fossil renders wiki and Markdown (its test-*-render
# commands); "" for plain text, or if Fossil cannot.
proc tktsearch::renderHtml {mimetype text} {
    fossil::render $::tickets::repo $mimetype $text
}

# The links of [hash] in the texts: tickets open here, other artifacts
# (check-ins) in the browser; what is not in the repository is no link.
proc tktsearch::findHashes {texts} {
    variable hashes
    set hashes [fossil::hashLinks $::tickets::repo $texts]
}

proc tktsearch::hashLink {match hash} {
    variable hashes
    set hash [string tolower $hash]
    expr {[dict exists $hashes $hash] ? [dict get $hashes $hash] : ""}
}

# A link that followLink opens in the browser: a URL; a page of the server
# (info:, a path) if the repository has one.
proc tktsearch::isExternal {href} {
    variable remote
    if {[string match tkt:* $href] || [string match #* $href]} { return 0 }
    # A check-in, a wiki page...: in the application (goto::linkTarget).
    if {[goto::linkTarget $href] ne ""} { return 0 }
    if {[regexp {^[a-zA-Z][a-zA-Z0-9+.-]*://|^mailto:} $href]} { return 1 }
    expr {$remote ne ""}
}

# A link in a comment clicked: in the application where it can be shown
# here, else in the browser.
proc tktsearch::followLink {href} {
    if {![string match tkt:* $href] && [goto::openLink $href]} return
    switch -glob -- $href {
        tkt:*                 { goTicket [string range $href 4 end] }
        info:*                { openUrl info/[string range $href 5 end] }
        *://* - mailto:*      { browse $href }
        "#*"                  {}
        /*                    { openUrl [string range $href 1 end] }
        default               { openUrl $href }
    }
}

# ---------------------------------------------------------- back, forward

# Where we are (tktaalik::location): the search of the list shown, the
# ticket, the scroll of its comments, the details tab.
proc tktsearch::here {} {
    variable searched
    variable shownTicket
    set nb .tickets.main.details.nb
    # (The top line by index: fractions change as lines are measured.)
    list $searched $shownTicket [$nb.comments.text index @0,0] [$nb select]
}

# Follow a link to a ticket; Back returns here.
proc tktsearch::goTicket {uuid} {
    variable shownTicket
    if {$uuid eq $shownTicket} return
    tktaalik::navigate
    showTicket $uuid
}

# Back or Forward to a place of here.
proc tktsearch::goTo {place} {
    variable query
    lassign $place q uuid scroll tab
    set query $q
    if {$uuid ne ""} {
        showTicket $uuid
    } else {
        search
    }
    # After the details are shown (on the selection event), and the scroll
    # once the heights of all lines are known (embedded windows are sized
    # later: before that the top line can land elsewhere).
    after idle [list ::apply {{scroll tab} {
        set nb .tickets.main.details.nb
        if {$tab ne "" && [$nb tab $tab -state] eq "normal"} { $nb select $tab }
        if {$scroll ne ""} {
            set d $nb.comments.text
            update idletasks
            $d sync
            $d yview $scroll
        }
    }} $scroll $tab]
}

# Does the repository record the format of each comment?
proc tktsearch::commentMime {} {
    variable chngMime
    set repo $::tickets::repo
    if {![dict exists $chngMime $repo]} {
        set has 0
        catch {
            set has [lindex [::tickets::sql "SELECT count(*) FROM pragma_table_info('ticketchng')\
                WHERE name='mimetype'"] 0 0]
        }
        dict set chngMime $repo $has
    }
    expr {[dict get $chngMime $repo] ? "coalesce(mimetype,'')" : "''"}
}

# The tooltip of an icon cell: its value (tablecols -celltip).
proc tktsearch::cellTip {item key} {
    variable rows
    if {[info exists rows($item)] && [dict exists $rows($item) tip:$key]} {
        return [dict get $rows($item) tip:$key]
    }
    return ""
}

# The icon of a status (by its resolution), a priority or a severity
# (lib/icons.tcl), or "".
proc tktsearch::iconName {key value {resolution ""}} {
    set value [string tolower [string trim $value]]
    switch -- $key {
        state {
            # The statuses of the Tcl/Tk projects, and of Fossil's own
            # ticket setup (as in tickets::stateExpr).
            switch -- $value {
                open - verified  { return st-open }
                pending - review { return st-pending }
                deferred         { return st-postponed }
                deleted          { return st-deleted }
                fixed - tested   { return st-fixed }
                closed {
                    # Fossil writes resolutions with "_" (Wont_Fix).
                    switch -- [string map {_ " "} [string tolower [string trim $resolution]]] {
                        fixed - accepted - "drive by patch" { return st-fixed }
                        duplicate                  { return st-duplicate }
                        invalid - "not a bug" - "not applicable here" - "external bug" -
                        misconfiguration - withdrawn { return st-invalid }
                        "works for me" - "works as designed" - "by design" -
                        "unable to reproduce"      { return st-worksforme }
                        "wont fix" - rejected      { return st-rejected }
                        "out of date" - "overcome by events" { return st-outofdate }
                        remind - later - postponed { return st-postponed }
                        default                    { return st-closed }
                    }
                }
            }
        }
        priority {
            if {$value eq ""} { return "" }
            if {![regexp {^([0-9]+)} $value -> n]} {
                set n [expr {[dict exists {immediate 9 highest 8 high 7 medium 5 low 3 zero 1} $value]
                    ? [dict get {immediate 9 highest 8 high 7 medium 5 low 3 zero 1} $value] : 5}]
            }
            return [expr {$n >= 9 ? "pr-9" : $n == 8 ? "pr-8" : $n == 7 ? "pr-7"
                : $n == 6 ? "pr-6" : $n == 5 ? "pr-5" : "pr-low"}]
        }
        severity {
            switch -- $value {
                critical          { return sv-critical }
                severe            { return sv-severe }
                major - important { return sv-major }
                minor             { return sv-minor }
                cosmetic          { return sv-cosmetic }
            }
        }
    }
    return ""
}

# A character beyond the BMP (an emoji): Tcl 9 has it as one character,
# Tcl 8.6 as a surrogate pair.
proc tktsearch::emoji {code} {
    if {[package vsatisfies [info tclversion] 9]} { return [format %c $code] }
    set c [expr {$code - 0x10000}]
    format %c%c [expr {0xD800 + ($c >> 10)}] [expr {0xDC00 + ($c & 0x3FF)}]
}

# The sign before a status (by its resolution), a priority or a severity:
# emoji that Tk draws in colour (with Noto Color Emoji) or symbols that it
# draws in black; "" for other columns and unknown values.
proc tktsearch::sign {key value {resolution ""}} {
    set value [string tolower [string trim $value]]
    switch -- $key {
        state {
            # As the icons (iconName), so that they agree.
            set icon [iconName state $value $resolution]
            if {$icon eq ""} { return "" }
            set code [dict get {
                st-open 0x1F535 st-pending 0x1F536 st-deleted 0x2716 st-fixed 0x2714
                st-duplicate 0x1F501 st-invalid 0x1F645 st-worksforme 0x1F937
                st-rejected 0x1F6AB st-outofdate 0x231B st-postponed 0x1F4CC
                st-closed 0x1F3C1
            } $icon]
            return [expr {$code > 0xFFFF ? [emoji $code] : [format %c $code]}]
        }
        priority {
            # "9 Immediate", "8", ..., "1 Zero", or only the name.
            if {![regexp {^([0-9]+)} $value -> n]} {
                set n [dict get {immediate 9 highest 8 high 7 medium 5 low 3 zero 1} \
                    [expr {$value in {immediate highest high medium low zero} ? $value : "medium"}]]
                if {$value eq ""} { return "" }
            }
            return [expr {$n >= 9 ? "[emoji 0x1F6A8]" : $n == 8 ? "[emoji 0x1F534]" : $n == 7 ? "[emoji 0x1F53A]"
                : $n == 6 ? "[emoji 0x1F536]" : $n == 5 ? "[emoji 0x1F539]" : "[emoji 0x1F53D]"}]
        }
        severity {
            switch -- $value {
                critical          { return [emoji 0x1F6D1] }
                severe            { return \u26a0 }
                major - important { return \u2757 }
                minor             { return [emoji 0x1F539] }
                cosmetic          { return [emoji 0x1F3A8] }
            }
        }
    }
    return ""
}

# "Closed \u00b7 Fixed", leaving out empty and "None" parts.
# A value of the details as a link: a click searches the tickets with it
# (KEY:VALUE), Ctrl+click adds that to the search.
proc tktsearch::fieldLink {h key value text tags} {
    variable fieldLinks
    set tag fl-[incr fieldLinks]
    # (Fixed values in lower case, as one types them: type:bug.)
    if {$key in {type status resolution priority severity}} { set value [string tolower $value] }
    $h insert end $text [list {*}$tags fieldlink $tag]
    $h tag bind $tag <ButtonRelease-1> [list tktsearch::searchField $key $value %s]
    $h tag bind $tag <Enter> [list $h tag configure $tag -underline 1]
    $h tag bind $tag <Leave> [list $h tag configure $tag -underline 0]
}

# Search the tickets with KEY:VALUE (with Control: add it to the search).
proc tktsearch::searchField {key value state} {
    variable query
    if {$state & 4} {
        addTerm $key $value 0
        return
    }
    tktaalik::navigate
    set query [::tickets::termText 0 $key $value]
    search
}

proc tktsearch::joinValues {args} {
    join [lmap value $args {
        if {$value in {"" None}} continue
        set value
    }] " \u00b7 "
}

proc tktsearch::showDetails {uuid} {
    variable shownTicket
    set h .tickets.main.details.head
    set d .tickets.main.details.nb.comments.text
    set shownTicket $uuid
    foreach w [list $h $d] {
        $w configure -state normal
        $w delete 1.0 end
    }
    destroy $d.reply $h.edit $h.close $h.fix
    # (The links of the values shown before.)
    foreach tag [$h tag names] { if {[string match fl-* $tag]} { $h tag delete $tag } }
    htmltext::reset $d
    set remarks {}; set checkins {}; set attachments {}; set comment ""; set changes 0
    try {
        if {$uuid eq ""} return
        set fields {title type status resolution subsystem priority severity
            foundin submitter assignee closer tip_number}
        set row [lindex [::tickets::sql "SELECT\
            [join [lmap f $fields {fossil::outcol "coalesce([::tickets::field $f],'')"}] {, }],\
            datetime(tkt_ctime), datetime(tkt_mtime),\
            coalesce(datetime([::tickets::field closedate]),''),\
            [fossil::outcol "coalesce(comment,'')"], tkt_id,\
            coalesce([::tickets::field cmimetype],'')\
            FROM ticket WHERE tkt_uuid=[fossil::sqlstr $uuid]"] 0]
        lassign $row {*}$fields created updated closed comment id cmimetype
        # The repository's own fields, with their values.
        set custom {}
        if {[llength $::tickets::custom]} {
            set customRow [lindex [::tickets::sql "SELECT [join [lmap c $::tickets::custom {
                fossil::outcol "coalesce($c,'')"}] {, }] FROM ticket\
                WHERE tkt_uuid=[fossil::sqlstr $uuid]"] 0]
            foreach c $::tickets::custom v $customRow { lappend custom $c $v }
        }
        # (Old ticket schemas have no icomment: the remarks are in the
        # comment, appended.)
        if {[::tickets::canWrite icomment]} {
            set remarks [::tickets::sql "SELECT datetime(tkt_mtime),\
                [fossil::outcol "coalesce(nullif(username,''),login,'')"],\
                [fossil::outcol icomment], [commentMime] FROM ticketchng\
                WHERE tkt_id=$id AND icomment<>'' ORDER BY tkt_mtime"]
        }
        set changes [lindex [::tickets::sql "SELECT count(*) FROM ticketchng WHERE tkt_id=$id"] 0 0]
        # Check-ins whose comments mention any prefix of the ticket id.
        set u [fossil::sqlstr $uuid]
        set checkins [::tickets::sql "SELECT datetime(e.mtime),\
            [fossil::outcol "coalesce(e.user,'')"], bl.uuid,\
            [fossil::outcol "coalesce(e.comment,'')"]\
            FROM backlink b JOIN event e ON e.objid=b.srcid\
            JOIN blob bl ON bl.rid=b.srcid\
            WHERE b.srctype=0 AND b.target BETWEEN substr($u,1,4) AND $u\
            AND $u GLOB b.target||'*' GROUP BY b.srcid ORDER BY e.mtime"]
        # The latest version of each attachment, not deleted ones.
        set attachments [::tickets::sql "SELECT a.src, [fossil::outcol a.filename],\
            [fossil::outcol "coalesce(a.user,'')"], datetime(a.mtime),\
            [fossil::outcol "coalesce(a.comment,'')"],\
            coalesce((SELECT size FROM blob WHERE uuid=a.src),-1)\
            FROM attachment a WHERE a.target=$u AND a.isLatest AND a.src<>''\
            ORDER BY a.mtime"]
    } trap {FOSSIL DB} msg {
        $h insert end "Database error: $msg"
        set uuid ""
    } finally {
        fillCheckins $checkins
        fillAttachments $attachments
        detailTabs [expr {[string trim $comment] ne ""}] [llength $remarks] \
            [llength $checkins] [llength $attachments] $changes
        clearHistory
        if {$uuid eq ""} {
            foreach w [list $h $d] { $w configure -state disabled }
            fitHead
        }
    }
    if {$uuid eq ""} return

    # The header, above the tabs: the title, the fields, then who and when.
    $h insert end $title title
    # Edit and Close: buttons with a frame, after the title.
    if {[canWrite]} {
        $h insert end "   " title
        ttk::button $h.edit -text Edit\u2026 -style Small.TButton \
            -command [list tktsearch::editTicket $uuid]
        $h window create end -window $h.edit -align center
        if {[::tickets::canWrite status] && ![isClosed $status]} {
            ttk::button $h.close -text Close\u2026 -style Small.TButton \
                -command [list tktsearch::closeTicket $uuid]
            $h window create end -window $h.close -align center -padx 4
        }
    }
    # (Start fix does not write the ticket: for anyone.)
    if {![isClosed $status]} {
        ttk::button $h.fix -text "Start fix\u2026" -style Small.TButton \
            -command [list tktsearch::startFix $uuid]
        $h window create end -window $h.fix -align center
    }
    $h insert end \n title
    # Status, Priority and Severity with their icon.  Each value is a
    # link: the tickets with it (fieldLink).
    foreach {label value icon key raw} [list TIP $tip_number "" tip $tip_number \
            Type $type "" type $type \
            Status [joinValues $status $resolution] [iconName state $status $resolution] status $status \
            Subsystem $subsystem "" subsystem $subsystem \
            Priority [cellText priority $priority] [iconName priority $priority] priority $priority \
            Severity [cellText severity $severity] [iconName severity $severity] severity $severity \
            "Found in" [cellText version $foundin] "" version $foundin \
            Assignee [cellText assignee $assignee] "" assignee $assignee \
            {*}[concat {*}[lmap {c v} $custom { list [::tickets::fieldLabel $c] [cellText $c $v] "" $c $v }]]] {
        if {$value eq ""} continue
        $h insert end "$label: " {label fields}
        if {$icon ne ""} {
            $h image create end -image [icons::get $icon row] -align center -padx 2
        }
        if {$key eq "status"} {
            # "Closed \u00b7 Fixed": the status and the resolution, each.
            fieldLink $h status $status [joinValues $status] fields
            if {[joinValues $resolution] ne ""} {
                $h insert end " \u00b7 " fields
                fieldLink $h resolution $resolution $resolution fields
            }
        } elseif {$key eq "version"} {
            # Its version number: "obsolete: 8.4.19" searches version:8.4.19.
            fieldLink $h version [::tickets::versionNumber $raw] $value fields
        } else {
            fieldLink $h $key $raw $value fields
        }
        $h insert end "    " fields
    }
    $h insert end \n fields
    # "by ..." only where the tickets record who.
    $h insert end "[string range $uuid 0 9]  \u00b7  opened $created" {meta when}
    if {$submitter ne ""} {
        $h insert end " by " {meta when}
        fieldLink $h author $submitter $submitter {meta when}
    }
    $h insert end ", updated $updated" {meta when}
    if {$closed ne ""} {
        $h insert end ", closed $closed" {meta when}
        if {[cellText closer $closer] ne ""} {
            $h insert end " by " {meta when}
            fieldLink $h closer $closer $closer {meta when}
        }
    }
    $h configure -state disabled
    fitHead

    # The Comments tab: the description and each comment in panels, then
    # the box for a new one.
    findHashes [list $comment {*}[lmap remark $remarks {lindex $remark 2}]]
    if {[string trim $comment] ne ""} {
        card $d [expr {$submitter ne "" ? $submitter : "Description"}] "opened $created" \
            $comment $cmimetype
    }
    foreach remark $remarks {
        lassign $remark time user text mimetype
        card $d $user "commented $time" $text $mimetype
    }
    if {[canComment]} {
        $d window create end -window [replyBox $d $uuid] \
            -padx [font measure TkDefaultFont 0]
    }
    $d configure -state disabled
    $d yview moveto 0
}

# The tab labels with their counts; empty tabs disabled.  The tab shown
# stays, unless it is now empty.
proc tktsearch::detailTabs {description comments checkins attachments {changes 0}} {
    set nb .tickets.main.details.nb
    # (Disabling the tab shown shows the next one: Comments instead.)
    set shown [$nb select]
    $nb tab $nb.comments -text "Comments ($comments)"
    foreach {tab label n} [list checkins Check-ins $checkins attachments Attachments $attachments \
            history History $changes] {
        # (Attachments also without any: its Attach button.)
        $nb tab $nb.$tab -text "$label ($n)" -state [expr {$n || $tab eq "attachments" ? "normal" : "disabled"}]
    }
    if {[$nb tab $shown -state] eq "disabled"} { $nb select $nb.comments }
}

# The header as high as its lines (they wrap with the width).
proc tktsearch::fitHead {} {
    set h .tickets.main.details.head
    # The height is in lines of the text font; the title is larger and
    # the icons make lines higher, so count pixels.
    set pixels [$h count -update -ypixels 1.0 end]
    set line [font metrics [$h cget -font] -linespace]
    set n [expr {max(1, ($pixels + $line - 1) / $line)}]
    if {[$h cget -height] != $n} { $h configure -height $n }
}

# ---------------------------------------------------------------- history

# The History tab: every change of the ticket, newest first, with the
# fields it set ("fossil ticket history"), read when the tab is shown.
# Comments are in the Comments tab: here only their first words.
proc tktsearch::buildHistory {f} {
    ttk::frame $f
    set d $f.text
    text $d -wrap word -height 8 -padx 8 -pady 6 -font TkTextFont -state disabled \
        -yscrollcommand [list $f.y set]
    ttk::scrollbar $f.y -command [list $d yview]
    $d tag configure head -font TkHeadingFont -spacing1 6 -spacing3 2
    $d tag configure meta -font TkDefaultFont -foreground gray35
    $d tag configure field -foreground gray35
    $d tag configure value -lmargin1 12 -lmargin2 24
    grid $d $f.y -sticky news
    grid columnconfigure $f 0 -weight 1
    grid rowconfigure $f 0 -weight 1
    return $f
}

proc tktsearch::clearHistory {} {
    variable historyOf ""
    set d .tickets.main.details.nb.history.text
    $d configure -state normal
    $d delete 1.0 end
    $d configure -state disabled
    loadHistory
}

proc tktsearch::loadHistory {} {
    variable shownTicket
    variable historyOf
    set nb .tickets.main.details.nb
    if {[$nb select] ne "$nb.history" || $shownTicket eq ""
            || ([info exists historyOf] && $historyOf eq $shownTicket)} return
    set historyOf $shownTicket
    set d $nb.history.text
    $d configure -state normal
    $d delete 1.0 end
    lassign [fossil::run ticket history $shownTicket -R $::tickets::repo] code out
    if {$code} {
        $d insert end "fossil ticket history failed: [string trim $out]"
    } else {
        foreach change [parseHistory $out] {
            lassign $change user date fields
            $d insert end $user head "  $date\n" meta
            foreach {action field value} $fields {
                set value [string trim $value]
                if {[string first \n $value] >= 0 || [string length $value] > 160} {
                    set value [string range [regsub -all {\s+} $value " "] 0 159]\u2026
                }
                $d insert end "[string tolower $action] $field: " {field value} "$value\n" value
            }
        }
    }
    $d configure -state disabled
    $d yview moveto 0
}

# The output of "fossil ticket history": {user date {action field value
# ...}} for each change.
proc tktsearch::parseHistory {out} {
    set changes {}
    set fields {}
    set user ""
    foreach line [split $out \n] {
        if {[regexp {^Ticket Change by (.*) on (.*):$} $line -> u date]} {
            if {$user ne ""} { lappend changes [list $user $when $fields] }
            set user $u
            set when $date
            set fields {}
        } elseif {[regexp {^  (\S.*?) (\S+): ?(.*)$} $line -> action field value]} {
            lappend fields $action $field $value
        } elseif {[string match "    *" $line] && [llength $fields]} {
            lset fields end [string trimleft "[lindex $fields end]\n[string range $line 4 end]" \n]
        }
    }
    if {$user ne ""} { lappend changes [list $user $when $fields] }
    return $changes
}
