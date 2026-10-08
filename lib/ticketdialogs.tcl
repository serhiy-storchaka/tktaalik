# The Tickets tab (lib/tktsearch.tcl): writing -- the comment dialog, new
# tickets and edits, with the fields of lib/ticketwrite.tcl.

# ---------------------------------------------------------------- writing

# Comments, field changes and new tickets go into the local repository
# (lib/ticketwrite.tcl); they are never pushed from here.

# Who the changes are recorded as: the repository's default user.
proc tktsearch::canWrite {} {
    expr {$::tickets::me ni {"" anonymous nobody}}
}

proc tktsearch::needUser {} {
    if {[canWrite]} { return 1 }
    tk_messageBox -icon info -title "No user" -message "Changes need a user." \
        -detail "This repository has no default user to record them as (fossil user default)."
    return 0
}

# Ask before writing: a posted change cannot be edited or taken back.
proc tktsearch::confirm {title what details} {
    ui::confirm -title $title $what "$details\n\nIt is written to [file tail $::tickets::repo]\
            as $::tickets::me and cannot be changed afterwards.  It is not pushed."
}

# Write and show the result; returns the ticket's id or "".
proc tktsearch::write {mode uuid fields} {
    set busy [ui::busyHold]
    try {
        set id [::tickets::writeTicket $mode $uuid $fields]
    } trap {TICKETS WRITE} msg {
        tk_messageBox -icon error -title "Not written" -message "The change was not written." \
            -detail $msg
        return ""
    } trap {FOSSIL DB} msg {
        tk_messageBox -icon error -title "Not written" -message "Database error." -detail $msg
        return ""
    } finally {
        ui::busyRelease $busy
    }
    return $id
}

# Search again and show $uuid, also if the search does not find it.
proc tktsearch::showTicket {uuid} {
    variable query
    search
    set t .tickets.main.list.t
    if {![$t exists $uuid]} {
        set query id:[string range $uuid 0 9]
        search
    }
    if {[$t exists $uuid]} {
        $t selection set $uuid
        $t focus $uuid
        $t see $uuid
    }
}

proc tktsearch::summary {fields} {
    join [lmap {field value} $fields {
        if {$field in {icomment comment +comment}} {
            set value [string range $value 0 400][expr {[string length $value] > 400 ? "\u2026" : ""}]
            string cat "$field:\n$value"
        } else {
            string cat "$field: $value"
        }
    }] \n
}

# The end of the details: the button that opens the comment dialog.
proc tktsearch::replyBox {d uuid} {
    variable drafts
    set f $d.reply
    ttk::frame $f -padding {0 6 0 4}
    ttk::button $f.add -text "Add a comment\u2026" -command [list tktsearch::commentDialog $uuid]
    if {[canWrite]} {
        set note "As $::tickets::me"
        if {[dict exists $drafts $uuid]} { append note "; a draft is waiting" }
    } else {
        set note "Comments need a user: this repository has no default user"
        $f.add state disabled
    }
    ttk::label $f.note -text $note -foreground gray35
    pack $f.add -side left
    pack $f.note -side left -padx {8 0}
    fitReply $d
    return $f
}

# The comment dialog: the comment written with its preview, in the format
# chosen (old ticket setups append comments to the description: wiki
# markup there).  Cancelled, it stays a draft of the ticket.
proc tktsearch::commentDialog {uuid} {
    variable drafts
    variable formats
    if {$uuid eq "" || ![needUser]} return
    set w .tickets.comment
    if {[winfo exists $w]} {
        # (One at a time: the one open first, kept.)
        closeComment
    }
    set title [lindex [::tickets::sql "SELECT [fossil::outcol "coalesce(title,'')"] FROM ticket\
        WHERE tkt_uuid=[fossil::sqlstr $uuid]"] 0 0]
    toplevel $w
    wm title $w "Comment on [string range $uuid 0 9]"
    wm transient $w .
    ttk::frame $w.f -padding 10
    ttk::label $w.f.title -text "[string range $uuid 0 9]  $title" -font TkHeadingFont \
        -wraplength 600 -justify left
    set text [expr {[dict exists $drafts $uuid] ? [dict get $drafts $uuid] : ""}]
    set opts [list -formats $formats -variable tktsearch::format -repo $::tickets::repo -text $text]
    if {![::tickets::canWrite icomment]} { lappend opts -fixed "Fossil wiki" }
    formattext::create $w.f.editor {*}$opts
    ttk::frame $w.f.b
    ttk::label $w.f.b.who -text "As $::tickets::me; nothing is pushed." -foreground gray35
    ttk::button $w.f.b.post -text Post -default active -command [list tktsearch::postComment $uuid]
    ttk::button $w.f.b.cancel -text Cancel -command tktsearch::closeComment
    pack $w.f.b.who -side left
    pack $w.f.b.cancel $w.f.b.post -side right -padx {4 0}
    pack $w.f.title -fill x -pady {0 6}
    pack $w.f.b -side bottom -fill x -pady {8 0}
    pack $w.f.editor -fill both -expand 1
    pack $w.f -fill both -expand 1
    variable commentTicket $uuid
    bind [formattext::widget $w.f.editor] <Control-Return> "[list tktsearch::postComment $uuid]; break"
    bind $w <Escape> tktsearch::closeComment
    wm protocol $w WM_DELETE_WINDOW tktsearch::closeComment
    focus [formattext::widget $w.f.editor]
}

# Close the comment dialog; what is written stays a draft.
proc tktsearch::closeComment {} {
    variable drafts
    variable commentTicket
    set w .tickets.comment
    if {![winfo exists $w]} return
    set text [string trimright [formattext::get $w.f.editor]]
    if {$text eq ""} {
        dict unset drafts $commentTicket
    } else {
        dict set drafts $commentTicket $text
    }
    destroy $w
    refreshReply
}

# The note by the comment button: a draft or not.
proc tktsearch::refreshReply {} {
    variable shownTicket
    variable drafts
    set f .tickets.main.details.nb.comments.text.reply
    if {![winfo exists $f] || ![canWrite]} return
    set note "As $::tickets::me"
    if {[dict exists $drafts $shownTicket]} { append note "; a draft is waiting" }
    $f.note configure -text $note
}


# The fields of a comment.  Old ticket schemas have no icomment: there the
# comment is appended to the "comment" field ("+comment"), after a line
# with who and when, as Fossil's ticket pages did then (in wiki markup).
proc tktsearch::commentFields {text} {
    variable formats
    variable format
    set fields {}
    if {[::tickets::canWrite icomment]} {
        set comment [list mimetype [dict get $formats $format] icomment $text]
    } else {
        set when [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S" -gmt 1]
        set comment [list +comment "\n\n<hr><i>$::tickets::me added on $when:</i><br>\n$text"]
    }
    foreach {field value} [list login $::tickets::me username $::tickets::me {*}$comment] {
        if {[::tickets::canWrite $field]} { dict set fields $field $value }
    }
    return $fields
}

# Can comments be added: icomment, or appended to comment.
proc tktsearch::canComment {} {
    expr {[::tickets::canWrite icomment] || [::tickets::canWrite comment]}
}

proc tktsearch::postComment {uuid} {
    variable drafts
    variable format
    set w .tickets.comment
    if {![winfo exists $w]} return
    set text [string trim [formattext::get $w.f.editor]]
    if {$text eq "" || ![needUser]} return
    set fields [commentFields $text]
    set as [expr {[::tickets::canWrite icomment] ? $format : "Fossil wiki"}]
    if {![confirm "Post comment" "Post this comment ($as) to [string range $uuid 0 9]?" $text]} return
    if {[write set $uuid $fields] eq ""} return
    dict unset drafts $uuid
    destroy $w
    showTicket $uuid
}

# A form row: a combobox with the choices if there are any, else an entry;
# for the status, resolution, priority and severity a menubutton with icons.
proc tktsearch::formRow {w row field label value choices} {
    ttk::label $w.l$field -text $label
    if {$field in {status resolution priority severity} && [dict exists $choices $field]} {
        choiceButton $w.e$field $field $value [dict get $choices $field]
        grid $w.l$field -row $row -column 0 -sticky w -padx {0 8} -pady 2
        grid $w.e$field -row $row -column 1 -sticky w -pady 2
        if {$field eq "resolution" && [winfo exists $w.estatus]} {
            # The status icon shows the resolution of a closed ticket.
            choiceShow $w.estatus status
        }
        return
    }
    if {[dict exists $choices $field]} {
        ttk::combobox $w.e$field -values [dict get $choices $field] -width 40
        $w.e$field set $value
    } else {
        ttk::entry $w.e$field -width 60
        $w.e$field insert 0 $value
    }
    grid $w.l$field -row $row -column 0 -sticky w -padx {0 8} -pady 2
    grid $w.e$field -row $row -column 1 -sticky ew -pady 2
}

# A menubutton choosing one of $values, each with its icon.  A value not
# among them (an old one) is kept as a choice; so is no value.
proc tktsearch::choiceButton {mb field value values} {
    variable formValue
    set formValue($mb) $value
    # As high as the comboboxes around it.
    ttk::style configure Choice.TMenubutton -padding {4 0}
    ttk::menubutton $mb -menu $mb.m -compound left -width 24 -style Choice.TMenubutton
    menu $mb.m -tearoff 0
    if {$value ni $values} { set values [linsert $values 0 $value] }
    if {$field eq "severity"} {
        # Least severe first, like the priorities (the repository lists
        # its default first).
        set values [lsort -command tktsearch::severityOrder $values]
    }
    foreach v $values {
        set icon [choiceIcon $field $v]
        $mb.m add radiobutton -label [expr {$v eq "" ? "(none)" : $v}] \
            -variable ::tktsearch::formValue($mb) -value $v \
            -image [expr {$icon eq "" ? [blankIcon] : [icons::get $icon row]}] -compound left \
            -command [list tktsearch::choiceShow $mb $field]
    }
    bind $mb <Destroy> [list unset -nocomplain ::tktsearch::formValue($mb)]
    choiceShow $mb $field
}

# The icon of a choice.  A resolution has the icon of a ticket closed with
# it (None has none); a status that of the resolution in the form, if it is
# closed.
proc tktsearch::choiceIcon {field value {resolution ""}} {
    switch -- $field {
        status     { iconName state $value $resolution }
        resolution {
            # No icon for no resolution.
            if {[string tolower [string trim $value]] in {"" none}} { return "" }
            iconName state closed $value
        }
        default    { iconName $field $value }
    }
}

# Severities by rank (as in lib/ticketquery.tcl), no value first.
proc tktsearch::severityOrder {a b} {
    set rank {critical 5 severe 4 major 3 important 3 minor 2 cosmetic 1}
    set ra [expr {$a eq "" ? -1 : [dict exists $rank [string tolower $a]] ? [dict get $rank [string tolower $a]] : 0}]
    set rb [expr {$b eq "" ? -1 : [dict exists $rank [string tolower $b]] ? [dict get $rank [string tolower $b]] : 0}]
    expr {$ra - $rb}
}

# Show the chosen value on the button, with its icon.
proc tktsearch::choiceShow {mb field} {
    variable formValue
    set value $formValue($mb)
    set w [winfo parent $mb]
    set resolution ""
    if {$field eq "status" && [winfo exists $w.eresolution]} {
        set resolution [fieldValue $w.eresolution]
    }
    set icon [choiceIcon $field $value $resolution]
    $mb configure -text [expr {$value eq "" ? "(none)" : $value}] \
        -image [expr {$icon eq "" ? [blankIcon] : [icons::get $icon row]}]
    if {$field eq "resolution" && [winfo exists $w.estatus]} {
        choiceShow $w.estatus status
    }
}

# An empty image, so that the menu entries without an icon line up.
proc tktsearch::blankIcon {} {
    set size [icons::rowSize]
    set name ::tktsearch::blank$size
    if {$name ni [image names]} { image create photo $name -width $size -height $size }
    return $name
}

# The value of a form field: an entry, a combobox or a choice button.
proc tktsearch::fieldValue {w} {
    variable formValue
    if {[info exists formValue($w)]} { return $formValue($w) }
    $w get
}

# A text of the form (the description, a comment): written in a format,
# with its preview.
proc tktsearch::formText {w row label {text ""}} {
    variable formats
    ttk::label $w.ltext -text $label
    formattext::create $w.editor -formats $formats -variable tktsearch::format \
        -repo $::tickets::repo -text $text -height 8
    grid $w.ltext -row $row -column 0 -sticky nw -padx {0 8} -pady {6 2}
    grid $w.editor -row $row -column 1 -sticky news -pady 2
    grid rowconfigure $w $row -weight 1
}

proc tktsearch::dialog {w title} {
    set f [ui::dialog $w $title -escape [list destroy $w]]
    grid columnconfigure $f 1 -weight 1
    return $f
}

# The fields of the edit and new-ticket dialogs, in this order.
namespace eval tktsearch {
    variable editFields {
        title Title  type Type  status Status  resolution Resolution
        subsystem Subsystem  priority Priority  severity Severity
        foundin {Found in}  assignee Assignee  tip_number TIP
    }
}

proc tktsearch::editTicket {uuid} {
    variable editFields
    if {$uuid eq "" || ![needUser]} return
    # (And the repository's own fields, after these.)
    set labels $editFields
    foreach c $::tickets::custom { dict set labels $c [::tickets::fieldLabel $c] }
    set names [dict keys $labels]
    set values [lindex [::tickets::sql "SELECT [join [lmap f $names {
        fossil::outcol "coalesce([::tickets::field $f],'')"}] {, }]\
        FROM ticket WHERE tkt_uuid=[fossil::sqlstr $uuid]"] 0]
    set f [dialog .tickets.edit "Edit ticket [string range $uuid 0 9]"]
    set choices [::tickets::choices]
    set row 0
    set old {}
    foreach field $names value $values {
        if {![::tickets::canWrite $field]} continue
        dict set old $field $value
        formRow $f [incr row] $field [dict get $labels $field] $value $choices
    }
    formText $f [incr row] "Comment\n(optional)"
    incr row 2
    ttk::frame $f.buttons
    ttk::button $f.buttons.save -text Save -default active \
        -command [list tktsearch::saveEdit $uuid $old]
    ttk::button $f.buttons.cancel -text Cancel -command {destroy .tickets.edit}
    pack $f.buttons.cancel $f.buttons.save -side right -padx {4 0}
    grid $f.buttons -row $row -column 0 -columnspan 2 -sticky e -pady {8 0}
    focus $f.etitle
}

proc tktsearch::saveEdit {uuid old} {
    variable format
    set f .tickets.edit.f
    set fields {}
    set changes {}
    dict for {field value} $old {
        set new [string trim [fieldValue $f.e$field]]
        if {$new eq $value} continue
        if {$new eq ""} {
            tk_messageBox -icon info -parent .tickets.edit -title "Edit ticket" \
                -message "Fields cannot be cleared from here." \
                -detail "Fossil's command line cannot set \"$field\" to an empty value."
            return
        }
        dict set fields $field $new
        lappend changes "$field: $value \u2192 $new"
    }
    if {[dict exists $fields status]} {
        set fields [dict merge $fields [closerFields [dict get $old status] [dict get $fields status]]]
    }
    set text [string trim [formattext::get $f.editor]]
    if {$text ne ""} {
        set fields [dict merge $fields [commentFields $text]]
        lappend changes "comment ($format):\n[string range $text 0 400]"
    }
    if {![llength $changes]} {
        tk_messageBox -icon info -parent .tickets.edit -title "Edit ticket" -message "Nothing changed."
        return
    }
    if {![confirm "Edit ticket" "Change ticket [string range $uuid 0 9]?" [join $changes \n]]} return
    if {[write set $uuid $fields] eq ""} return
    destroy .tickets.edit
    showTicket $uuid
}

# What a change of the status from OLD to NEW also sets, as the web page:
# closing records who and when, reopening clears who.  (Fossil's own Fixed
# and Tested are closed too, as in tickets::stateExpr.)
proc tktsearch::closerFields {old new} {
    set closed {closed deleted fixed tested}
    set closing [expr {[string tolower [string trim $new]] in $closed}]
    set wasClosed [expr {[string tolower [string trim $old]] in $closed}]
    set fields {}
    if {$closing && !$wasClosed} {
        if {[::tickets::canWrite closer]} { dict set fields closer $::tickets::me }
        if {[::tickets::canWrite closedate]} {
            dict set fields closedate [lindex [::tickets::sql "SELECT julianday('now')"] 0 0]
        }
    } elseif {$wasClosed && !$closing && [::tickets::canWrite closer]} {
        dict set fields closer nobody
    }
    return $fields
}

# Whether the ticket's status is a closed one (as closerFields).
proc tktsearch::isClosed {status} {
    expr {[string tolower [string trim $status]] in {closed deleted fixed tested}}
}

# Ticket > Close: the status Closed with a resolution (Fixed for a bug,
# else Accepted) and a closing comment, in one change.
proc tktsearch::closeTicket {uuid} {
    if {$uuid eq "" || ![needUser]} return
    if {![::tickets::canWrite status]} {
        tk_messageBox -icon info -title "Close ticket" -message "Tickets here have no status to close."
        return
    }
    set row [lindex [::tickets::sql "SELECT [join [lmap f {title type status} {
        expr {[::tickets::canWrite $f] ? [fossil::outcol "coalesce([::tickets::field $f],'')"] : "''"}
    }] {, }] FROM ticket WHERE tkt_uuid=[fossil::sqlstr $uuid]"] 0]
    lassign $row title type status
    if {[isClosed $status]} {
        tk_messageBox -icon info -title "Close ticket" -message "The ticket is already $status."
        return
    }
    # The values of the repository's ticket setup (the web pages' choices).
    set choices [::tickets::choices]
    set closedStatus Closed
    if {[dict exists $choices status]} {
        set i [lsearch -exact -nocase [dict get $choices status] closed]
        if {$i >= 0} { set closedStatus [lindex [dict get $choices status] $i] }
    }
    if {![dict exists $choices resolution]} {
        dict set choices resolution {Fixed Accepted Rejected {Works For Me} Duplicate {Wont Fix}}
    }
    dict set choices resolution [lsearch -all -inline -not -exact -nocase \
        [dict get $choices resolution] none]
    set resolution [expr {[string equal -nocase [string trim $type] bug] ? "Fixed" : "Accepted"}]
    set i [lsearch -exact -nocase [dict get $choices resolution] $resolution]
    set resolution [lindex [dict get $choices resolution] [expr {max($i, 0)}]]

    set w .tickets.close
    set f [dialog $w "Close ticket [string range $uuid 0 9]"]
    ttk::label $f.title -text "[string range $uuid 0 9]  $title" -font TkHeadingFont \
        -wraplength 600 -justify left
    grid $f.title -row 0 -column 0 -columnspan 2 -sticky w -pady {0 6}
    if {[::tickets::canWrite resolution]} {
        formRow $f 1 resolution Resolution $resolution $choices
    }
    formText $f 2 "Comment\n(optional)"
    ttk::frame $f.buttons
    ttk::label $f.buttons.who -text "As $::tickets::me; nothing is pushed." -foreground gray35
    ttk::button $f.buttons.close -text Close -default active \
        -command [list tktsearch::closeDone $uuid $status $closedStatus]
    ttk::button $f.buttons.cancel -text Cancel -command [list destroy $w]
    pack $f.buttons.who -side left
    pack $f.buttons.cancel $f.buttons.close -side right -padx {4 0}
    grid $f.buttons -row 4 -column 0 -columnspan 2 -sticky ew -pady {8 0}
    bind [formattext::widget $f.editor] <Control-Return> \
        "[list tktsearch::closeDone $uuid $status $closedStatus]; break"
    focus [formattext::widget $f.editor]
}

proc tktsearch::closeDone {uuid old closedStatus} {
    variable format
    set f .tickets.close.f
    if {![winfo exists $f]} return
    set fields [list status $closedStatus]
    set changes [list "status: $old \u2192 $closedStatus"]
    set as ""
    if {[winfo exists $f.eresolution]} {
        set resolution [string trim [fieldValue $f.eresolution]]
        if {$resolution ne ""} {
            dict set fields resolution $resolution
            lappend changes "resolution: $resolution"
            set as " as $resolution"
        }
    }
    set fields [dict merge $fields [closerFields $old $closedStatus]]
    set text [string trim [formattext::get $f.editor]]
    if {$text ne ""} {
        set fields [dict merge $fields [commentFields $text]]
        lappend changes "comment ($format):\n[string range $text 0 400]"
    }
    if {![confirm "Close ticket" "Close ticket [string range $uuid 0 9]$as?" [join $changes \n]]} return
    if {[write set $uuid $fields] eq ""} return
    destroy .tickets.close
    showTicket $uuid
}

# Ticket > Start fix: a branch for the fix of the ticket, as the Tcl/Tk
# workflow has it (TIP 710: a branch per fix, from the tip of trunk).  The
# fix is made in this checkout, updated to the tip of the base branch
# (after Fossil's dry run and a question), or in a new checkout of it
# beside this one (Fossil's way: a checkout per line of work); then the
# Commit tab gets the new branch's name and the comment "Fix [id]: title".
# The fix itself and the commit are yours.

namespace eval tktsearch {
    variable fixBranch ""
    variable fixBase ""
    variable fixComment ""
    variable fixWhere here      ;# here (this checkout) or new
    variable fixDir ""          ;# the new checkout
    variable fixSuggested ""    ;# the branch name the folder is named after
}

# The folder of the new checkout follows the branch name while it is the
# one suggested.
proc tktsearch::fixDirFollows {args} {
    variable fixDir
    variable fixBranch
    variable fixSuggested
    if {[file tail $fixDir] ne $fixSuggested} return
    set fixDir [file join [file dirname $fixDir] $fixBranch]
    set fixSuggested $fixBranch
}

# A branch name from a title: its words, without the little ones, joined
# by "-" (tests-fail-high-display-scale).
proc tktsearch::branchName {title} {
    set words [regexp -all -inline {[a-z0-9]+} [string tolower $title]]
    set words [lmap w $words {
        if {$w in {a an the of at in on to for with and or is are be by from not when does do}} continue
        set w
    }]
    set name [join [lrange $words 0 4] -]
    string range $name 0 39
}

# The branches a fix can start from: main (or trunk), then the merge
# targets of the Branches tab.
proc tktsearch::fixBases {} {
    set repo $::tickets::repo
    set bases {}
    foreach b [concat {main trunk} [expr {[info exists ::tkbranches::targets] ? $::tkbranches::targets : {}}]] {
        if {$b in $bases} continue
        if {[llength [fossil::sql $repo "SELECT 1 FROM tag WHERE tagname=[fossil::sqlstr sym-$b]"]]} {
            lappend bases $b
        }
    }
    # (main and trunk are the same branch where both exist: main.)
    if {"main" in $bases} { set bases [lsearch -all -inline -not -exact $bases trunk] }
    return $bases
}

proc tktsearch::startFix {uuid} {
    variable fixBranch
    variable fixBase
    variable fixComment
    variable fixWhere
    variable fixDir
    if {$uuid eq ""} return
    set root $::tktaalik::root
    set title [lindex [::tickets::sql "SELECT [fossil::outcol "coalesce(title,'')"] FROM ticket\
        WHERE tkt_uuid=[fossil::sqlstr $uuid]"] 0 0]
    set bases [fixBases]
    set fixBranch [branchName $title]
    set fixBase [lindex $bases 0]
    set fixComment "Fix \[[string range $uuid 0 9]\]: $title"
    # A new checkout beside this one (or the repository): by default when
    # there is none, or when this one has changes.
    set changes ""
    if {$root ne ""} {
        lassign [fossil::run -dir $root changes] code out
        if {!$code} { set changes [string trim $out] }
    }
    set fixWhere [expr {$root eq "" || $changes ne "" ? "new" : "here"}]
    set fixDir [file join [file dirname [expr {$root ne "" ? $root : $::tickets::repo}]] $fixBranch]
    set f [dialog .tickets.startfix "Start a fix for [string range $uuid 0 9]"]
    ttk::label $f.title -text "[string range $uuid 0 9]  $title" -font TkHeadingFont \
        -wraplength 600 -justify left
    grid $f.title - -sticky w -pady {0 8}
    ttk::label $f.lbranch -text "New branch"
    ttk::entry $f.branch -textvariable tktsearch::fixBranch -width 40
    ttk::label $f.lbase -text "From the tip of"
    ttk::combobox $f.base -textvariable tktsearch::fixBase -values $bases -state readonly -width 38
    ttk::label $f.lcomment -text "Comment"
    ttk::entry $f.comment -textvariable tktsearch::fixComment -width 60
    foreach {l e} {lbranch branch lbase base lcomment comment} {
        grid $f.$l $f.$e -sticky ew -pady 2
        grid $f.$l -sticky w -padx {0 8}
    }
    ttk::label $f.lwhere -text "Where"
    ttk::frame $f.where
    ttk::radiobutton $f.where.here -variable tktsearch::fixWhere -value here \
        -text [expr {$root eq "" ? "This checkout (there is none: a repository is shown)"
            : "This checkout, updated[expr {$changes ne "" ? " (it has changes: they are kept)" : ""}]"}]
    if {$root eq ""} { $f.where.here state disabled }
    ttk::radiobutton $f.where.new -variable tktsearch::fixWhere -value new -text "A new checkout in:"
    ttk::entry $f.where.dir -textvariable tktsearch::fixDir -width 50
    grid $f.where.here - -sticky w
    grid $f.where.new $f.where.dir -sticky w
    grid $f.where.dir -sticky ew
    grid columnconfigure $f.where 1 -weight 1
    grid $f.lwhere $f.where -sticky nw -pady {6 2}
    grid $f.where -sticky ew
    variable fixSuggested $fixBranch
    trace add variable ::tktsearch::fixBranch write tktsearch::fixDirFollows
    bind $f <Destroy> {trace remove variable ::tktsearch::fixBranch write tktsearch::fixDirFollows}
    ttk::label $f.note -foreground gray35 -wraplength 560 -justify left -text "Then the Commit\
        tab gets the new branch and the comment, for the first commit of the fix.  Nothing is\
        committed or pushed."
    grid $f.note - -sticky w -pady {8 0}
    ttk::frame $f.b
    ttk::button $f.b.start -text Start -default active -command [list tktsearch::startFixDone $uuid]
    ttk::button $f.b.cancel -text Cancel -command {destroy .tickets.startfix}
    pack $f.b.cancel $f.b.start -side right -padx {4 0}
    grid $f.b - -sticky e -pady {10 0}
    bind .tickets.startfix <Return> [list tktsearch::startFixDone $uuid]
    focus $f.branch
    $f.branch selection range 0 end
}

proc tktsearch::startFixDone {uuid} {
    variable fixBranch
    variable fixBase
    variable fixComment
    variable fixWhere
    variable fixDir
    set w .tickets.startfix
    if {![winfo exists $w]} return
    set repo $::tickets::repo
    set root $::tktaalik::root
    set name [string trim $fixBranch]
    set problem [fossil::valueProblem "The branch name" $name name]
    if {$problem eq "" && [regexp {\s} $name]} { set problem "The branch name cannot have spaces." }
    if {$problem eq "" && [llength [fossil::sql $repo "SELECT 1 FROM tag\
            WHERE tagname=[fossil::sqlstr sym-$name]"]]} {
        set problem "There is a branch or tag \"$name\" already."
    }
    if {$problem eq "" && $fixWhere eq "new"} {
        set dir [file normalize [string trim $fixDir]]
        if {[string trim $fixDir] eq ""} {
            set problem "Which folder for the new checkout?"
        } elseif {[file exists $dir] && (![file isdirectory $dir] || [llength [glob -nocomplain -directory $dir * .*]] > 2)} {
            set problem "$dir is not empty: choose a new folder."
        } elseif {![file isdirectory [file dirname $dir]]} {
            set problem "There is no folder [file dirname $dir]."
        } elseif {$root ne "" && [string match [file normalize $root]/* $dir]} {
            set problem "The new checkout cannot be inside this one: choose a folder beside it."
        }
    }
    if {$problem ne ""} {
        ui::infoBox -parent $w -title "Start fix" $problem
        return
    }
    set t .commit.bottom.msg.text
    set replaced [expr {[winfo exists $t] && [string trim [$t get 1.0 end]] ne ""}]
    if {$fixWhere eq "here"} {
        lassign [fossil::run -dir $root update --nosync -n [fossil::arg $fixBase]] code out
        if {$code} {
            ui::errorBox -parent $w -title "Start fix" "fossil update failed (dry run):" $out
            return
        }
        lassign [fossil::run -dir $root changes] code changes
        set message "Update the checkout to the tip of $fixBase, for the new branch $name?"
        set detail "Dry run:\n[join [lrange [split [string trim $out] \n] 0 30] \n]"
        if {!$code && [string trim $changes] ne ""} {
            append detail "\n\nThe checkout has uncommitted changes: they are merged into the new\
                files, and can conflict with them."
        }
        if {$replaced} { append detail "\n\nThe comment written in the Commit tab is replaced." }
        if {![ui::confirm -parent $w -title "Start fix" $message $detail]} return
        lassign [fossil::run -dir $root update --nosync [fossil::arg $fixBase]] code out
        if {$code} {
            ui::errorBox -parent $w -title "Start fix" "fossil update failed:" $out
            return
        }
    } else {
        if {![ui::confirm -parent $w -title "Start fix" "Open a new checkout of\
                [file tail $repo] at the tip of $fixBase in $dir, for the new branch $name?" \
                "fossil open --workdir: Fossil writes the files there, and Tktaalik then shows that\
                checkout.  This checkout stays as it is.  Nothing is synced."]} return
        file mkdir $dir
        # (Beside it: inside another checkout fossil refuses.)
        lassign [fossil::run -dir [file dirname $dir] open $repo [fossil::arg $fixBase] \
            --workdir $dir --nosync] code out
        if {$code} {
            ui::errorBox -parent $w -title "Start fix" "fossil open failed:" $out
            return
        }
        destroy $w
        tktaalik::openPath $dir
    }
    destroy $w
    tktaalik::show commit
    update idletasks
    set ::tkcommit::branch $name
    $t delete 1.0 end
    $t insert end $fixComment
    set ::tkcommit::status "For the fix of [string range $uuid 0 9]: the new branch $name, from $fixBase"
}

# The fields of the web page's new-ticket form, and what it sets itself.
proc tktsearch::newTicket {} {
    variable editFields
    variable newTitle
    if {![needUser]} return
    set f [dialog .tickets.new "New ticket"]
    set choices [::tickets::choices]
    set row 0
    foreach field {title type foundin subsystem severity} {
        if {![::tickets::canWrite $field]} continue
        formRow $f [incr row] $field [dict get $editFields $field] "" $choices
    }
    # (And the repository's own fields: some setups need them.)
    foreach field $::tickets::custom {
        if {![::tickets::canWrite $field]} continue
        formRow $f [incr row] $field [::tickets::fieldLabel $field] "" $choices
    }
    formText $f [incr row] Description
    incr row 2
    ttk::frame $f.buttons
    ttk::button $f.buttons.create -text Create -default active -command tktsearch::createTicket
    ttk::button $f.buttons.cancel -text Cancel -command {destroy .tickets.new}
    pack $f.buttons.cancel $f.buttons.create -side right -padx {4 0}
    grid $f.buttons -row $row -column 0 -columnspan 2 -sticky e -pady {8 0}
    # Create needs a title and a description, however they are entered.
    set newTitle ""
    $f.etitle configure -textvariable tktsearch::newTitle
    trace add variable newTitle write tktsearch::checkNew
    bind [formattext::widget $f.editor] <<Modified>> {tktsearch::checkNew; %W edit modified 0}
    bind $f.etitle <Destroy> {trace remove variable ::tktsearch::newTitle write tktsearch::checkNew}
    checkNew
    focus $f.etitle
}

proc tktsearch::checkNew {args} {
    set f .tickets.new.f
    if {![winfo exists $f.buttons.create]} return
    set ok [expr {[string trim [$f.etitle get]] ne "" && [string trim [formattext::get $f.editor]] ne ""}]
    $f.buttons.create state [expr {$ok ? "!disabled" : "disabled"}]
}

proc tktsearch::createTicket {} {
    variable formats
    variable format
    set f .tickets.new.f
    set fields {}
    foreach field [list title type foundin subsystem severity {*}$::tickets::custom] {
        if {![winfo exists $f.e$field]} continue
        set value [string trim [fieldValue $f.e$field]]
        if {$value ne ""} { dict set fields $field $value }
    }
    set text [string trim [formattext::get $f.editor]]
    if {![dict exists $fields title] || $text eq ""} return
    dict set fields comment $text
    # What the web page's form sets itself, where these tickets have it.
    foreach {field value} [list status Open resolution None priority {5 Medium} \
            assignee nobody closer nobody is_private 0 submitter $::tickets::me \
            login $::tickets::me cmimetype [dict get $formats $format]] {
        if {[::tickets::canWrite $field] && ![dict exists $fields $field]} {
            dict set fields $field $value
        }
    }
    if {![confirm "New ticket" "Create this ticket?" [summary $fields]]} return
    set id [write add "" $fields]
    if {$id eq ""} return
    destroy .tickets.new
    showTicket $id
}
