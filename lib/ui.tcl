# The dialogs and small things of every window, in one way.  New code uses
# these, not tk_messageBox, toplevel, clipboard or vwait of its own:
#
#   ui::confirm ?-parent W? ?-title T? ?-icon I? ?-default D? MESSAGE ?DETAIL?
#                               OK or Cancel (Cancel the default): 1 if OK
#   ui::ask ?-parent W? ?-title T? ?-icon I? ?-default D? MESSAGE ?DETAIL?
#                               Yes or No: 1 if Yes
#   ui::askCancel ?-parent W? ?-title T? ?-icon I? ?-default D? MESSAGE ?DETAIL?
#                               yes, no or cancel
#   ui::splitByWeights PW       a ttk::panedwindow whose panes are not left
#                               squeezed (sashes by the panes' weights then)
#   ui::focusIfThere W         focus W if it still exists
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
#   ui::size W COLUMNS LINES    the window W that many characters and lines
#                               of the default font, at most 90% of the screen
#   ui::zoomText STEP           the size of the text in every text widget:
#                               a step larger (1), smaller (-1), 100% (0)
#   ui::textSize ?FACTOR?       that size (1 is 100%): to keep in settings
#   ui::whenTextSize SCRIPT     SCRIPT run when that size changes (what is
#                               drawn in that size, as charts)

namespace eval ui {
    variable f                  ;# array: the fields of a form (by default)
    variable done ""            ;# ok or cancel: a form's answer (by default)
    variable formOpen ""        ;# the form open (one at a time)
    variable formPreview        ;# array: form -> the command of its preview
    variable textSizes {0.5 0.67 0.8 0.9 1 1.1 1.25 1.5 1.75 2 2.5 3}
    variable textSize 1         ;# of the text widgets (one of textSizes)
    variable zoomed             ;# array: text -> dict {TAG OPTION} -> {ORIGINAL SET}
    variable wheel 0            ;# Ctrl+Wheel turned short of a step
    variable sizeScripts {}     ;# run when the text size changes
}

# A line selected in a text ends in its newline, and an entry pasted it
# as it was ("abc\n" for a title): entries get their paste in one line.
# (Every paste of Tk's entries, the clipboard and the middle button, ttk
# or not, goes through tk::GetSelection.)
if {[info commands ::ui::RealGetSelection] eq ""} {
    rename ::tk::GetSelection ::ui::RealGetSelection
    proc ::tk::GetSelection {w sel} {
        set text [::ui::RealGetSelection $w $sel]
        if {[winfo class $w] in {TEntry TCombobox TSpinbox Entry Spinbox}} {
            set text [string map {\r\n " " \n " " \r " "} [string trim $text \r\n]]
        }
        return $text
    }
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

# A question of three answers: yes, no or cancel.
proc ui::askCancel {args} {
    Box question yesnocancel $args
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
    set title [if {[dict exists $args -title]} {dict get $args -title} else {string cat "Tktaalik"}]
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

# Waiting for something: the windows busy (tk busy), the watch cursor
# over all of each, text and entries too, and clicks ignored until done.
#
#   ui::busy SCRIPT         SCRIPT run in the caller with all the windows
#                           shown busy, the keys ignored too (its return,
#                           break or error passed on)
#   ui::busyHold ?WINDOWS?  WINDOWS (default: the main window and the other
#                           toplevels shown) busy: those held, for
#   ui::busyRelease HELD    after (for what goes on in the background)
#   ui::progress TEXT       TEXT over the middle of the main window, drawn
#                           at once, for a wait that blocks it (with
#                           ui::busy); "" removes it
proc ui::busy {script} {
    set held [busyHold]
    # The keys too: SCRIPT may handle events while it waits (web::), and a
    # Return must not post twice.  They go to the busy window, which has
    # no bindings (not even those of its toplevel).
    set focus [focus]
    set busyWin ""
    if {$focus ne "" && [set top [winfo toplevel $focus]] in $held} {
        set busyWin [expr {$top eq "." ? "._Busy" : "$top._Busy"}]
        if {[winfo exists $busyWin]} {
            bindtags $busyWin [list $busyWin]
            focus $busyWin
        } else {
            set busyWin ""
        }
    }
    set code [catch {uplevel 1 $script} result opts]
    busyRelease $held
    # (Released, the busy window passes the focus to its toplevel.)
    if {$busyWin ne "" && [winfo exists $focus] && [focus] in [list $busyWin $top ""]} { focus $focus }
    if {$code == 1} {
        dict incr opts -level
        return -options $opts $result
    }
    return -code $code $result
}

proc ui::busyHold {{windows ""}} {
    if {$windows eq ""} { set windows [linsert [wm stackorder .] 0 .] }
    set held {}
    foreach w [lsort -unique $windows] {
        # (Not one held already, by a busy that this one is within: it
        # releases it.)
        if {![winfo exists $w] || [tk busy status $w]} continue
        if {![catch {tk busy hold $w -cursor watch}]} { lappend held $w }
    }
    update idletasks
    return $held
}

proc ui::busyRelease {held} {
    foreach w $held { catch {tk busy forget $w} }
}

# (Only idle tasks handled: the events wait, and a click on a busy window
# goes nowhere.)
proc ui::progress {text} {
    set w .uiProgress
    if {$text eq ""} {
        destroy $w
        return
    }
    if {![winfo exists $w]} {
        ttk::frame $w -relief solid -borderwidth 1 -padding {16 10}
        ttk::label $w.l
        pack $w.l
    }
    $w.l configure -text $text
    place $w -in . -relx 0.5 -rely 0.5 -anchor center
    raise $w
    update idletasks
}

# Focus W if it is still there (for "after idle": a dialog can be gone by
# then, answered at once).
proc ui::focusIfThere {w} {
    if {[winfo exists $w]} { focus $w }
}

# A ttk::panedwindow PW whose panes do not stay squeezed: when it is
# resized (after the layout), a pane of less than 30 pixels where there is
# room for all puts the sashes where the panes' weights say.  (On Windows,
# on a small screen, the Tickets list was 1 pixel high for good.)
proc ui::splitByWeights {pw} {
    bind $pw <Configure> [list after idle [list ui::Unsqueeze $pw]]
}

proc ui::Unsqueeze {pw} {
    if {![winfo exists $pw]} return
    set panes [$pw panes]
    if {[llength $panes] < 2} return
    set vertical [expr {[$pw cget -orient] eq "vertical"}]
    set size [expr {$vertical ? [winfo height $pw] : [winfo width $pw]}]
    if {$size < 60 * [llength $panes]} return
    # (The sizes by the sashes: a pane squeezed to nothing is unmapped and
    # keeps its old size.)
    set sashes [lmap i [lrange [lsearch -all $panes *] 1 end] { $pw sashpos [expr {$i - 1}] }]
    set edges [list 0 {*}$sashes $size]
    set small 0
    for {set i 0} {$i < [llength $panes]} {incr i} {
        if {[lindex $edges [expr {$i + 1}]] - [lindex $edges $i] < 30} { set small 1 }
    }
    if {!$small} return
    set weights [lmap p $panes { expr {max(1, [$pw pane $p -weight])} }]
    set total [tcl::mathop::+ {*}$weights]
    set at 0.0
    for {set i 0} {$i < [llength $panes] - 1} {incr i} {
        set at [expr {$at + $size * double([lindex $weights $i]) / $total}]
        $pw sashpos $i [expr {int($at)}]
    }
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

# A size in pixels fits one font size only: with large fonts or a large
# scaling the window was too small for what is in it.
proc ui::size {w columns lines} {
    set width [expr {$columns * [font measure TkDefaultFont 0]}]
    set height [expr {$lines * [font metrics TkDefaultFont -linespace]}]
    set width [expr {min($width, [winfo screenwidth $w] * 9 / 10)}]
    set height [expr {min($height, [winfo screenheight $w] * 9 / 10)}]
    wm geometry $w ${width}x$height
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

# ------------------------------------------------------------ text size

# Ctrl+plus, Ctrl+minus and Ctrl+Wheel in a text widget make the text of
# all of them larger or smaller, Ctrl+0 100% (Ctrl+0 elsewhere is a tab:
# break).  The fonts of the widget and of its tags are scaled, and the
# tabs and margins in pixels with them; the text filled anew (new tags,
# fonts set again) is scaled when its lines are laid out
# (<<WidgetViewSync>>).
proc ui::zoomText {step} {
    variable textSizes
    variable textSize
    set i [lsearch -exact $textSizes $textSize]
    if {$step == 0} {
        set i [lsearch -exact $textSizes 1]
    } elseif {$i + $step < 0 || $i + $step >= [llength $textSizes]} {
        return
    } else {
        incr i $step
    }
    textSize [lindex $textSizes $i]
}

proc ui::textSize {args} {
    variable textSizes
    variable textSize
    variable zoomed
    if {[llength $args]} {
        set size [lindex $args 0]
        if {$size ni $textSizes} { set size 1 }
        set textSize $size
        foreach w [array names zoomed] {
            if {![winfo exists $w]} { unset zoomed($w) }
        }
        foreach w [TextWidgets .] { ZoomIn $w }
        foreach script $::ui::sizeScripts { uplevel #0 $script }
    }
    return $textSize
}

proc ui::whenTextSize {script} {
    variable sizeScripts
    if {$script ni $sizeScripts} { lappend sizeScripts $script }
}

proc ui::TextWidgets {w} {
    set found [if {[winfo class $w] eq "Text"} { list $w }]
    foreach c [winfo children $w] { lappend found {*}[TextWidgets $c] }
    return $found
}

# The text widget W in the size chosen: its options that are not as they
# were set last are new originals.
proc ui::ZoomIn {w} {
    variable textSize
    variable zoomed
    if {![winfo exists $w]} return
    if {$textSize == 1 && ![info exists zoomed($w)]} return
    set d [if {[info exists zoomed($w)]} { set zoomed($w) }]
    set new {}
    foreach tag [list "" {*}[$w tag names]] {
        foreach opt {-font -tabs -lmargin1 -lmargin2 -rmargin} {
            if {$tag eq ""} {
                if {$opt ni {-font -tabs}} continue
                set value [$w cget $opt]
            } else {
                set value [$w tag cget $tag $opt]
            }
            set key [list $tag $opt]
            if {[dict exists $d $key] && [lindex [dict get $d $key] 1] eq $value} {
                set orig [lindex [dict get $d $key] 0]
            } elseif {$value eq ""} {
                continue
            } else {
                set orig $value
            }
            set scaled [Scaled $opt $orig]
            if {$scaled ne $value} {
                if {$tag eq ""} {
                    $w configure $opt $scaled
                    set scaled [$w cget $opt]
                } else {
                    $w tag configure $tag $opt $scaled
                    set scaled [$w tag cget $tag $opt]
                }
            }
            if {$textSize != 1} { dict set new $key [list $orig $scaled] }
        }
    }
    if {[dict size $new]} {
        set zoomed($w) $new
    } else {
        unset -nocomplain zoomed($w)
    }
}

# VALUE of OPT (a font, or distances) in the size chosen.
proc ui::Scaled {opt value} {
    variable textSize
    if {$textSize == 1} { return $value }
    if {$opt eq "-font"} {
        set font [font actual $value]
        set size [dict get $font -size]
        set scaled [expr {max(1, round(abs($size) * $textSize))}]
        dict set font -size [expr {$size < 0 ? -$scaled : $scaled}]
        return $font
    }
    # (Distances in pixels; with units, such as 2c, and the alignments of
    # tabs, as they are.)
    lmap v $value {
        if {[string is double -strict $v]} { expr {round($v * $textSize)} } else { set v }
    }
}

proc ui::ZoomWheel {delta} {
    variable wheel
    # (A step for each notch, 120; a touchpad sends less, more often.)
    set wheel [expr {$wheel + $delta}]
    while {abs($wheel) >= 120} {
        zoomText [expr {$wheel > 0 ? 1 : -1}]
        set wheel [expr {$wheel > 0 ? $wheel - 120 : $wheel + 120}]
    }
}

foreach key {Control-plus Control-equal Control-KP_Add} {
    bind Text <$key> {ui::zoomText 1; break}
}
foreach key {Control-minus Control-KP_Subtract} {
    bind Text <$key> {ui::zoomText -1; break}
}
bind Text <Control-0> {ui::zoomText 0; break}
bind Text <Control-MouseWheel> {ui::ZoomWheel %D; break}
# (Tk 8.6 on X11: the wheel is buttons 4 and 5.)
if {![package vsatisfies [package provide Tk] 9] && [tk windowingsystem] eq "x11"} {
    bind Text <Control-Button-4> {ui::zoomText 1; break}
    bind Text <Control-Button-5> {ui::zoomText -1; break}
}
bind Text <<WidgetViewSync>> {ui::ZoomIn %W}
bind Text <Map> {ui::ZoomIn %W}
bind Text <Destroy> {unset -nocomplain ::ui::zoomed(%W)}
unset key
