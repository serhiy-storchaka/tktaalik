# Changing the tags of check-ins, for the Timeline and Tags tabs: add and
# cancel a tag ("fossil tag add/cancel"), edit a check-in ("fossil amend":
# its comment, author, date, branch, colours, tags, closing, hiding), and
# reparent it ("fossil reparent", for experts).  Each first runs the
# command with --dry-run and shows what it would record, to confirm.  The
# changes go into the local repository only: none of these syncs.
#
#   tagwrite::addTag REPO CHECKIN ?NAME? ?DONE?
#   tagwrite::cancelTag REPO NAME CHECKIN ?RAW? ?DONE?
#   tagwrite::amend REPO RID ?DONE?
#   tagwrite::reparent REPO CHECKIN ?DONE?
#
# DONE is a script run (at the global level) after a change.

source [file join [file dirname [file normalize [info script]]] fossil.tcl]

namespace eval tagwrite {
    variable answer 0
    variable f                ;# array: the fields of the dialog shown
}

# A modal dialog: the toplevel W with the frame W.f to fill.
proc tagwrite::dialog {w title} {
    ui::dialog $w $title -bar 1 -close {set tagwrite::answer 0} -escape {set tagwrite::answer 0}
}

# The OK and Cancel buttons of the dialog W; wait for one.  CHECK is a
# command that returns "" if the fields are right, else what is wrong.
proc tagwrite::wait {w ok {check {}}} {
    variable answer
    ui::buttons $w.b $ok {set tagwrite::answer 1} {set tagwrite::answer 0}
    while 1 {
        set answer 0
        vwait ::tagwrite::answer
        if {!$answer || $check eq ""} break
        set problem [uplevel #0 $check]
        if {$problem eq ""} break
        tk_messageBox -icon info -parent $w -title [wm title $w] -message $problem
    }
    destroy $w
    return $answer
}

# What the command would record (its dry run): apply it?  -note NOTE: the
# line under it (what changes, what does not).
proc tagwrite::confirm {title message text args} {
    set note [expr {[dict exists $args -note] ? [dict get $args -note]
        : "Only the local repository is changed: nothing is pushed."}]
    set w [dialog .tagwrite title]
    wm title .tagwrite $title
    ttk::label $w.msg -text $message -wraplength 600 -justify left
    text $w.t -width 90 -height 12 -font TkFixedFont -wrap none -yscrollcommand [list $w.y set]
    ttk::scrollbar $w.y -command [list $w.t yview]
    $w.t insert end [string trim $text]
    $w.t configure -state disabled
    ttk::label $w.note -text $note -foreground gray40 -wraplength 600 -justify left
    grid $w.msg - -sticky w -pady {0 6}
    grid $w.t $w.y -sticky news
    grid $w.note - -sticky w -pady {6 0}
    grid columnconfigure $w 0 -weight 1
    grid rowconfigure $w 1 -weight 1
    focus .tagwrite.b
    wait .tagwrite Apply
}

proc tagwrite::failed {title message out} {
    tk_messageBox -icon error -title $title -message $message -detail [string trim $out]
}

# Run "fossil CMD" after its dry run is confirmed; then DONE.  1 if done.
proc tagwrite::apply {title message repo cmd done} {
    lassign [fossil::run {*}$cmd -R $repo --dry-run] code out
    if {$code} {
        failed $title "fossil [lindex $cmd 0] failed:" $out
        return 0
    }
    if {![confirm $title $message "fossil [join [lmap a $cmd {
            expr {[regexp {[\s"]} $a] ? "\"$a\"" : $a}
        }]]\n\n$out"]} {
        return 0
    }
    lassign [fossil::run {*}$cmd -R $repo] code out
    if {$code} {
        failed $title "fossil [lindex $cmd 0] failed:" $out
        return 0
    }
    if {$done ne ""} { uplevel #0 $done }
    return 1
}

# A tag name: not empty, no spaces, not an internal prefix.
proc tagwrite::badTag {name {raw 0}} {
    if {$name eq ""} { return "The tag name is empty." }
    if {[regexp {\s} $name]} { return "The tag name \"$name\" contains spaces." }
    if {[catch {fossil::arg $name}]} { return "A tag name cannot start with \"[string index $name 0]\"." }
    if {[regexp {^(wiki|tkt|event)-} $name]} {
        return "Tags starting with wiki-, tkt- or event- are Fossil's own."
    }
    if {!$raw && [string match sym-* $name]} { return "Without the sym- prefix: it is added." }
    return ""
}

# ---------------------------------------------------------------- tags

# Add a tag to a check-in (or any artifact): its name, a value, whether it
# propagates to the descendants, whether the name is raw (a property such
# as bgcolor, not a symbolic name).
proc tagwrite::addTag {repo checkin {name ""} {done ""}} {
    variable f
    array set f [list checkin $checkin name $name value "" propagate 0 raw 0]
    set w [dialog .tagwrite "Add tag"]
    ttk::label $w.cl -text "Check-in:"
    ttk::entry $w.c -textvariable tagwrite::f(checkin) -width 40
    ttk::label $w.nl -text "Tag:"
    ttk::entry $w.n -textvariable tagwrite::f(name) -width 40
    ttk::label $w.vl -text "Value:"
    ttk::entry $w.v -textvariable tagwrite::f(value) -width 40
    ttk::checkbutton $w.p -text "Propagate to the descendants (as a branch name does)" \
        -variable tagwrite::f(propagate)
    ttk::checkbutton $w.r -text "Raw name: a property (bgcolor, closed...), not a symbolic tag" \
        -variable tagwrite::f(raw)
    ttk::label $w.note -foreground gray40 -justify left -text "The check-in: a hash, a tag\
        or a branch name (its newest check-in), a date."
    grid $w.cl $w.c -sticky w -pady 2
    grid $w.nl $w.n -sticky w -pady 2
    grid $w.vl $w.v -sticky w -pady 2
    grid $w.p - -sticky w -pady 2
    grid $w.r - -sticky w -pady 2
    grid $w.note - -sticky w -pady {6 0}
    focus [expr {$name eq "" ? "$w.n" : "$w.c"}]
    bind .tagwrite <Return> {set tagwrite::answer 1}
    if {![wait .tagwrite "Add\u2026" {tagwrite::checkAdd}]} { return 0 }
    set cmd [list tag add]
    if {$f(propagate)} { lappend cmd --propagate }
    if {$f(raw)} { lappend cmd --raw }
    lappend cmd [string trim $f(name)] [string trim $f(checkin)]
    if {$f(value) ne ""} { lappend cmd $f(value) }
    apply "Add tag" "Add the tag [string trim $f(name)] to [string trim $f(checkin)]?" \
        $repo $cmd $done
}

proc tagwrite::checkAdd {} {
    variable f
    set problem [badTag [string trim $f(name)] $f(raw)]
    if {$problem ne ""} { return $problem }
    if {[string trim $f(checkin)] eq ""} { return "Which check-in?" }
    if {[catch {fossil::arg [string trim $f(checkin)]}]} { return "Not a check-in: $f(checkin)" }
    if {$f(value) ne "" && [catch {fossil::arg $f(value)}]} {
        return "A value cannot start with \"[string index $f(value) 0]\"."
    }
    return ""
}

# Cancel a tag on a check-in (and where it propagated from there).
proc tagwrite::cancelTag {repo name checkin {raw 0} {done ""}} {
    # (Names from the repository: maybe made by another program.)
    foreach v [list $name $checkin] {
        if {[catch {fossil::arg $v}]} {
            failed "Cancel tag" "This name cannot be passed to fossil:" "\"$v\""
            return 0
        }
    }
    set cmd [list tag cancel]
    if {$raw} { lappend cmd --raw }
    lappend cmd [fossil::arg $name] [fossil::arg $checkin]
    apply "Cancel tag" "Cancel the tag $name on [string range $checkin 0 9]?" $repo $cmd $done
}

# ---------------------------------------------------------------- amend

# Edit a check-in: what is changed in the dialog becomes the options of
# "fossil amend".
proc tagwrite::amend {repo rid {done ""}} {
    variable f
    set row [lindex [fossil::sql $repo "SELECT b.uuid,
        [fossil::outcol "coalesce(e.ecomment,e.comment,'')"],
        [fossil::outcol "coalesce(e.euser,e.user,'')"],
        strftime('%Y-%m-%d %H:%M:%S', e.mtime),
        [fossil::outcol "coalesce((SELECT value FROM tagxref WHERE rid=e.objid AND tagtype>0
            AND tagid=(SELECT tagid FROM tag WHERE tagname='branch')),'')"],
        [fossil::outcol "coalesce((SELECT value FROM tagxref WHERE rid=e.objid AND tagtype=1
            AND tagid=(SELECT tagid FROM tag WHERE tagname='bgcolor')),'')"],
        [fossil::outcol "coalesce((SELECT value FROM tagxref WHERE rid=e.objid AND tagtype=2
            AND tagid=(SELECT tagid FROM tag WHERE tagname='bgcolor')),'')"],
        e.objid IN (SELECT rid FROM leaf),
        EXISTS (SELECT 1 FROM tagxref WHERE rid=e.objid AND tagtype>0
            AND tagid=(SELECT tagid FROM tag WHERE tagname='closed')),
        EXISTS (SELECT 1 FROM tagxref WHERE rid=e.objid AND tagtype>0
            AND tagid=(SELECT tagid FROM tag WHERE tagname='hidden'))
        FROM event e JOIN blob b ON b.rid=e.objid WHERE e.objid=$rid AND e.type='ci'"] 0]
    if {$row eq ""} { return 0 }
    lassign $row uuid comment user date branch bgcolor branchcolor leaf closed hidden
    # Its own tags, propagating ones too (not names of branches).
    set tags [lmap r [fossil::sql $repo "SELECT [fossil::outcol "substr(t.tagname,5)"]
        FROM tagxref x JOIN tag t ON t.tagid=x.tagid
        WHERE x.rid=$rid AND x.tagtype>0 AND x.origid=x.rid AND t.tagname GLOB 'sym-*'
        AND NOT EXISTS (SELECT 1 FROM tagxref b
            WHERE b.tagid=(SELECT tagid FROM tag WHERE tagname='branch') AND b.value=substr(t.tagname,5))
        ORDER BY 1"] { lindex $r 0 }]
    array unset f
    array set f [list comment $comment user $user date $date branch $branch \
        bgcolor $bgcolor branchcolor $branchcolor addTags "" close 0 hide 0 noverify 0]
    set w [dialog .tagwrite "Edit check-in [string range $uuid 0 9]"]
    ttk::label $w.ml -text "Comment:"
    text $w.m -width 70 -height 6 -wrap word -font TkFixedFont -undo 1
    $w.m insert end $comment
    ttk::checkbutton $w.nv -text "Do not check the comment (links, markup)" \
        -variable tagwrite::f(noverify)
    # (Fossil 2.21 checks no comments: no such option.)
    if {![fossil::helpMatches amend *--no-verify-comment*]} {
        $w.nv state disabled
        icons::tooltip $w.nv "This Fossil does not check comments"
    }
    ttk::label $w.ul -text "Author:"
    ttk::entry $w.u -textvariable tagwrite::f(user) -width 30
    ttk::label $w.dl -text "Date (UTC):"
    ttk::entry $w.d -textvariable tagwrite::f(date) -width 30
    ttk::label $w.brl -text "Branch:"
    ttk::entry $w.br -textvariable tagwrite::f(branch) -width 30
    ttk::label $w.brn -foreground gray40 -text "(renamed from here on)"
    foreach {key label} {bgcolor "Colour:" branchcolor "Branch colour:"} {
        ttk::label $w.${key}l -text $label
        ttk::frame $w.$key
        ttk::entry $w.$key.e -textvariable tagwrite::f($key) -width 12
        ttk::button $w.$key.c -text "Choose\u2026" -command [list tagwrite::chooseColor $key]
        pack $w.$key.e $w.$key.c -side left -padx {0 4}
    }
    ttk::label $w.tl -text "Add tags:"
    ttk::entry $w.t -textvariable tagwrite::f(addTags) -width 40
    ttk::frame $w.ct
    set i 0
    foreach tag $tags {
        set f(cancel,$tag) 0
        ttk::checkbutton $w.ct.c[incr i] -text $tag -variable tagwrite::f(cancel,$tag)
        pack $w.ct.c$i -side left -padx {0 6}
        # (A name fossil cannot take as an argument: not offered.)
        if {[catch {fossil::arg $tag}]} { $w.ct.c$i state disabled }
    }
    ttk::checkbutton $w.close -text [expr {$closed ? "Closed" : $leaf ? "Close this leaf"
        : "Close (only a leaf can be closed)"}] -variable tagwrite::f(close)
    if {!$leaf || $closed} { $w.close state disabled }
    ttk::checkbutton $w.hide -text [expr {$hidden ? "Hidden" : "Hide the branch from here on"}] \
        -variable tagwrite::f(hide)
    if {$hidden} { $w.hide state disabled }
    grid $w.ml - - -sticky w
    grid $w.m - - -sticky news -pady 2
    grid $w.nv - - -sticky w -pady {0 6}
    grid $w.ul $w.u - -sticky w -pady 2
    grid $w.dl $w.d - -sticky w -pady 2
    grid $w.brl $w.br $w.brn -sticky w -pady 2
    grid $w.bgcolorl $w.bgcolor - -sticky w -pady 2
    grid $w.branchcolorl $w.branchcolor - -sticky w -pady 2
    grid $w.tl $w.t - -sticky w -pady 2
    if {[llength $tags]} {
        ttk::label $w.ctl -text "Cancel tags:"
        grid $w.ctl $w.ct - -sticky w -pady 2
    }
    grid $w.close - - -sticky w -pady 2
    grid $w.hide - - -sticky w -pady 2
    grid columnconfigure $w 2 -weight 1
    grid rowconfigure $w 1 -weight 1
    focus $w.m
    set f(original) [list comment [string trimright $comment \n] user $user date $date branch $branch \
        bgcolor $bgcolor branchcolor $branchcolor]
    if {![wait .tagwrite "Apply\u2026" tagwrite::checkAmend]} { return 0 }
    set opts [amendOptions]
    if {![llength $opts]} {
        tk_messageBox -icon info -title "Edit check-in" -message "Nothing is changed."
        return 0
    }
    # (The comment from a file: it can start with anything.)
    set file ""
    if {[dict get $f(original) comment] ne $f(comment)} {
        set chan [file tempfile file tktaalik-comment.txt]
        fconfigure $chan -encoding utf-8 -translation lf
        puts -nonewline $chan $f(comment)
        close $chan
        lappend opts -M $file
    }
    try {
        apply "Edit check-in" "Change check-in [string range $uuid 0 9]?" $repo \
            [list amend $uuid {*}$opts] $done
    } finally {
        if {$file ne ""} { file delete $file }
    }
}

# The fields of the amend dialog: right?  (Also takes the comment from
# its text before the dialog goes.)
proc tagwrite::checkAmend {} {
    variable f
    set f(comment) [string trimright [.tagwrite.f.m get 1.0 end] \n]
    if {[string trim $f(comment)] eq ""} { return "The comment is empty." }
    foreach key {user branch} label {author branch} {
        set v [string trim $f($key)]
        if {$v eq "" || [catch {fossil::arg $v}] || [regexp {\s} $v] && $key eq "branch"} {
            return "Not a $label name: \"$v\"."
        }
    }
    set d [string trim $f(date)]
    if {![regexp {^\d{4}-\d\d-\d\d(?:[T ]\d\d:\d\d(?::\d\d(?:\.\d+)?)?)?(?:Z|[-+]\d\d:\d\d)?$} $d]} {
        return "The date: YYYY-MM-DD HH:MM:SS (UTC), or with an offset as +HH:MM."
    }
    foreach key {bgcolor branchcolor} {
        if {$f($key) ne "" && ![regexp {^#[0-9a-fA-F]{3,6}$|^[a-zA-Z]+$} $f($key)]} {
            return "Not a colour: $f($key) (#rrggbb or a name)."
        }
    }
    # (Given both, fossil amend sets only the branch colour.)
    set old $f(original)
    if {[string trim $f(bgcolor)] ne [dict get $old bgcolor]
            && [string trim $f(branchcolor)] ne [dict get $old branchcolor]} {
        return "Change one of the colours at a time: given both, Fossil sets only the branch\
            colour (on this check-in and the ones after it)."
    }
    foreach tag [regexp -all -inline {\S+} $f(addTags)] {
        set problem [badTag $tag]
        if {$problem ne ""} { return $problem }
    }
    return ""
}

# The options of "fossil amend" for what is changed (not the comment).
proc tagwrite::amendOptions {} {
    variable f
    set opts {}
    set old $f(original)
    foreach {key option} {user --author date --date branch --branch
            bgcolor --bgcolor branchcolor --branchcolor} {
        set v [string trim $f($key)]
        if {$v ne [dict get $old $key]} { lappend opts $option $v }
    }
    foreach tag [regexp -all -inline {\S+} $f(addTags)] { lappend opts --tag $tag }
    foreach key [array names f cancel,*] {
        # (Names from the repository: kept out if fossil cannot take them.)
        if {$f($key) && ![catch {fossil::arg [string range $key 7 end]}]} {
            lappend opts --cancel [string range $key 7 end]
        }
    }
    if {$f(close)} { lappend opts --close }
    if {$f(hide)} { lappend opts --hide }
    if {[llength $opts] || [dict get $old comment] ne $f(comment)} {
        if {$f(noverify) && [fossil::helpMatches amend *--no-verify-comment*]} { lappend opts --no-verify-comment }
    }
    return $opts
}

proc tagwrite::chooseColor {key} {
    variable f
    set initial [expr {$f($key) ne "" && ![catch {winfo rgb . $f($key)}] ? $f($key) : "#ffffff"}]
    set c [tk_chooseColor -parent .tagwrite -initialcolor $initial]
    if {$c ne ""} { set f($key) $c }
}

# ------------------------------------------------------------- reparent

# Give a check-in other parents (the first the primary one): to patch up
# a damaged history.  A tag: cancelling it undoes this.
proc tagwrite::reparent {repo checkin {done ""}} {
    variable f
    array unset f
    set f(parents) ""
    set w [dialog .tagwrite "Reparent [string range $checkin 0 9]"]
    ttk::label $w.warn -wraplength 460 -justify left -text "For experts: to patch up a\
        history damaged by shunning, or pieced together from separate repositories.\
        It is a tag (\"parent\") on the check-in; cancelling it undoes this."
    ttk::label $w.pl -text "Parents:"
    ttk::entry $w.p -textvariable tagwrite::f(parents) -width 50
    ttk::label $w.note -foreground gray40 -text "Hashes, the primary parent first, then\
        the merged ones."
    grid $w.warn - -sticky w -pady {0 8}
    grid $w.pl $w.p -sticky w -pady 2
    grid $w.note - -sticky w
    focus $w.p
    bind .tagwrite <Return> {set tagwrite::answer 1}
    if {![wait .tagwrite "Reparent\u2026" tagwrite::checkReparent]} { return 0 }
    apply "Reparent" "Reparent [string range $checkin 0 9]?" $repo \
        [list reparent [fossil::arg $checkin] {*}[regexp -all -inline {\S+} $f(parents)]] $done
}

proc tagwrite::checkReparent {} {
    variable f
    set parents [regexp -all -inline {\S+} $f(parents)]
    if {![llength $parents]} { return "Which parents?" }
    foreach p $parents {
        if {[catch {fossil::arg $p}]} { return "Not a check-in: $p" }
    }
    return ""
}
