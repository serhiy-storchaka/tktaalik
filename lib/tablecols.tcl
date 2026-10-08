# Treeview columns the user can sort, show, hide and move, for the tabs of
# tktaalik (Tickets, Branches).
#
# A click on a heading sorts by its column, a second click reverses the
# order.  A right-click on a heading opens a pop-up with a checkbox for
# each column, which stays open and changes the table at once (a column
# shown goes after the one right-clicked), then the sort orders of the
# column and "Default columns".  Dragging a heading
# moves its column.  The rows are sorted here, by the values given to
# tablecols::fill, or by the caller (-sortcommand), e.g. with a query.
#
#   tablecols::setup TREE COLUMNS ?OPTION VALUE...?
#       COLUMNS: a dict key -> {heading TEXT ?width CHARS? ?stretch 0|1?
#       ?type dictionary|integer|real? ?dir asc|desc? ?anchor w|center|e?
#       ?extra {KEY HEADING DIR}? ?icon IMAGE? ?tip TEXT? ?pixels N?}.  An
#       icon column shows IMAGE as its heading instead of the text, and the
#       heading has a tooltip (TEXT, or the heading text) instead; other
#       columns have the tooltip TEXT if given.  pixels is a width in
#       pixels.  "extra" is a second sort key for what
#       the column also shows (Status: the resolution); while the table is
#       sorted by it, the heading says "Status / Resolution \u25b2".
#       Options: -fixed KEYS (always shown, but movable), -defaults KEYS
#       (shown by default), -shown KEYS, -order KEYS, -defaultorder KEYS
#       (the order without a saved one, and after "Default columns"; else
#       the fixed columns come first), -sort {KEY DIR},
#       -command SCRIPT (run after the user has changed the columns or the
#       sorting), -sortcommand SCRIPT (sorts the rows instead: run after the
#       sort order has changed, which tablecols::state tells), -celltip
#       SCRIPT (called with the item and the column key: the tooltip of a
#       cell, "" for none).
#       Can be called again: with other columns, for another repository.
#   tablecols::fill TREE ROWS
#       ROWS: a list of {ID CELLS ?SORTVALUES? ?TAGS?}, CELLS and SORTVALUES
#       dicts key -> value; a cell sorts by its sort value if it has one.
#       With -sortcommand, the rows are shown in the order given.
#   tablecols::state TREE   -> dict {shown KEYS order KEYS sort {KEY DIR}}
#   tablecols::setSort TREE KEY DIR
#       The sort order as the rows are sorted elsewhere: only the headings.
#   tablecols::fit TREE
#       The stretchable columns resized so that the columns fill the window
#       (done when it is first shown and when columns are shown or hidden).

namespace eval tablecols {
    variable columns    ;# array: tree -> the dict of columns
    variable fixed      ;# array: tree -> keys always shown
    variable defaults   ;# array: tree -> keys shown by default
    variable shown      ;# array: tree -> other keys shown, in order
    variable order      ;# array: tree -> the display order of all keys
    variable defaultOrder ;# array: tree -> the order by default
    variable sort       ;# array: tree -> {key dir}
    variable command    ;# array: tree -> called after a change
    variable sortcommand ;# array: tree -> sorts the rows, or ""
    variable sortvalue  ;# array: tree,id -> dict key -> sort value
    variable on         ;# array: tree,key -> its checkbox
    variable fitted     ;# array: tree -> fitted since setup (tablecols::fit)
    variable drag {}    ;# the heading being dragged
}

proc tablecols::setup {t cols args} {
    variable columns
    variable fixed
    variable defaults
    variable shown
    variable order
    variable sort
    variable command
    variable sortcommand
    set opts [dict merge {
        -fixed {} -defaults {} -shown {} -order {} -defaultorder {} -sort {} -command {}
        -sortcommand {} -celltip {}
    } $args]
    set columns($t) $cols
    set keys [dict keys $cols]
    set fixed($t) [lmap k [dict get $opts -fixed] { if {$k ni $keys} continue; set k }]
    set defaults($t) [lmap k [dict get $opts -defaults] { if {$k ni $keys} continue; set k }]
    if {![llength $defaults($t)]} { set defaults($t) [others $t $keys] }
    set shown($t) [lmap k [dict get $opts -shown] {
        if {$k ni $keys || $k in $fixed($t)} continue
        set k
    }]
    if {![llength [dict get $opts -shown]]} { set shown($t) [others $t $defaults($t)] }
    variable defaultOrder
    set defaultOrder($t) [dict get $opts -defaultorder]
    set order($t) [dict get $opts -order]
    if {![llength $order($t)]} { set order($t) $defaultOrder($t) }
    lassign [dict get $opts -sort] key dir
    if {![dict exists [sortKeys $t] $key]} { set key [lindex $fixed($t) 0] }
    if {$key eq ""} { set key [lindex $keys 0] }
    if {$dir ni {asc desc}} { set dir [dict get [sortKeys $t] $key dir] }
    set sort($t) [list $key $dir]
    set command($t) [dict get $opts -command]
    set sortcommand($t) [dict get $opts -sortcommand]
    variable celltip
    set celltip($t) [dict get $opts -celltip]

    $t delete [$t children {}]
    # The old displayed columns may be gone.
    $t configure -displaycolumns #all
    $t configure -columns $keys -show headings
    set char [font measure TkDefaultFont 0]
    foreach key $keys {
        $t heading $key -anchor w -command [list tablecols::sortBy $t $key]
        set width [expr {[option $t $key width 10] * $char}]
        set pixels [option $t $key pixels ""]
        if {$pixels ne ""} { set width $pixels }
        set stretch [option $t $key stretch 0]
        $t column $key -width $width -stretch $stretch -anchor [option $t $key anchor w] \
            -minwidth [expr {$pixels ne "" ? $pixels : $stretch ? $width * 2 / 3 : 20}]
    }
    display $t
    foreach {key spec} $cols {
        if {[dict exists $spec icon]} { imageFirst; break }
    }
    headings $t
    # The widths just set: fitted to the window when it is shown (now, if
    # it is).
    variable fitted
    set fitted($t) 0
    if {[winfo ismapped $t]} { after idle [list tablecols::firstFit $t] }

    if {![winfo exists [mark $t]]} {
        # A mark where a dragged column would go.
        frame [mark $t] -background #4a6984 -width 3
        catch {[mark $t] configure -background [ttk::style lookup Treeview -selectbackground]}
        # The press only remembers the heading: a click still sorts.
        bind $t <ButtonPress-1> {+tablecols::dragStart %W %x %y}
        bind $t <B1-Motion> {+tablecols::dragMotion %W %x %y}
        bind $t <ButtonRelease-1> {+tablecols::dragEnd %W %x %y}
        # Tooltips: of icon headings, and of cells (-celltip).
        bind $t <Map> {+tablecols::firstFit %W}
        bind $t <Motion> {+tablecols::motion %W %x %y %X %Y}
        bind $t <Leave> {+tablecols::tipOff %W}
        bind $t <ButtonPress> {+tablecols::tipOff %W}
        if {[tk windowingsystem] eq "aqua"} {
            bind $t <ButtonPress-2> {+tablecols::rightClick %W %x %y %X %Y}
            bind $t <Control-ButtonPress-1> {+tablecols::rightClick %W %x %y %X %Y}
        } else {
            bind $t <ButtonPress-3> {+tablecols::rightClick %W %x %y %X %Y}
        }
        ttk::style configure Item.Toolbutton -anchor w -padding {4 2}
    }
}

# The keys of $keys that are not fixed.
proc tablecols::others {t keys} {
    variable fixed
    lmap k $keys { if {$k in $fixed($t)} continue; set k }
}

proc tablecols::option {t key name default} {
    variable columns
    set col [dict get $columns($t) $key]
    expr {[dict exists $col $name] ? [dict get $col $name] : $default}
}

# The sort keys: key -> {heading TEXT dir DIR column KEY}, the columns and
# their extra keys.
proc tablecols::sortKeys {t} {
    variable columns
    set keys {}
    dict for {key col} $columns($t) {
        dict set keys $key [dict create heading [option $t $key heading $key] \
            dir [option $t $key dir asc] column $key]
        if {[dict exists $col extra]} {
            lassign [dict get $col extra] x heading dir
            dict set keys $x [dict create heading $heading \
                dir [expr {$dir eq "" ? "asc" : $dir}] column $key]
        }
    }
    return $keys
}

proc tablecols::mark {t} {
    return [winfo parent $t].tablecolsMark
}

proc tablecols::state {t} {
    variable shown
    variable sort
    dict create shown $shown($t) order [$t cget -displaycolumns] sort $sort($t)
}

proc tablecols::changed {t} {
    variable command
    if {$command($t) ne ""} { uplevel #0 $command($t) }
}

# ----------------------------------------------------------------- rows

proc tablecols::fill {t rows} {
    variable sortvalue
    array unset sortvalue $t,*
    $t delete [$t children {}]
    set keys [$t cget -columns]
    foreach row $rows {
        lassign $row id cells sorts tags
        $t insert {} end -id $id -tags $tags \
            -values [lmap k $keys { expr {[dict exists $cells $k] ? [dict get $cells $k] : ""} }]
        if {[dict size $sorts]} { set sortvalue($t,$id) $sorts }
    }
    variable sortcommand
    if {$sortcommand($t) eq ""} { sortRows $t }
}

proc tablecols::value {t id key} {
    variable sortvalue
    if {[info exists sortvalue($t,$id)] && [dict exists $sortvalue($t,$id) $key]} {
        return [dict get $sortvalue($t,$id) $key]
    }
    $t set $id $key
}

# Sort the rows; empty values last in both directions.
proc tablecols::sortRows {t} {
    variable sort
    lassign $sort($t) key dir
    set type [option $t $key type dictionary]
    set full {}
    set empty {}
    foreach id [$t children {}] {
        set v [value $t $id $key]
        if {$v eq "" || ($type ne "dictionary" && ![string is $type -strict $v])} {
            lappend empty $id
        } else {
            lappend full [list $v $id]
        }
    }
    set ids [lmap pair [lsort -$type -index 0 \
        [expr {$dir eq "asc" ? "-increasing" : "-decreasing"}] $full] { lindex $pair 1 }]
    set i 0
    foreach id [concat $ids $empty] { $t move $id {} $i; incr i }
    set sel [lindex [$t selection] 0]
    if {$sel ne ""} { $t see $sel }
}

# ----------------------------------------------------------- sorting

proc tablecols::headings {t} {
    variable sort
    lassign $sort($t) skey dir
    set sorted [dict get [sortKeys $t] $skey]
    set arrow [expr {$dir eq "asc" ? " \u25b2" : " \u25bc"}]
    foreach key [$t cget -columns] {
        set icon [option $t $key icon ""]
        # An icon heading: the image and the arrow (the rest in the tooltip).
        set text [expr {$icon eq "" ? [option $t $key heading $key] : ""}]
        if {$key eq $skey} {
            append text $arrow
        } elseif {[dict get $sorted column] eq $key} {
            # Sorted by what the column also shows.
            if {$icon eq ""} { append text " / [dict get $sorted heading]" }
            append text $arrow
        }
        $t heading $key -text [string trimleft $text] -image $icon
    }
}

# Headings show the image left of the text (the sort arrow), not right as
# in the themes' layout.  Headings without an image look the same.
proc tablecols::imageFirst {} {
    catch {
        set layout [ttk::style layout Heading]
        set new [string map {{Treeheading.image -side right} {Treeheading.image -side left}} $layout]
        if {$new ne $layout} { ttk::style layout Heading $new }
    }
    bind TablecolsTheme <<ThemeChanged>> tablecols::imageFirst
    if {"TablecolsTheme" ni [bindtags .]} { bindtags . [linsert [bindtags .] end TablecolsTheme] }
}

# The tooltip of a heading: its "tip"; for an icon heading also its name,
# and how it is sorted.
proc tablecols::headingTip {t key} {
    variable sort
    set icon [option $t $key icon ""]
    if {$icon eq ""} { return [option $t $key tip ""] }
    set text [option $t $key tip [option $t $key heading $key]]
    lassign $sort($t) skey dir
    set sorted [dict get [sortKeys $t] $skey]
    if {[dict get $sorted column] eq $key} {
        append text "\nsorted by [dict get $sorted heading], [expr {$dir eq "asc" ? "ascending" : "descending"}]"
    }
    return $text
}

# The pointer moved: the tooltip of the heading or cell under it, after a
# moment (lib/icons.tcl), if it has one.
proc tablecols::motion {t x y X Y} {
    variable tipAt
    variable celltip
    if {[info commands ::icons::tipLater] eq ""} return
    set region [$t identify region $x $y]
    set column [$t identify column $x $y]
    set key [lindex [$t cget -displaycolumns] [string range $column 1 end]-1]
    set text ""
    if {$region eq "heading" && $key ne ""} {
        set at [list heading $key]
        set text [headingTip $t $key]
    } elseif {$region eq "cell" && $key ne "" && $celltip($t) ne ""} {
        set item [$t identify item $x $y]
        set at [list cell $item $key]
        set text [uplevel #0 [list {*}$celltip($t) $item $key]]
    } else {
        set at ""
    }
    if {[info exists tipAt($t)] && $tipAt($t) eq $at} return
    set tipAt($t) $at
    icons::tipHide
    if {$text ne ""} { icons::tipLater $t $text $X $Y }
}

proc tablecols::tipOff {t} {
    variable tipAt
    set tipAt($t) ""
    if {[info commands ::icons::tipHide] ne ""} { icons::tipHide }
}

proc tablecols::setSort {t key dir} {
    variable sort
    if {![dict exists [sortKeys $t] $key] || [list $key $dir] eq $sort($t)} return
    set sort($t) [list $key $dir]
    headings $t
}

# Sort by $key (a column or an extra key); a second time in reverse.
proc tablecols::sortBy {t key {dir ""}} {
    variable sort
    variable sortcommand
    if {$dir eq ""} {
        if {$key eq [lindex $sort($t) 0]} {
            set dir [expr {[lindex $sort($t) 1] eq "asc" ? "desc" : "asc"}]
        } else {
            set dir [dict get [sortKeys $t] $key dir]
        }
    }
    set sort($t) [list $key $dir]
    headings $t
    if {$sortcommand($t) eq ""} {
        sortRows $t
    } else {
        uplevel #0 $sortcommand($t)
    }
    changed $t
}

# ----------------------------------------------------------- columns

# The displayed columns: fixed and shown, in the remembered order, new
# ones at the end.
proc tablecols::display {t} {
    variable fixed
    variable shown
    variable order
    set keys [concat $fixed($t) $shown($t)]
    set display [lmap k $order($t) { if {$k ni $keys} continue; set k }]
    foreach k $keys { if {$k ni $display} { lappend display $k } }
    $t configure -displaycolumns $display
}

# A checkbox of the pop-up: hide the column, or show it after the column
# AFTER (the one right-clicked), else at the end, and scroll to it (at the
# end of a wide table it would be out of sight).
proc tablecols::toggle {t key {after ""}} {
    variable shown
    variable on
    variable order
    if {$on($t,$key)} {
        if {$key ni $shown($t)} {
            lappend shown($t) $key
            set display [$t cget -displaycolumns]
            set i [lsearch -exact $display $after]
            set order($t) [expr {$i < 0 ? [concat $display $key] : [linsert $display $i+1 $key]}]
        }
        display $t
        fit $t
        seeColumn $t $key
    } else {
        set shown($t) [lmap k $shown($t) { if {$k eq $key} continue; set k }]
        display $t
        fit $t
    }
    changed $t
}

# Fit the columns to the window: the stretchable ones grow, or shrink down
# to their -minwidth, until the columns shown fill it.  Tk adjusts them
# only when the window is resized (and then only once any overflow or empty
# space is used up), so a column shown would land beyond the right edge and
# a column hidden would leave empty space.
proc tablecols::fit {t} {
    if {![winfo exists $t] || ![winfo ismapped $t]} return
    # The width inside the border: where the first column starts.
    set inset 0
    for {set x 0} {$x < 20} {incr x} {
        if {[$t identify column $x 10] ne ""} { set inset $x; break }
    }
    set display [$t cget -displaycolumns]
    set total 0
    set stretch {}
    foreach c $display {
        incr total [$t column $c -width]
        if {[$t column $c -stretch]} { lappend stretch $c }
    }
    set diff [expr {[winfo width $t] - 2 * $inset - $total}]
    # (Evenly; what one cannot give below its -minwidth, the others do.)
    while {$diff != 0 && [llength $stretch]} {
        set n [llength $stretch]
        set left {}
        foreach c $stretch {
            set part [expr {$diff / $n}]
            incr n -1
            set w [$t column $c -width]
            set new [expr {max([$t column $c -minwidth], $w + $part)}]
            $t column $c -width $new
            incr diff [expr {$w - $new}]
            if {$new != $w + $part} continue
            lappend left $c
        }
        if {[llength $left] == [llength $stretch] && $diff != 0} break
        set stretch $left
    }
    # Tk's own record of the free space is computed again.
    $t configure -displaycolumns $display
}

# Fit the table once after setup, when it is shown (Map), or at once.
proc tablecols::firstFit {t} {
    variable fitted
    if {![info exists fitted($t)] || $fitted($t) || ![winfo ismapped $t]} return
    set fitted($t) 1
    update idletasks
    fit $t
}

# Scroll the table sideways, if needed, so that column KEY is in view.
proc tablecols::seeColumn {t key} {
    update idletasks
    set total 0
    foreach c [$t cget -displaycolumns] {
        if {$c eq $key} { set left $total }
        incr total [$t column $c -width]
    }
    if {![info exists left] || $total <= 0} return
    set right [expr {$left + [$t column $key -width]}]
    lassign [$t xview] first last
    set view [expr {($last - $first) * $total}]
    if {$left < $first * $total} {
        $t xview moveto [expr {double($left) / $total}]
    } elseif {$right > $last * $total} {
        $t xview moveto [expr {max(0.0, double($right) - $view) / $total}]
    }
}

proc tablecols::defaultColumns {t} {
    variable shown
    variable defaults
    variable order
    variable on
    set shown($t) [others $t $defaults($t)]
    variable defaultOrder
    set order($t) $defaultOrder($t)
    foreach key [others $t [$t cget -columns]] { set on($t,$key) [expr {$key in $shown($t)}] }
    display $t
    fit $t
    changed $t
}

# Move column $key to position $pos among the displayed columns.
proc tablecols::moveColumn {t key pos} {
    variable order
    variable shown
    variable fixed
    set display [$t cget -displaycolumns]
    set from [lsearch -exact $display $key]
    if {$pos > $from} { incr pos -1 }
    set new [linsert [lreplace $display $from $from] $pos $key]
    if {$new eq $display} return
    set order($t) $new
    set shown($t) [others $t $new]
    $t configure -displaycolumns $new
    changed $t
}

# ----------------------------------------------------------- dragging

# The displayed columns and their left edges, then the right edge of the
# last one ({"" x}), in the treeview's coordinates.
proc tablecols::columnEdges {t} {
    set cols [$t cget -displaycolumns]
    set total 0
    foreach c $cols { incr total [$t column $c -width] }
    # Where the first column starts: after the border, minus the scrolling.
    set x0 0
    while {$x0 < 10 && [$t identify column $x0 1] ne "#1"} { incr x0 }
    set x [expr {$x0 - round([lindex [$t xview] 0] * $total)}]
    set edges {}
    foreach c $cols {
        lappend edges $c $x
        incr x [$t column $c -width]
    }
    lappend edges "" $x
}

# Where a column dropped at $x goes: {position edge-x}.
proc tablecols::dropTarget {t x} {
    set edges [columnEdges $t]
    set pos 0
    foreach {c left} $edges {
        if {$c eq ""} break
        set right [lindex $edges [expr {2 * $pos + 3}]]
        if {$x < ($left + $right) / 2} { return [list $pos $left] }
        incr pos
    }
    list $pos [dict get $edges ""]
}

proc tablecols::headingKey {t x y} {
    if {[$t identify region $x $y] ne "heading"} return
    set column [$t identify column $x $y]
    lindex [$t cget -displaycolumns] [string range $column 1 end]-1
}

proc tablecols::dragStart {t x y} {
    variable drag
    set drag {}
    set key [headingKey $t $x $y]
    if {$key ne ""} { set drag [dict create key $key x $x moving 0] }
}

proc tablecols::dragMotion {t x y} {
    variable drag
    if {![llength $drag]} return
    if {![dict get $drag moving]} {
        if {abs($x - [dict get $drag x]) < 5} return
        dict set drag moving 1
        $t configure -cursor sb_h_double_arrow
    }
    set edge [lindex [dropTarget $t $x] 1]
    place [mark $t] -in $t -x [expr {$edge - 1}] -y 0 -width 3 -relheight 1
    raise [mark $t]
}

proc tablecols::dragEnd {t x y} {
    variable drag
    if {![llength $drag] || ![dict get $drag moving]} {
        set drag {}
        return
    }
    set key [dict get $drag key]
    set drag {}
    place forget [mark $t]
    $t configure -cursor ""
    # The treeview's own release binding (after this one) would sort.
    foreach c [$t cget -columns] { $t heading $c -command {} }
    after idle [list tablecols::restoreSortCommands $t]
    moveColumn $t $key [lindex [dropTarget $t $x] 0]
}

proc tablecols::restoreSortCommands {t} {
    foreach c [$t cget -columns] { $t heading $c -command [list tablecols::sortBy $t $c] }
}

# ------------------------------------------------------------- pop-up

proc tablecols::rightClick {t x y X Y} {
    set key [headingKey $t $x $y]
    if {$key ne ""} { popup $t $key $X $Y }
}

# Not a menu, because a menu closes when an entry is chosen.
proc tablecols::popup {t key X Y} {
    variable on
    variable shown
    set w .tablecolsPopup
    destroy $w
    toplevel $w -borderwidth 1 -relief solid
    wm overrideredirect $w 1
    wm transient $w [winfo toplevel $t]
    ttk::frame $w.f -padding 4
    pack $w.f -fill both -expand 1
    set first ""
    foreach k [others $t [$t cget -columns]] {
        set on($t,$k) [expr {$k in $shown($t)}]
        ttk::checkbutton $w.f.c$k -text [option $t $k heading $k] \
            -variable tablecols::on($t,$k) -command [list tablecols::toggle $t $k $key]
        pack $w.f.c$k -fill x -padx 2 -pady 1
        if {$first eq ""} { set first $w.f.c$k }
    }
    ttk::separator $w.f.sep
    pack $w.f.sep -fill x -pady 4
    # Sorting by the column, and by what it also shows.
    set keys [list $key]
    if {[option $t $key extra ""] ne ""} { lappend keys [lindex [option $t $key extra ""] 0] }
    set i 0
    foreach k $keys {
        set heading [dict get [sortKeys $t] $k heading]
        foreach {dir label} {asc ascending desc descending} {
            ttk::button $w.f.s$i$dir -style Item.Toolbutton -text "Sort by $heading, $label" \
                -command [list tablecols::popupSort $t $k $dir]
            pack $w.f.s$i$dir -fill x
        }
        incr i
    }
    ttk::button $w.f.default -style Item.Toolbutton -text "Default columns" \
        -command [list tablecols::defaultColumns $t]
    pack $w.f.default -fill x

    # On the screen, below and right of the pointer if there is room.
    update idletasks
    set x [expr {min($X, [winfo screenwidth $w] - [winfo reqwidth $w])}]
    set y [expr {min($Y, [winfo screenheight $w] - [winfo reqheight $w])}]
    wm geometry $w +[expr {max($x, 0)}]+[expr {max($y, 0)}]
    # Closed by Escape or a click outside.
    bind $w <Escape> [list destroy $w]
    bind $w <ButtonPress> [list tablecols::popupClick $w %X %Y]
    tkwait visibility $w
    focus [expr {$first ne "" ? $first : "$w.f.s0asc"}]
    grab $w
}

proc tablecols::popupClick {w X Y} {
    if {$X < [winfo rootx $w] || $X >= [winfo rootx $w] + [winfo width $w]
            || $Y < [winfo rooty $w] || $Y >= [winfo rooty $w] + [winfo height $w]} {
        destroy $w
    }
}

proc tablecols::popupSort {t key dir} {
    destroy .tablecolsPopup
    sortBy $t $key $dir
}
