# The Tickets tab (lib/tktsearch.tcl): the attachments of a ticket (view,
# save, apply a patch to the checkout).

# ------------------------------------------------------------ attachments

# The Attachments tab, like the Check-ins tab: double-click views one (or
# opens it on the server if its content is not here), the context menu
# also saves it or applies a patch.
proc tktsearch::buildAttachments {f} {
    ttk::frame $f
    set tv $f.tv
    ttk::treeview $tv -columns {file size user date comment} -show headings \
        -selectmode browse -yscrollcommand [list $f.y set]
    ttk::scrollbar $f.y -command [list $tv yview]
    set char [font measure TkDefaultFont 0]
    foreach {col heading chars anchor} {
        file File 24 w  size Size 9 e  user User 15 w  date Date 18 w  comment Comment 30 w
    } {
        $tv heading $col -text $heading -anchor $anchor
        $tv column $col -width [expr {$chars * $char}] -anchor $anchor \
            -stretch [expr {$col eq "comment"}]
    }
    $tv tag configure missing -foreground gray50
    ttk::label $f.hint -foreground gray40 -padding {4 2} \
        -text "Double-click to view; right-click to save, or apply a patch to the checkout."
    grid $tv $f.y -sticky news
    grid $f.hint - -sticky w
    grid columnconfigure $f 0 -weight 1
    grid rowconfigure $f 0 -weight 1
    bind $tv <Double-1> {
        if {[%W identify region %x %y] eq "cell"} {
            tktsearch::openAttachment [%W identify item %x %y]
        }
    }
    bind $tv <Return> {tktsearch::openAttachment [lindex [%W selection] 0]}
    if {[tk windowingsystem] eq "aqua"} {
        bind $tv <2> {tktsearch::attachmentMenu %W %x %y %X %Y}
        bind $tv <Control-1> {tktsearch::attachmentMenu %W %x %y %X %Y}
    } else {
        bind $tv <3> {tktsearch::attachmentMenu %W %x %y %X %Y}
    }
    return $f
}

proc tktsearch::fillAttachments {attachments} {
    variable attached
    array unset attached
    set tv .tickets.main.details.nb.attachments.tv
    $tv delete [$tv children {}]
    set i 0
    foreach row $attachments {
        lassign $row src name user date comment size
        # The content can be missing: the attachment arrived, the file not.
        set here [expr {$size >= 0}]
        set attached($i) [dict create src $src name $name here $here]
        $tv insert {} end -id $i -tags [expr {$here ? "" : "missing"}] \
            -values [list $name [expr {$here ? [sizeText $size] : "not local"}] $user $date \
                [fossil::oneLine $comment]]
        incr i
    }
}

# View an attachment, or open it on the server if it is not here.
proc tktsearch::openAttachment {i} {
    variable attached
    variable shownTicket
    if {$i eq "" || ![info exists attached($i)]} return
    set a $attached($i)
    if {[dict get $a here]} {
        viewAttachment [dict get $a src] [dict get $a name]
    } else {
        openUrl attachview?tkt=$shownTicket&file=[fossil::urlquery [dict get $a name]]
    }
}

proc tktsearch::attachmentMenu {tv x y X Y} {
    variable attached
    variable shownTicket
    set i [$tv identify item $x $y]
    if {$i eq "" || ![info exists attached($i)]} return
    $tv selection set $i
    set a $attached($i)
    lassign [list [dict get $a src] [dict get $a name]] src name
    set here [expr {[dict get $a here] ? "normal" : "disabled"}]
    set m .tickets.attctx
    if {![winfo exists $m]} { menu $m }
    $m delete 0 end
    $m add command -label View -state $here -command [list tktsearch::viewAttachment $src $name]
    $m add command -label Save\u2026 -state $here -command [list tktsearch::saveAttachment $src $name]
    if {[isPatch $name]} {
        $m add command -label "Apply to the checkout\u2026" -state $here \
            -command [list tktsearch::applyAttachment $src $name]
    }
    $m add separator
    $m add command -label "Open in browser" \
        -command [list tktsearch::openUrl attachview?tkt=$shownTicket&file=[fossil::urlquery $name]]
    $m add command -label "Copy file name" -command [list ui::copy $name]
    tk_popup $m $X $Y
}

proc tktsearch::sizeText {size} {
    if {$size < 1024} { return "$size bytes" }
    if {$size < 1048576} { return "[format %.1f [expr {$size / 1024.0}]] KB" }
    format "%.1f MB" [expr {$size / 1048576.0}]
}

proc tktsearch::isPatch {name} {
    regexp -nocase {\.(?:patch|diff)$} $name
}

# The content of an attachment, or "" (and a message) if it cannot be read
# or is not text.
proc tktsearch::attachmentText {src} {
    lassign [fossil::run artifact -R $::tickets::repo $src] code out
    if {$code} {
        tk_messageBox -icon error -title Attachment -message "Cannot read the attachment:" -detail $out
        return ""
    }
    if {[string first \0 $out] >= 0} {
        tk_messageBox -icon info -title Attachment -message "This is not a text file." \
            -detail "Save it to look at it."
        return ""
    }
    return $out
}

proc tktsearch::viewAttachment {src name} {
    set text [attachmentText $src]
    if {$text eq ""} return
    diffview::show $name $text
}

proc tktsearch::saveAttachment {src name} {
    set file [tk_getSaveFile -title "Save attachment" -initialfile $name]
    if {$file eq ""} return
    lassign [fossil::run artifact -R $::tickets::repo $src [file normalize $file]] code out
    if {$code} {
        tk_messageBox -icon error -title Attachment -message "Cannot save the attachment:" -detail $out
    }
}

# Apply a patch to the checkout with "patch", after a dry run that also
# finds the number of leading path parts to strip (-p0: Fossil, -p1: git).
proc tktsearch::applyAttachment {src name} {
    set root $::tktaalik::root
    if {$root eq ""} {
        tk_messageBox -icon info -title "Apply patch" -message "Applying a patch needs a checkout." \
            -detail "Open one with File \u25b8 Open checkout."
        return
    }
    if {[auto_execok patch] eq ""} {
        tk_messageBox -icon error -title "Apply patch" -message "The program \"patch\" is not installed."
        return
    }
    close [file tempfile file .patch]
    lassign [fossil::run artifact -R $::tickets::repo $src $file] code out
    if {$code} {
        tk_messageBox -icon error -title "Apply patch" -message "Cannot read the attachment:" -detail $out
        return
    }
    set here [pwd]
    cd $root
    try {
        set strip ""
        foreach p {0 1} {
            set failed [catch {exec patch --dry-run --batch -N -p$p -i $file << ""} dry]
            set dry [regsub {\n?child process exited abnormally$} $dry ""]
            if {!$failed} {
                set strip $p
                break
            }
            if {$p == 0} { set first $dry }
        }
        if {$strip eq ""} {
            tk_messageBox -icon error -title "Apply patch" \
                -message "$name does not apply to the checkout." -detail $first
            return
        }
        if {![ui::confirm -title "Apply patch" \
                "Apply $name to [file tail $root]?" \
                "Dry run (patch -p$strip):\n[string range [string trim $dry] 0 1500]\n\nThe files of\
                    the checkout change; nothing is committed."]} return
        if {[catch {exec patch --batch -N -p$strip -i $file << ""} out]} {
            tk_messageBox -icon error -title "Apply patch" -message "patch failed:" \
                -detail [regsub {\n?child process exited abnormally$} $out ""]
            return
        }
    } finally {
        cd $here
        file delete $file
    }
    if {[ui::ask -title "Apply patch" "Applied $name." \
            "[string trim $out]\n\nShow the Commit tab?"]} {
        tktaalik::show commit
    }
}

# The check-ins of a ticket as a list: {time user uuid comment} each.
proc tktsearch::buildCheckins {f} {
    ttk::frame $f
    set tv $f.tv
    ttk::treeview $tv -columns {time hash user comment} -show headings \
        -selectmode browse -yscrollcommand [list $f.y set]
    ttk::scrollbar $f.y -command [list $tv yview]
    set char [font measure TkDefaultFont 0]
    foreach {col heading chars} {time Date 18 hash Check-in 11 user User 15 comment Comment 40} {
        $tv heading $col -text $heading -anchor w
        $tv column $col -width [expr {$chars * $char}] -stretch [expr {$col eq "comment"}]
    }
    grid $tv $f.y -sticky news
    grid columnconfigure $f 0 -weight 1
    grid rowconfigure $f 0 -weight 1
    # A check-in: in the Timeline (its files and diff there); the browser
    # from the context menu.
    bind $tv <Double-1> {
        if {[%W identify region %x %y] eq "cell"} {
            goto::checkin [%W identify item %x %y]
        }
    }
    bind $tv <Return> {goto::checkin [lindex [%W selection] 0]}
    bind $tv <3> {tktsearch::checkinMenu %W %x %y %X %Y}
    if {[tk windowingsystem] eq "aqua"} { bind $tv <2> {tktsearch::checkinMenu %W %x %y %X %Y} }
    return $f
}

proc tktsearch::checkinMenu {tv x y X Y} {
    set uuid [$tv identify item $x $y]
    if {$uuid eq ""} return
    $tv selection set [list $uuid]
    set m .tickets.cictx
    if {![winfo exists $m]} { menu $m }
    $m delete 0 end
    $m add command -label "Show in Timeline" -command [list goto::checkin $uuid]
    $m add command -label "Diff of this check-in" -command [list diffview::run \
        "Check-in [string range $uuid 0 9]" -- -R $::tickets::repo --checkin $uuid]
    $m add command -label "Open in browser" -command [list tktsearch::openUrl info/$uuid]
    $m add separator
    $m add command -label "Copy check-in" -command [list ui::copy $uuid]
    tk_popup $m $X $Y
}

proc tktsearch::fillCheckins {checkins} {
    set tv .tickets.main.details.nb.checkins.tv
    $tv delete [$tv children {}]
    foreach checkin $checkins {
        lassign $checkin time user uuid text
        $tv insert {} end -id $uuid -values [list $time [string range $uuid 0 9] \
            $user [fossil::oneLine $text]]
    }
}

# The embedded check-in list and comment box: as wide as the panels.
# The comment box as wide as the panels.
proc tktsearch::fitReply {d} {
    set inner [expr {[winfo width $d] - 2 * ([$d cget -padx] + [$d cget -borderwidth]
        + [$d cget -highlightthickness] + [font measure TkDefaultFont 0])}]
    if {[winfo exists $d.reply]} { $d.reply configure -width [expr {max($inner, 100)}] }
}
