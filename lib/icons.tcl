# Icons for the buttons of tktaalik, and the buttons with them.
#
#   icons::get NAME ?row?        the image (search, save, clear, help; for
#                                tickets st-*, pr-*, sv-*; for the timeline
#                                k-*), in the size that suits the default
#                                font, or with "row" a table row
#   icons::button W NAME TIP CMD a ttk::button with the icon and a tooltip
#   icons::appIcon               the application icon, for all windows
#   icons::tooltip W TEXT        a tooltip for any widget
#   icons::tipLater W TEXT ?X Y? show a tooltip after a moment: below W, or
#                                at the screen position X Y (for a part of
#                                W, like a table cell); icons::tipHide
#
# The icons are PNG files (Tk 8.6 has no SVG) in icons/, in 16, 24 and 32
# pixels, drawn by tools/make-icons.py.

namespace eval icons {
    variable images {}          ;# name -> image
    variable tipAfter ""        ;# the pending tooltip
    # The PNG files: icons/NAME-SIZE.png, drawn by tools/make-icons.py.
    variable dir [file normalize [file join [file dirname [info script]] .. icons]]
}

proc icons::size {} {
    set line [font metrics TkDefaultFont -linespace]
    expr {$line <= 19 ? 16 : $line <= 27 ? 24 : 32}
}

# The size of an icon in a table row (a line of the default font).
proc icons::rowSize {} {
    set line [font metrics TkDefaultFont -linespace]
    expr {$line <= 22 ? 16 : $line <= 30 ? 24 : 32}
}

proc icons::get {name {where button}} {
    variable images
    variable dir
    set size [expr {$where eq "row" ? [rowSize] : [size]}]
    if {![dict exists $images $name-$size]} {
        dict set images $name-$size [image create photo -format png \
            -file [file join $dir $name-$size.png]]
    }
    dict get $images $name-$size
}

# The application's icon, for all windows: every size, the window manager
# picks.
proc icons::appIcon {} {
    variable dir
    set images [lmap n {256 128 64 48 32 24 16} {
        image create photo -format png -file [file join $dir tktaalik-$n.png]
    }]
    wm iconphoto . -default {*}$images
}

proc icons::button {w name tip command} {
    ttk::style configure Icon.TButton -padding {6 2}
    ttk::button $w -image [get $name] -style Icon.TButton -width 0 -command $command
    tooltip $w $tip
    return $w
}

# ---------------------------------------------------------------- tooltips

proc icons::tooltip {w text} {
    bind $w <Enter> [list icons::tipLater $w $text]
    bind $w <Leave> icons::tipHide
    bind $w <ButtonPress> icons::tipHide
}

proc icons::tipLater {w text {X ""} {Y ""}} {
    variable tipAfter
    after cancel $tipAfter
    set tipAfter [after 600 [list icons::tipShow $w $text $X $Y]]
}

proc icons::tipShow {w text {X ""} {Y ""}} {
    if {![winfo exists $w]} return
    set t .iconsTip
    destroy $t
    toplevel $t -background gray30 -borderwidth 0
    wm overrideredirect $t 1
    catch {wm attributes $t -type tooltip}
    label $t.l -text $text -justify left -background #ffffe0 -foreground black -padx 6 -pady 2 \
        -font TkTooltipFont
    pack $t.l -padx 1 -pady 1
    # Below the widget, or the pointer; on the screen.
    update idletasks
    if {$X eq ""} {
        set X [winfo rootx $w]
        set y [expr {[winfo rooty $w] + [winfo height $w] + 2}]
    } else {
        set y [expr {$Y + 20}]
    }
    set x [expr {min($X, [winfo screenwidth $w] - [winfo reqwidth $t])}]
    wm geometry $t +[expr {max($x, 0)}]+$y
}

proc icons::tipHide {} {
    variable tipAfter
    after cancel $tipAfter
    destroy .iconsTip
}
