# The dialogs and small things of every window, in one way.  New code uses
# these, not tk_messageBox, toplevel, clipboard or vwait of its own:
#
#   ui::confirm ?-parent W? ?-title T? ?-icon I? ?-default D? MESSAGE ?DETAIL?
#                               OK or Cancel (Cancel the default): 1 if OK
#   ui::ask ?-parent W? ?-title T? ?-icon I? ?-default D? MESSAGE ?DETAIL?
#                               Yes or No: 1 if Yes
#   ui::errorBox ?-parent W? ?-title T? MESSAGE ?DETAIL?
#   ui::infoBox ?-parent W? ?-title T? MESSAGE ?DETAIL?
#   ui::copy TEXT               to the clipboard
#   ui::openServer REMOTE PATH ?-title T? ?-quiet 0|1? ?-browse CMD?
#                               REMOTE/PATH in the browser (REMOTE: the
#                               server URL, as fossil::remoteUrl gives);
#                               none: a message titled T (none if -quiet)
#   ui::dialog W TITLE ?-escape SCRIPT? ?-close SCRIPT? ?-bar 0|1?
#           ?-help TARGET?      the toplevel W (made again) with the frame
#                               W.f to fill (and W.b at the bottom if -bar):
#                               W.f
#   ui::buttons FRAME OK OKSCRIPT CANCELSCRIPT
#                               FRAME.ok (labelled OK, the default) and
#                               FRAME.cancel, packed right
#   ui::later CMD ?MS?          CMD MS (250) after the last call with it
#   ui::setText W TEXT          a read-only text widget's text
#   ui::form W TITLE INTRO FIELDS OK ?-array NAME? ?-done VAR?
#           ?-validate CMD? ?-preview CMD? ?-help TARGET?
#                               a modal dialog of fields, one at a time: 1
#                               if OK (the values in the array); see below
#   ui::formBusy                1 if a form is open (then it is raised)
#   ui::textWindow W TITLE TEXT a text to read (and copy), with Close
#   ui::helpFor W TARGET        F1 in W: TARGET (page#anchor) of the manual

namespace eval ui {
    variable f                  ;# array: the fields of a form (by default)
    variable done ""            ;# ok or cancel: a form's answer (by default)
    variable formOpen ""        ;# the form open (one at a time)
    variable formPreview        ;# array: form -> the command of its preview
}

# ------------------------------------------------------------ messages

proc ui::Box {icon type argv} {
    set opts {}
    while {[llength $argv] && [lindex $argv 0] in {-parent -title -icon -default}} {
        set argv [lassign $argv opt value]
        lappend opts $opt $value
    }
    lassign $argv message detail
    lappend opts -message $message
    if {[llength $argv] > 1} { lappend opts -detail $detail }
    if {$type ne "ok"} { lappend opts -type $type }
    if {$type eq "okcancel" && ![dict exists $opts -default]} { lappend opts -default cancel }
    tk_messageBox -icon $icon {*}$opts
}

proc ui::confirm {args} {
    expr {[Box question okcancel $args] eq "ok"}
}

proc ui::ask {args} {
    expr {[Box question yesno $args] eq "yes"}
}

proc ui::errorBox {args} {
    Box error ok $args
    return
}

proc ui::infoBox {args} {
    Box info ok $args
    return
}

proc ui::copy {text} {
    clipboard clear
    clipboard append $text
}

proc ui::openServer {remote path args} {
    set title [expr {[dict exists $args -title] ? [dict get $args -title] : "Tktaalik"}]
    set browse [expr {[dict exists $args -browse] ? [dict get $args -browse] : "fossil::browse"}]
    if {$remote eq ""} {
        if {![dict exists $args -quiet] || ![dict get $args -quiet]} {
            infoBox -title $title "The repository has no server URL."
        }
        return
    }
    uplevel #0 [list {*}$browse $remote/$path]
}

# ------------------------------------------------------------- dialogs

proc ui::dialog {w title args} {
    destroy $w
    toplevel $w
    wm title $w $title
    wm transient $w .
    ttk::frame $w.f -padding 10
    pack $w.f -fill both -expand 1
    if {[dict exists $args -bar] && [dict get $args -bar]} {
        ttk::frame $w.b -padding {10 0 10 10}
        pack $w.b -side bottom -fill x
    }
    if {[dict exists $args -close]} { wm protocol $w WM_DELETE_WINDOW [dict get $args -close] }
    if {[dict exists $args -escape]} { bind $w <Escape> [dict get $args -escape] }
    if {[dict exists $args -help]} { helpFor $w [dict get $args -help] }
    return $w.f
}

proc ui::buttons {frame ok okScript cancelScript} {
    ttk::button $frame.ok -text $ok -default active -command $okScript
    ttk::button $frame.cancel -text Cancel -command $cancelScript
    pack $frame.cancel $frame.ok -side right -padx {4 0}
}

proc ui::later {cmd {ms 250}} {
    after cancel $cmd
    after $ms $cmd
}

proc ui::setText {w text} {
    $w configure -state normal
    $w delete 1.0 end
    $w insert end $text
    $w configure -state disabled
}

# F1 there: the manual at TARGET (the longest prefix wins, so a window's
# own entry is kept).
proc ui::helpFor {w target} {
    if {![info exists ::help::contexts]} return
    foreach {prefix t} $::help::contexts {
        if {$prefix eq $w} return
    }
    lappend ::help::contexts $w $target
}

proc ui::textWindow {w title text} {
    destroy $w
    toplevel $w
    wm title $w $title
    wm transient $w .
    ttk::frame $w.b -padding 6
    ttk::button $w.b.close -text Close -command [list destroy $w]
    pack $w.b.close -side right
    pack $w.b -side bottom -fill x
    text $w.t -width 90 -height 20 -font TkFixedFont -wrap word -yscrollcommand [list $w.y set]
    ttk::scrollbar $w.y -command [list $w.t yview]
    pack $w.y -side right -fill y
    pack $w.t -fill both -expand 1
    setText $w.t $text
    bind $w <Escape> [list destroy $w]
    focus $w.t
    return $w
}

# ---------------------------------------------------------------- forms

# A dialog of FIELDS ({key label kind ?arg?} each; kinds: entry, secret,
# check, combo (arg: the values; anything can be typed), choice (arg: the
# values, only those), save, open (arg: file types), dir) with an OK
# button labelled OK; the values in the array -array (::ui::f), the answer
# (ok, cancel) in -done (::ui::done: setting it answers).  -validate CMD
# is called with the dialog and returns "" or a problem to show ("-":
# none to show, the dialog stays).  -preview CMD is called with the
# dialog and returns the dry run to show under the fields, again a moment
# after each change.  1 if OK.  One at a time: modal (another one asked
# for while it is open is refused).
proc ui::form {w title intro fields ok args} {
    variable formOpen
    variable formPreview
    set array [expr {[dict exists $args -array] ? [dict get $args -array] : "::ui::f"}]
    set doneVar [expr {[dict exists $args -done] ? [dict get $args -done] : "::ui::done"}]
    set validate [expr {[dict exists $args -validate] ? [dict get $args -validate] : ""}]
    set preview [expr {[dict exists $args -preview] ? [dict get $args -preview] : ""}]
    upvar #0 $array f $doneVar done
    if {[formBusy]} { return 0 }
    destroy $w
    toplevel $w
    set formOpen $w
    wm title $w $title
    wm transient $w .
    if {[dict exists $args -help]} { helpFor $w [dict get $args -help] }
    ttk::frame $w.f -padding 10
    pack $w.f -fill both -expand 1
    if {$intro ne ""} {
        ttk::label $w.f.intro -text $intro -wraplength 480 -justify left
        grid $w.f.intro - - -sticky w -pady {0 8}
    }
    foreach field $fields {
        lassign $field key label kind arg
        if {![info exists f($key)]} { set f($key) "" }
        switch -- $kind {
            check {
                ttk::checkbutton $w.f.$key -text $label -variable ${array}($key)
                grid x $w.f.$key - -sticky w -pady 1
            }
            default {
                ttk::label $w.f.l$key -text $label
                if {$kind in {combo choice}} {
                    ttk::combobox $w.f.$key -textvariable ${array}($key) -values $arg -width 40
                    if {$kind eq "choice"} { $w.f.$key state readonly }
                } else {
                    ttk::entry $w.f.$key -textvariable ${array}($key) -width 50 \
                        -show [expr {$kind eq "secret" ? "*" : ""}]
                }
                grid $w.f.l$key $w.f.$key -sticky ew -pady 2
                if {$kind in {save open dir}} {
                    ttk::button $w.f.b$key -text "Browse\u2026" \
                        -command [list ui::Browse $w $array $key $kind $arg]
                    grid $w.f.b$key -row [dict get [grid info $w.f.$key] -row] -column 2 -padx {4 0}
                }
            }
        }
    }
    grid columnconfigure $w.f 1 -weight 1
    if {$preview ne ""} {
        ttk::label $w.f.pl -text "What it does (dry run):" -foreground gray35
        ttk::frame $w.f.p
        text $w.f.p.t -width 80 -height 10 -font TkFixedFont -wrap none -state disabled \
            -yscrollcommand [list $w.f.p.y set]
        ttk::scrollbar $w.f.p.y -command [list $w.f.p.t yview]
        grid $w.f.p.t $w.f.p.y -sticky news
        grid columnconfigure $w.f.p 0 -weight 1
        grid rowconfigure $w.f.p 0 -weight 1
        grid $w.f.pl - - -sticky w -pady {8 2}
        grid $w.f.p - - -sticky news
        grid rowconfigure $w.f [dict get [grid info $w.f.p] -row] -weight 1
        set formPreview($w) $preview
        trace add variable f write [list ui::FormChanged $w]
        PreviewNow $w
    }
    ttk::frame $w.f.buttons
    buttons $w.f.buttons $ok [list set $doneVar ok] [list set $doneVar cancel]
    grid $w.f.buttons - - -sticky e -pady {10 0}
    bind $w <Return> [list set $doneVar ok]
    bind $w <Escape> [list set $doneVar cancel]
    wm protocol $w WM_DELETE_WINDOW [list set $doneVar cancel]
    set first [lindex [lmap c [winfo children $w.f] {
        if {[winfo class $c] in {TEntry TCombobox}} { set c } else continue }] 0]
    if {$first ne ""} { focus $first }
    # (Modal: the main window waits.  An answer given meanwhile is kept.)
    set done ""
    catch {tkwait visibility $w}
    catch {grab $w}
    try {
        while 1 {
            if {$done eq ""} { vwait $doneVar }
            if {$done ne "ok"} { return 0 }
            set problem [expr {$validate eq "" ? "" : [uplevel #0 [list {*}$validate $w]]}]
            if {$problem eq ""} break
            set done ""
            if {$problem ne "-"} {
                tk_messageBox -parent $w -icon info -title $title -message $problem
            }
        }
    } finally {
        if {$preview ne ""} {
            trace remove variable f write [list ui::FormChanged $w]
            after cancel [list ui::PreviewNow $w]
            unset -nocomplain formPreview($w)
        }
        catch {grab release $w}
        destroy $w
        set formOpen ""
    }
    return 1
}

proc ui::formBusy {} {
    variable formOpen
    if {$formOpen eq "" || ![winfo exists $formOpen]} { return 0 }
    wm deiconify $formOpen
    raise $formOpen
    bell
    return 1
}

proc ui::Browse {w array key kind types} {
    upvar #0 $array f
    switch -- $kind {
        save { set path [tk_getSaveFile -parent $w -filetypes $types -initialfile [file tail $f($key)]] }
        open { set path [tk_getOpenFile -parent $w -filetypes $types] }
        dir  { set path [tk_chooseDirectory -parent $w] }
    }
    if {$path ne ""} { set f($key) $path }
}

proc ui::FormChanged {w args} {
    later [list ui::PreviewNow $w]
}

proc ui::PreviewNow {w} {
    variable formPreview
    if {![winfo exists $w.f.p.t] || ![info exists formPreview($w)]} return
    setText $w.f.p.t [string trim [uplevel #0 [list {*}$formPreview($w) $w]]]
}
