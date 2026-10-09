# Context menus of the lists: a right-click on a row (Control-click on
# macOS too) selects it and posts a menu filled by the list's builder.
# The entries are mostly the window's own buttons and menu entries (the
# same labels, states and actions), so the menu and the window agree.
#
#   popup::attach W BUILDER   W: a ttk::treeview or a listbox; BUILDER is
#                             called with the menu and the row (the item
#                             of a treeview, the index of a listbox)
#   popup::button M B ?LABEL? an entry for the button B (its state, its
#                             command)
#   popup::menuEntries M SRC  the command entries and separators of SRC
#   popup::copy M LABEL TEXT  an entry copying TEXT to the clipboard
#   popup::column             the column of the row clicked (treeviews)
#   popup::default M LABEL    the entry LABEL of M in bold: what a
#                             double-click on the row does
#   popup::fill M BUILDER ROW the menu M of the menu bar emptied and filled
#                             by BUILDER for ROW (or "" for none), as the
#                             context menu: each action of the list is in
#                             the menu bar too, but what only changes the
#                             rows of the list (filters)
#   popup::inBar              true while popup::fill fills: builders leave
#                             out the filters then

namespace eval popup {
    variable column ""
    variable bar 0
}

proc popup::attach {w builder} {
    bind $w <ButtonPress-3> [list +popup::post $w $builder %x %y %X %Y]
    if {[tk windowingsystem] eq "aqua"} {
        bind $w <ButtonPress-2> [list +popup::post $w $builder %x %y %X %Y]
        bind $w <Control-ButtonPress-1> [list +popup::post $w $builder %x %y %X %Y]
    }
}

proc popup::post {w builder x y X Y} {
    variable column
    if {[winfo class $w] eq "Listbox"} {
        if {![$w size]} return
        set row [$w nearest $y]
        $w selection clear 0 end
        $w selection set $row
        $w activate $row
        event generate $w <<ListboxSelect>>
    } else {
        # (A heading: its own menu, of the columns.)
        if {[$w identify region $x $y] ni {cell tree}} return
        set row [$w identify item $x $y]
        if {$row eq ""} return
        set c [$w identify column $x $y]
        set column [lindex [$w cget -displaycolumns] [expr {[string range $c 1 end] - 1}]]
        if {$column eq "#all"} { set column [lindex [$w cget -columns] [expr {[string range $c 1 end] - 1}]] }
        if {$row ni [$w selection]} { $w selection set [list $row] }
        $w focus $row
    }
    # (The window takes in the selection: its buttons.)
    update
    set m $w.popup
    destroy $m
    menu $m -tearoff 0
    uplevel #0 [list {*}$builder $m $row]
    # (No separator at the end.)
    while {[$m index end] ne "none" && [$m type end] eq "separator"} { $m delete end }
    if {[$m index end] ne "none"} { tk_popup $m $X $Y }
}

proc popup::fill {m builder row} {
    variable bar
    $m delete 0 end
    set bar 1
    try {
        uplevel #0 [list {*}$builder $m $row]
    } finally {
        set bar 0
    }
    while {[$m index end] ne "none" && [$m type end] eq "separator"} { $m delete end }
    # (Nothing in bold here: that is the double-click of a row.)
    if {[$m index end] eq "none"} return
    for {set i 0} {$i <= [$m index end]} {incr i} {
        if {[$m type $i] ne "separator"} { $m entryconfigure $i -font {} }
    }
}

proc popup::inBar {} {
    return $::popup::bar
}

proc popup::button {m b {label ""}} {
    if {![winfo exists $b]} return
    if {$label eq ""} { set label [$b cget -text] }
    $m add command -label $label -command [list $b invoke] \
        -state [expr {[$b instate disabled] ? "disabled" : "normal"}]
}

proc popup::menuEntries {m src} {
    for {set i 0} {$i <= [$src index end]} {incr i} {
        switch -- [$src type $i] {
            command {
                $m add command -label [$src entrycget $i -label] \
                    -command [$src entrycget $i -command] -state [$src entrycget $i -state]
            }
            separator { if {[$m index end] ne "none"} { $m add separator } }
        }
    }
}

proc popup::default {m label} {
    if {[$m index end] eq "none"} return
    for {set i 0} {$i <= [$m index end]} {incr i} {
        if {[$m type $i] in {command checkbutton radiobutton cascade}
                && [$m entrycget $i -label] eq $label} {
            $m entryconfigure $i -font [DefaultFont]
            return
        }
    }
}

# The menu font in bold (made once, following TkMenuFont).
proc popup::DefaultFont {} {
    if {"PopupDefaultFont" ni [font names]} {
        font create PopupDefaultFont {*}[font actual TkMenuFont] -weight bold
    }
    return PopupDefaultFont
}

proc popup::copy {m label text} {
    $m add command -label $label -command [list ui::copy $text] \
        -state [expr {$text eq "" ? "disabled" : "normal"}]
}

proc popup::separator {m} {
    if {[$m index end] ne "none" && [$m type end] ne "separator"} { $m add separator }
}
