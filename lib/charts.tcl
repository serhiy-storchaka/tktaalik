# Charts on a canvas, for the Statistics window and the tabs: bars (stacked
# by series, standing or lying), lines through the same categories, a grid
# of cells coloured by their values (a calendar, weekday by hour), and
# small bar images for table cells.  Sizes follow the default font and the
# size of the text (ui::textSize, Ctrl+plus and Ctrl+minus over a chart
# too); hovering a bar or cell shows its values, a click runs the chart's
# command (mostly a search for what it counts), and the context menu
# copies the data or saves the chart as SVG or PostScript.
#
#   charts::bars W ?OPTION VALUE...?
#       W: a canvas (made if it does not exist).  -categories LIST, the
#       labels along the axis; -series {NAME VALUES ...}, a list of values
#       per series, stacked; -keys LIST, what -command gets for each
#       category (the category by default); -horizontal 1, lying bars
#       with the labels on the left; -line 1, lines through the values
#       instead of bars; -title TEXT; -format CMD, a value as text
#       (charts::number; charts::bytes); -command CMD, run with the key
#       and the series clicked ("" between the bars); -colors LIST;
#       -message TEXT, shown when there is nothing to draw; -elide end
#       or middle, where a label too long is cut (middle for paths).
#   charts::grid W ?OPTION VALUE...?
#       -rows LABELS, -columns LABELS (a label "" is not shown), -cells
#       {ROW COLUMN VALUE KEY TIP ...} by index (a cell missing is not
#       drawn; TIP "" for "ROW COLUMN: VALUE"); -title, -format, -command
#       (with the key), -message; -colormap {VALUE COLOUR ...}: values that
#       are kinds, each in its colour (and so in the legend), not amounts.
#   charts::message W TEXT   no chart: TEXT in the middle
#   charts::spark VALUES WIDTH HEIGHT ?COLOR?
#                            a new photo image of VALUES as thin bars
#                            (the caller deletes it)
#   charts::tsv W            the data of the chart: tab-separated lines
#   charts::svg W            the chart as an SVG document
#   charts::colour NAME      a colour of the palette, the same for NAME
#                            every time (branches, users)
#   charts::number N, charts::bytes N   values as text
#   charts::numstat TEXT     the output of "fossil diff --numstat": {FILE
#                            ADDED DELETED ...}, without the total
#   charts::stat T INDEX ADDED DELETED MAX ?TAG?
#                            "+ADDED -DELETED" and bars of their share of
#                            MAX (at most 20 characters), inserted in the
#                            text widget T at INDEX (charts::statTags T first);
#                            with TAG, each after a tab, all with TAG (the
#                            tag with the tab stops of the columns)
#   charts::statImage ADDED DELETED MAX WIDTH HEIGHT
#                            a new photo image of those bars (table cells)

namespace eval charts {
    variable spec               ;# array: canvas -> its options
    variable items              ;# array: canvas -> what its items show
    # Colours told apart also by those who see colours differently
    # (Okabe and Ito).
    variable palette {#0072b2 #e69f00 #009e73 #cc79a7 #56b4e9 #d55e00 #999999 #f0e442}
    variable background white
    variable grid #e4e4e4
    variable hover #eef3fa
    variable empty #ebedf0
    font create ChartFont
    font create ChartTitleFont
}
ui::whenTextSize charts::RedrawAll

# ------------------------------------------------------------- the charts

proc charts::bars {w args} {
    Set $w [dict merge {-categories {} -series {} -keys {} -horizontal 0 -line 0
        -title "" -format charts::number -command "" -colors {} -message "Nothing to show"
        -elide end} \
        $args {-type bars}]
}

proc charts::grid {w args} {
    Set $w [dict merge {-rows {} -columns {} -cells {} -title "" -format charts::number
        -command "" -message "Nothing to show" -colormap {}} $args {-type grid}]
}

proc charts::message {w text} {
    Set $w [dict create -type message -message $text -title ""]
}

proc charts::Set {w options} {
    variable spec
    if {![winfo exists $w]} { Make $w }
    set spec($w) $options
    Draw $w
}

proc charts::Make {w} {
    variable background
    canvas $w -highlightthickness 0 -background $background -width 300 -height 200 \
        -borderwidth 0
    bind $w <Configure> [list ui::later [list charts::Draw $w] 20]
    bind $w <Destroy> [list charts::Forget $w]
    # The text size, as in the texts (lib/ui.tcl); the keys once clicked.
    bind $w <1> [list focus $w]
    foreach key {plus equal KP_Add} { bind $w <Control-$key> {ui::zoomText 1} }
    foreach key {minus KP_Subtract} { bind $w <Control-$key> {ui::zoomText -1} }
    bind $w <Control-Key-0> {ui::zoomText 0; break}
    bind $w <Control-MouseWheel> {ui::ZoomWheel %D; break}
    if {[tk windowingsystem] eq "x11" && ![package vsatisfies [package provide Tk] 9]} {
        bind $w <Control-Button-4> {ui::ZoomWheel 120; break}
        bind $w <Control-Button-5> {ui::ZoomWheel -120; break}
    }
    bind $w <ButtonPress-3> [list charts::Menu $w %X %Y]
    if {[tk windowingsystem] eq "aqua"} {
        bind $w <ButtonPress-2> [list charts::Menu $w %X %Y]
        bind $w <Control-ButtonPress-1> [list charts::Menu $w %X %Y]
    }
}

proc charts::Forget {w} {
    variable spec
    variable items
    unset -nocomplain spec($w) items($w)
}

proc charts::RedrawAll {} {
    variable spec
    foreach w [array names spec] { Draw $w }
}

proc charts::Draw {w} {
    variable spec
    variable items
    if {![winfo exists $w] || ![info exists spec($w)]} return
    $w delete all
    set items($w) {}
    if {[winfo width $w] < 20 || [winfo height $w] < 20} return
    Fonts
    set s $spec($w)
    switch -- [dict get $s -type] {
        bars {
            if {![llength [dict get $s -categories]] || ![llength [dict get $s -series]]} {
                DrawMessage $w [dict get $s -message]
            } else {
                DrawBars $w $s
            }
        }
        grid {
            if {![llength [dict get $s -cells]]} {
                DrawMessage $w [dict get $s -message]
            } else {
                DrawGrid $w $s
            }
        }
        default { DrawMessage $w [dict get $s -message] }
    }
}

# The fonts: the default one in the size of the text (ui::textSize).
proc charts::Fonts {} {
    set f [font actual TkDefaultFont]
    set size [dict get $f -size]
    set new [expr {round($size * [ui::textSize])}]
    if {$new == 0} { set new [expr {$size < 0 ? -1 : 1}] }
    font configure ChartFont {*}$f -size $new
    font configure ChartTitleFont {*}$f -size $new -weight bold
}

proc charts::DrawMessage {w text} {
    $w create text [expr {[winfo width $w] / 2}] [expr {[winfo height $w] / 2}] \
        -text $text -font ChartFont -fill gray45 -justify center \
        -width [expr {[winfo width $w] - 20}]
}

# The title at the top: the y below it.
proc charts::Title {w s} {
    set pad [font measure ChartFont 0]
    set y $pad
    if {[dict get $s -title] ne ""} {
        $w create text $pad $y -text [dict get $s -title] -anchor nw -font ChartTitleFont \
            -state disabled
        set y [expr {$y + [font metrics ChartTitleFont -linespace] + $pad / 2}]
    }
    return $y
}

proc charts::DrawBars {w s} {
    variable items
    variable grid
    set cats [dict get $s -categories]
    set n [llength $cats]
    set names {}; set values {}
    foreach {name list} [dict get $s -series] { lappend names $name; lappend values $list }
    set colors [Colors $s [llength $names]]
    set format [dict get $s -format]
    set line [dict get $s -line]
    set pad [font measure ChartFont 0]
    set ls [font metrics ChartFont -linespace]
    set width [winfo width $w]
    set height [winfo height $w]
    set y0 [Title $w $s]
    if {[llength $names] > 1} { set y0 [Legend $w $y0 $names $colors] }
    # The largest value: of a series for lines, of the stacks for bars.
    set max 0
    for {set i 0} {$i < $n} {incr i} {
        set sum 0
        foreach list $values {
            set v [lindex $list $i]
            if {![string is double -strict $v]} continue
            if {$line} { set max [expr {max($max, $v)}] } else { set sum [expr {$sum + max($v, 0)}] }
        }
        if {!$line} { set max [expr {max($max, $sum)}] }
    }
    lassign [Ticks $max] step top
    set ticks {}
    for {set t 0} {$t <= $top + $step / 2.0} {set t [expr {$t + $step}]} { lappend ticks $t }
    set tickWidth 0
    foreach t $ticks { set tickWidth [expr {max($tickWidth, [font measure ChartFont [{*}$format $t]])}] }

    if {[dict get $s -horizontal]} {
        set labelWidth 0
        foreach c $cats { set labelWidth [expr {max($labelWidth, [font measure ChartFont $c])}] }
        set labelWidth [expr {min($labelWidth, $width * 35 / 100)}]
        set left [expr {$pad + $labelWidth + $pad / 2}]
        set right [expr {$width - $pad - [font measure ChartFont [{*}$format $max]] - $pad}]
        set right [expr {max($right, $left + 10)}]
        set bottom [expr {$height - $pad - $ls}]
        # (A few bars at the top, not spread over the height.)
        set slot [expr {min(($bottom - $y0) / double($n), $ls * 1.8)}]
        set bottom [expr {$y0 + $slot * $n}]
        set thick [expr {min($slot * 0.75, $ls * 1.2)}]
        set scale [expr {($right - $left) / double($top)}]
        for {set i 0} {$i < $n} {incr i} {
            set y [expr {$y0 + $i * $slot}]
            $w create rectangle 0 $y $width [expr {$y + $slot}] -fill [$w cget -background] \
                -outline "" -tags [list col col$i]
            Bind $w col$i $i ""
        }
        foreach t $ticks {
            set x [expr {$left + $t * $scale}]
            $w create line $x $y0 $x $bottom -fill $grid -state disabled
            $w create text $x [expr {$bottom + 2}] -text [{*}$format $t] -anchor n \
                -font ChartFont -fill gray35 -state disabled
        }
        # (Rows thinner than a line: every other label, and value.)
        set every [expr {max(1, int(ceil($ls * 0.9 / $slot)))}]
        for {set i 0} {$i < $n} {incr i} {
            set y [expr {$y0 + ($i + 0.5) * $slot}]
            set labelled [expr {$i % $every == 0}]
            if {$labelled} {
                $w create text [expr {$left - $pad / 2}] $y -anchor e -font ChartFont -state disabled \
                    -text [Fit [lindex $cats $i] $labelWidth ChartFont [dict get $s -elide]]
            }
            set x $left
            set total 0
            foreach list $values color $colors name $names {
                set v [lindex $list $i]
                if {![string is double -strict $v] || $v <= 0} continue
                set x2 [expr {$x + $v * $scale}]
                set id [$w create rectangle $x [expr {$y - $thick / 2}] $x2 [expr {$y + $thick / 2}] \
                    -fill $color -outline "" -tags [list bar bar$i]]
                Bind $w $id $i $name
                set x $x2
                set total [expr {$total + $v}]
            }
            if {$labelled} {
                $w create text [expr {$x + $pad / 2}] $y -text [{*}$format $total] -anchor w \
                    -font ChartFont -fill gray35 -state disabled
            }
        }
        $w create line $left $y0 $left $bottom -fill gray60 -state disabled
    } else {
        set left [expr {$pad + $tickWidth + $pad / 2}]
        set right [expr {$width - $pad}]
        set y0 [expr {$y0 + $ls / 2}]
        set bottom [expr {$height - $pad - $ls}]
        set bottom [expr {max($bottom, $y0 + 10)}]
        set slot [expr {($right - $left) / double($n)}]
        set bw [expr {$slot > 4 ? min($slot * 0.75, $ls * 4) : max(1.0, $slot - 0.5)}]
        set scale [expr {($bottom - $y0) / double($top)}]
        for {set i 0} {$i < $n} {incr i} {
            set x [expr {$left + $i * $slot}]
            $w create rectangle $x $y0 [expr {$x + $slot}] $bottom -fill [$w cget -background] \
                -outline "" -tags [list col col$i]
            Bind $w col$i $i ""
        }
        foreach t $ticks {
            set y [expr {$bottom - $t * $scale}]
            $w create line $left $y $right $y -fill $grid -state disabled
            $w create text [expr {$left - $pad / 2}] $y -text [{*}$format $t] -anchor e \
                -font ChartFont -fill gray35 -state disabled
        }
        # The labels: as many as fit, evenly.
        set labelWidth 0
        foreach c $cats { set labelWidth [expr {max($labelWidth, [font measure ChartFont $c])}] }
        set every [expr {max(1, int(ceil(($labelWidth + $pad) / $slot)))}]
        for {set i 0} {$i < $n} {incr i $every} {
            # (Within the chart at its ends.)
            set label [lindex $cats $i]
            set half [expr {[font measure ChartFont $label] / 2.0}]
            set x [expr {$left + ($i + 0.5) * $slot}]
            set x [expr {min(max($x, $half + 2), $width - $half - 2)}]
            $w create text $x [expr {$bottom + 2}] \
                -text $label -anchor n -font ChartFont -fill gray35 -state disabled
        }
        if {$line} {
            foreach list $values color $colors name $names {
                set points {}
                for {set i 0} {$i < $n} {incr i} {
                    set v [lindex $list $i]
                    if {![string is double -strict $v]} continue
                    lappend points [expr {$left + ($i + 0.5) * $slot}] [expr {$bottom - $v * $scale}]
                }
                if {[llength $points] >= 4} {
                    $w create line {*}$points -fill $color -width 2 -state disabled
                }
                if {$n <= 60} {
                    foreach {x y} $points {
                        $w create oval [expr {$x - 2.5}] [expr {$y - 2.5}] [expr {$x + 2.5}] [expr {$y + 2.5}] \
                            -fill $color -outline "" -state disabled
                    }
                }
            }
        } else {
            for {set i 0} {$i < $n} {incr i} {
                set x [expr {$left + $i * $slot + ($slot - $bw) / 2}]
                set y $bottom
                foreach list $values color $colors name $names {
                    set v [lindex $list $i]
                    if {![string is double -strict $v] || $v <= 0} continue
                    set y2 [expr {$y - $v * $scale}]
                    set id [$w create rectangle $x $y2 [expr {$x + $bw}] $y -fill $color -outline "" \
                        -tags [list bar bar$i]]
                    Bind $w $id $i $name
                    set y $y2
                }
            }
        }
        $w create line $left $bottom $right $bottom -fill gray60 -state disabled
    }
}

# The names of the series and their colours, in a row (or more) below
# the title: the y below.
proc charts::Legend {w y names colors} {
    set pad [font measure ChartFont 0]
    set ls [font metrics ChartFont -linespace]
    set box [expr {$ls * 0.6}]
    set x $pad
    foreach name $names color $colors {
        set wide [expr {$box + $pad / 2 + [font measure ChartFont $name] + $pad * 2}]
        if {$x > $pad && $x + $wide > [winfo width $w]} {
            set x $pad
            set y [expr {$y + $ls}]
        }
        set top [expr {$y + ($ls - $box) / 2}]
        $w create rectangle $x $top [expr {$x + $box}] [expr {$top + $box}] -fill $color \
            -outline "" -state disabled
        $w create text [expr {$x + $box + $pad / 2}] [expr {$y + $ls / 2}] -text $name -anchor w \
            -font ChartFont -state disabled
        set x [expr {$x + $wide}]
    }
    expr {$y + $ls + $pad / 2}
}

proc charts::DrawGrid {w s} {
    set rows [dict get $s -rows]
    set cols [dict get $s -columns]
    set pad [font measure ChartFont 0]
    set ls [font metrics ChartFont -linespace]
    set y0 [Title $w $s]
    set labelWidth 0
    foreach r $rows { set labelWidth [expr {max($labelWidth, [font measure ChartFont $r])}] }
    set left [expr {$pad + $labelWidth + $pad / 2}]
    set top [expr {$y0 + $ls}]
    set across [expr {[winfo width $w] - $left - $pad}]
    set down [expr {[winfo height $w] - $top - $pad - $ls - $pad / 2}]
    set cell [expr {max(2, int(min($across / double(max(1, [llength $cols])),
        $down / double(max(1, [llength $rows])), $ls * 2)))}]
    set gap [expr {$cell > 6 ? max(1, $cell / 8) : 0}]
    set colormap [dict get $s -colormap]
    set max 0
    if {![dict size $colormap]} {
        foreach {r c v key tip} [dict get $s -cells] { set max [expr {max($max, $v)}] }
    }
    # (Every other label where they would not fit: Mon, Wed, Fri.)
    set every [expr {max(1, int(ceil($ls / double($cell))))}]
    for {set i 0} {$i < [llength $rows]} {incr i $every} {
        $w create text [expr {$left - $pad / 2}] [expr {$top + ($i + 0.5) * $cell}] -anchor e \
            -text [lindex $rows $i] -font ChartFont -fill gray35 -state disabled
    }
    set end -1
    for {set j 0} {$j < [llength $cols]} {incr j} {
        set label [lindex $cols $j]
        set x [expr {$left + $j * $cell}]
        if {$label eq "" || $x < $end} continue
        $w create text $x [expr {$top - 2}] -anchor sw -text $label -font ChartFont -fill gray35 \
            -state disabled
        set end [expr {$x + [font measure ChartFont $label] + $pad / 2}]
    }
    set i 0
    foreach {r c v key tip} [dict get $s -cells] {
        set x [expr {$left + $c * $cell}]
        set y [expr {$top + $r * $cell}]
        set fill [if {[dict exists $colormap $v]} {dict get $colormap $v} else {Shade $v $max}]
        set id [$w create rectangle $x $y [expr {$x + $cell - $gap}] [expr {$y + $cell - $gap}] \
            -fill $fill -outline "" -tags [list cell cell$i]]
        Bind $w $id $i ""
        incr i
    }
    # Less ... More: the shades; or the kinds.
    set y [expr {$top + [llength $rows] * $cell + $pad / 2}]
    set box [expr {min($cell, $ls * 0.7)}]
    set x $left
    if {[dict size $colormap]} {
        dict for {name colour} $colormap {
            $w create rectangle $x $y [expr {$x + $box}] [expr {$y + $box}] -fill $colour \
                -outline "" -state disabled
            $w create text [expr {$x + $box + $pad / 2}] [expr {$y + $box / 2}] -text $name \
                -anchor w -font ChartFont -fill gray35 -state disabled
            set x [expr {$x + $box + $pad + [font measure ChartFont $name] + $pad}]
        }
        return
    }
    $w create text $x [expr {$y + $box / 2}] -text Less -anchor w -font ChartFont -fill gray35 \
        -state disabled
    set x [expr {$x + [font measure ChartFont Less] + $pad / 2}]
    foreach f {0 0.25 0.5 0.75 1} {
        $w create rectangle $x $y [expr {$x + $box}] [expr {$y + $box}] -outline "" \
            -fill [Shade [expr {$f * max($max, 1)}] [expr {max($max, 1)}]] -state disabled
        set x [expr {$x + $box + 2}]
    }
    $w create text [expr {$x + $pad / 2}] [expr {$y + $box / 2}] -text More -anchor w \
        -font ChartFont -fill gray35 -state disabled
}

# A colour from light to dark blue for VALUE of MAX (more contrast among
# the small values); grey for none.
proc charts::Shade {value max} {
    variable empty
    if {$value <= 0 || $max <= 0} { return $empty }
    set f [expr {sqrt(min(1.0, $value / double($max)))}]
    set rgb {}
    foreach a {198 219 239} b {8 48 107} {
        lappend rgb [expr {round($a + ($b - $a) * $f)}]
    }
    format #%02x%02x%02x {*}$rgb
}

proc charts::Colors {s n} {
    variable palette
    set colors [dict get $s -colors]
    for {set i [llength $colors]} {$i < $n} {incr i} {
        lappend colors [lindex $palette [expr {$i % [llength $palette]}]]
    }
    lrange $colors 0 [expr {$n - 1}]
}

# (Not the grey, which marks what has no colour of its own, nor the
# yellow, too light on white.)
proc charts::colour {name} {
    variable palette
    set h 0
    foreach c [split $name ""] { set h [expr {($h * 31 + [scan $c %c]) % 1000003}] }
    lindex $palette [expr {$h % 6}]
}

# A step and the top of the axis for values up to MAX: 1, 2 or 5 times a
# power of ten, about five steps; whole numbers.
proc charts::Ticks {max} {
    if {$max <= 0} { return {1 1} }
    set raw [expr {$max / 5.0}]
    set mag [expr {10 ** floor(log10($raw))}]
    set r [expr {$raw / $mag}]
    set step [expr {$mag * ($r <= 1 ? 1 : $r <= 2 ? 2 : $r <= 5 ? 5 : 10)}]
    set step [expr {max(1, round($step))}]
    list $step [expr {int(ceil($max / double($step))) * $step}]
}

# TEXT cut to WIDTH pixels in FONT, with an ellipsis at the end or in
# the middle.
proc charts::Fit {text width font {where end}} {
    if {[font measure $font $text] <= $width} { return $text }
    set n [string length $text]
    while {$n > 1} {
        incr n -1
        if {$where eq "middle"} {
            set head [expr {$n / 2}]
            set cut "[string range $text 0 $head-1]\u2026[string range $text end-[expr {$n - $head - 1}] end]"
        } else {
            set cut "[string range $text 0 $n-1]\u2026"
        }
        if {[font measure $font $cut] <= $width} break
    }
    return $cut
}

proc charts::number {n} {
    if {![string is double -strict $n]} { return $n }
    if {$n != round($n)} {
        return [format [expr {abs($n) < 10 ? "%.1f" : "%.0f"}] $n]
    }
    set n [format %.0f $n]
    regsub -all {\d(?=(\d{3})+$)} $n {&,} n
    return $n
}

proc charts::bytes {n} {
    if {![string is double -strict $n]} { return $n }
    foreach unit {B kB MB GB TB} {
        if {abs($n) < 1000 || $unit eq "TB"} break
        set n [expr {$n / 1000.0}]
    }
    if {$unit eq "B"} { return "[format %.0f $n] B" }
    return "[format [expr {abs($n) < 10 ? "%.1f" : "%.0f"}] $n] $unit"
}

# --------------------------------------------------------- hover, click

# The item ID (or tag) of chart W shows entry I (a category, a cell) and
# the series NAME ("" for all).
proc charts::Bind {w id i name} {
    variable items
    variable spec
    set n [llength $items($w)]
    lappend items($w) [list $i $name]
    $w bind $id <Enter> [list charts::Enter $w $n %X %Y]
    $w bind $id <Leave> [list charts::Leave $w $n]
    if {[dict get $spec($w) -command] ne ""} {
        $w bind $id <ButtonRelease-1> [list charts::Click $w $n]
    }
}

proc charts::Enter {w n X Y} {
    variable items
    variable spec
    variable hover
    lassign [lindex $items($w) $n] i name
    if {[dict get $spec($w) -type] eq "bars"} { $w itemconfigure col$i -fill $hover }
    if {[dict get $spec($w) -command] ne ""} { $w configure -cursor hand2 }
    icons::tipLater $w [Tip $w $i $name] $X $Y
}

proc charts::Leave {w n} {
    variable items
    variable spec
    lassign [lindex $items($w) $n] i
    if {[dict get $spec($w) -type] eq "bars"} { $w itemconfigure col$i -fill [$w cget -background] }
    $w configure -cursor ""
    icons::tipHide
}

proc charts::Click {w n} {
    variable items
    variable spec
    lassign [lindex $items($w) $n] i name
    set s $spec($w)
    icons::tipHide
    if {[dict get $s -type] eq "grid"} {
        set key [lindex [dict get $s -cells] [expr {$i * 5 + 3}]]
        if {$key ne ""} { uplevel #0 [list {*}[dict get $s -command] $key] }
    } else {
        uplevel #0 [list {*}[dict get $s -command] [Key $s $i] $name]
    }
}

proc charts::Key {s i} {
    set keys [dict get $s -keys]
    if {$i < [llength $keys]} { return [lindex $keys $i] }
    lindex [dict get $s -categories] $i
}

# The tooltip of entry I: the category and each series' value (and the
# sum, stacked); of a cell, its own or "ROW COLUMN: VALUE".
proc charts::Tip {w i name} {
    variable spec
    set s $spec($w)
    set format [dict get $s -format]
    if {[dict get $s -type] eq "grid"} {
        lassign [lrange [dict get $s -cells] [expr {$i * 5}] [expr {$i * 5 + 4}]] r c v key tip
        if {$tip ne ""} { return $tip }
        return "[lindex [dict get $s -rows] $r] [lindex [dict get $s -columns] $c]: [{*}$format $v]"
    }
    set lines [list [lindex [dict get $s -categories] $i]]
    set series [dict get $s -series]
    if {[llength $series] == 2} {
        lappend lines [{*}$format [lindex $series 1 $i]]
    } else {
        set sum 0
        foreach {n list} $series {
            set v [lindex $list $i]
            if {![string is double -strict $v]} continue
            set sum [expr {$sum + $v}]
            lappend lines "$n: [{*}$format $v]"
        }
        if {![dict get $s -line]} { lappend lines "Total: [{*}$format $sum]" }
    }
    join $lines \n
}

# ------------------------------------------------------- copy and save

proc charts::Menu {w X Y} {
    set m $w.menu
    destroy $m
    menu $m -tearoff 0
    $m add command -label "Copy data" -command [list ui::copy [tsv $w]]
    $m add command -label "Save as SVG\u2026" -command [list charts::Save $w svg]
    $m add command -label "Save as PostScript\u2026" -command [list charts::Save $w ps]
    tk_popup $m $X $Y
}

proc charts::Save {w format} {
    variable spec
    set name [string map {/ - " " -} [string tolower [dict get $spec($w) -title]]]
    if {$name eq ""} { set name chart }
    set file [tk_getSaveFile -parent [winfo toplevel $w] -initialfile $name.$format \
        -defaultextension .$format \
        -filetypes [list [list [string toupper $format] .$format] {"All files" *}]]
    if {$file eq ""} return
    try {
        if {$format eq "svg"} {
            set chan [open $file w]
            fconfigure $chan -encoding utf-8
            puts -nonewline $chan [svg $w]
            close $chan
        } else {
            $w postscript -file $file
        }
    } on error msg {
        ui::errorBox -parent [winfo toplevel $w] "The chart was not saved." $msg
    }
}

proc charts::tsv {w} {
    variable spec
    set s $spec($w)
    set lines {}
    switch -- [dict get $s -type] {
        bars {
            set names {}
            foreach {name list} [dict get $s -series] { lappend names $name }
            lappend lines [join [list "" {*}$names] \t]
            set i 0
            foreach c [dict get $s -categories] {
                set row [list $c]
                foreach {name list} [dict get $s -series] { lappend row [lindex $list $i] }
                lappend lines [join $row \t]
                incr i
            }
        }
        grid {
            foreach {r c v key tip} [dict get $s -cells] {
                lappend lines [join [list [lindex [dict get $s -rows] $r] \
                    [lindex [dict get $s -columns] $c] $key $v] \t]
            }
        }
    }
    join $lines \n
}

# The items of the canvas as SVG shapes, as drawn.
proc charts::svg {w} {
    set width [winfo width $w]
    set height [winfo height $w]
    set out [list "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" \
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\"\
viewBox=\"0 0 $width $height\">" \
        "<rect width=\"$width\" height=\"$height\" fill=\"[Hex $w [$w cget -background]]\"/>"]
    foreach id [$w find all] {
        if {[$w itemcget $id -state] eq "hidden"} continue
        set c [lmap v [$w coords $id] {format %.1f $v}]
        switch -- [$w type $id] {
            rectangle - oval {
                set fill [Hex $w [$w itemcget $id -fill]]
                set stroke [Hex $w [$w itemcget $id -outline]]
                if {$fill eq "none" && $stroke eq "none"} continue
                lassign $c x1 y1 x2 y2
                if {[$w type $id] eq "rectangle"} {
                    lappend out [format {<rect x="%s" y="%s" width="%.1f" height="%.1f" fill="%s" stroke="%s"/>} \
                        $x1 $y1 [expr {$x2 - $x1}] [expr {$y2 - $y1}] $fill $stroke]
                } else {
                    lappend out [format {<ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="%s" stroke="%s"/>} \
                        [expr {($x1 + $x2) / 2}] [expr {($y1 + $y2) / 2}] [expr {($x2 - $x1) / 2}] \
                        [expr {($y2 - $y1) / 2}] $fill $stroke]
                }
            }
            line {
                set points {}
                foreach {x y} $c { lappend points $x,$y }
                lappend out [format {<polyline points="%s" fill="none" stroke="%s" stroke-width="%s"/>} \
                    [join $points] [Hex $w [$w itemcget $id -fill]] [$w itemcget $id -width]]
            }
            text {
                set font [font actual [$w itemcget $id -font]]
                lassign [$w bbox $id] x1 y1
                set px [expr {abs([dict get $font -size]) * ([dict get $font -size] > 0 ? [tk scaling] : 1)}]
                set y [expr {$y1 + [font metrics [$w itemcget $id -font] -ascent]}]
                lappend out [format {<text x="%d" y="%d" font-family="%s" font-size="%.1f" font-weight="%s" fill="%s">%s</text>} \
                    $x1 $y [Xml [dict get $font -family]] $px [dict get $font -weight] \
                    [Hex $w [$w itemcget $id -fill]] [Xml [$w itemcget $id -text]]]
            }
        }
    }
    lappend out </svg>
    join $out \n
}

proc charts::Hex {w color} {
    if {$color eq ""} { return none }
    lassign [winfo rgb $w $color] r g b
    format #%02x%02x%02x [expr {$r >> 8}] [expr {$g >> 8}] [expr {$b >> 8}]
}

proc charts::Xml {text} {
    string map {& &amp; < &lt; > &gt; \" &quot;} $text
}

# ---------------------------------------------------------- sparklines

proc charts::spark {values width height {color #0072b2}} {
    set image [image create photo -width $width -height $height]
    set max 0
    foreach v $values { if {[string is double -strict $v]} { set max [expr {max($max, $v)}] } }
    set n [llength $values]
    if {!$n} { return $image }
    $image put #d0d0d0 -to 0 [expr {$height - 1}] $width $height
    if {$max <= 0} { return $image }
    set i 0
    foreach v $values {
        if {[string is double -strict $v] && $v > 0} {
            set x1 [expr {int($i * $width / double($n))}]
            set x2 [expr {max($x1 + 1, int(($i + 1) * $width / double($n)) - ($width / $n > 2 ? 1 : 0))}]
            set h [expr {max(1, round($v / double($max) * ($height - 1)))}]
            $image put $color -to $x1 [expr {$height - $h}] $x2 $height
        }
        incr i
    }
    return $image
}

# ------------------------------------------------------------ diffstat

proc charts::statTags {t} {
    $t tag configure statadd -foreground #1a7f37
    $t tag configure statdel -foreground #cf222e
    $t tag configure baradd -background #3fb950
    $t tag configure bardel -background #f47067
}

proc charts::numstat {text} {
    set result {}
    foreach line [split $text \n] {
        if {![regexp {^\s*(\d+)\s+(\d+)\s+(.+)$} $line -> added deleted file]} continue
        if {[string match "TOTAL over *" $file]} continue
        lappend result $file $added $deleted
    }
    return $result
}

proc charts::stat {t index added deleted max {tag ""}} {
    # (Bars of spaces: as high as the line, in the size of the text.)
    set scale [expr {$max > 20 ? 20.0 / $max : 1}]
    set a [expr {$added ? max(1, round($added * $scale)) : 0}]
    set d [expr {$deleted ? max(1, round($deleted * $scale)) : 0}]
    set sep [if {$tag ne ""} {string cat \t} else {string cat "  "}]
    $t insert $index $sep $tag +$added [list statadd {*}$tag] " " $tag \
        \u2212$deleted [list statdel {*}$tag] $sep $tag \
        [string repeat " " $a] [list baradd {*}$tag] [string repeat " " $d] [list bardel {*}$tag]
}

proc charts::statImage {added deleted max width height} {
    set image [image create photo -width $width -height $height]
    set a [expr {$added ? max(1, round($added * $width / double($max))) : 0}]
    set d [expr {$deleted ? max(1, round($deleted * $width / double($max))) : 0}]
    if {$a} { $image put #3fb950 -to 0 0 $a $height }
    if {$d} { $image put #f47067 -to $a 0 [expr {min($width, $a + $d)}] $height }
    return $image
}
