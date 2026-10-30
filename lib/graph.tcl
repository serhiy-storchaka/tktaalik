# The graph of the check-ins beside the Timeline's rows, as on Fossil's
# web timeline: a node for each check-in, a line down to its parent (in the
# colour of its branch), a thin grey line to each check-in it merged.  The
# rows come newest first; each draws its part of the lines as an image of
# its own (the tree column of the treeview), so the graph scrolls and is
# selected with the rows, in Tk 8.6 and 9.
#
#   graph::layout ROWS
#       ROWS: {ID CHECKIN COLOUR PARENTS} in the order shown, PARENTS a
#       list of {PARENT PRIMARY}.  Returns {LANES DRAWING}: the lanes used
#       and a dict ID -> the parts of its row (graph::rowImage draws them).
#       A parent shown below gets a line down to it; one not shown (further
#       down than the rows, or left out by a search) a short stub, as a
#       line to the bottom for each would fill the graph with lanes.
#   graph::rowImage PARTS LANES LANEWIDTH HEIGHT ?CURRENT?
#       a new photo image of a row: CURRENT circles its node

namespace eval graph {
    variable merge #9a9a9a      ;# the colour of the lines to merged check-ins
    variable most 24            ;# lanes drawn at most
}

proc graph::layout {rows} {
    variable merge
    set index {}
    set i 0
    foreach row $rows { dict set index [lindex $row 0] [incr i] }
    # The lanes going down: each waits for a check-in {ID COLOUR WIDTH},
    # or is free ("").
    set lanes {}
    set drawing {}
    set most 0
    set i 0
    foreach row $rows {
        incr i
        lassign $row id checkin colour parents
        set parts {}
        if {!$checkin} {
            set n 0
            foreach lane $lanes {
                if {$lane ne ""} { lappend parts [list full $n {*}[lrange $lane 1 2]] }
                incr n
            }
            dict set drawing $id $parts
            continue
        }
        # Its lane: one waiting for it, else a free one.
        set hits {}
        set n 0
        foreach lane $lanes {
            if {[lindex $lane 0] eq $id} { lappend hits $n }
            incr n
        }
        if {[llength $hits]} {
            set mine [lindex $hits 0]
        } else {
            set mine [Free $lanes]
        }
        set n 0
        foreach lane $lanes {
            if {$lane ne "" && $n ni $hits} { lappend parts [list full $n {*}[lrange $lane 1 2]] }
            incr n
        }
        # The lanes that end here: from above into the node.
        foreach h $hits {
            set lane [lindex $lanes $h]
            lappend parts [list top $h {*}[lrange $lane 1 2]]
            if {$h != $mine} {
                lappend parts [list across $h $mine {*}[lrange $lane 1 2]]
                lset lanes $h ""
            }
        }
        while {[llength $lanes] <= $mine} { lappend lanes "" }
        lset lanes $mine ""
        set node [list node $mine $colour]
        foreach parent $parents {
            lassign $parent pid primary
            set below [expr {[dict exists $index $pid] && [dict get $index $pid] > $i}]
            if {$primary} {
                if {$below} {
                    lset lanes $mine [list $pid $colour 2]
                    lappend parts [list bottom $mine $colour 2]
                } else {
                    lappend parts [list stub $mine $colour 2]
                }
            } elseif {$below} {
                # Into the lane waiting for it, else a lane of its own.
                set to -1
                set n 0
                foreach lane $lanes {
                    if {[lindex $lane 0] eq $pid} { set to $n; break }
                    incr n
                }
                if {$to < 0} {
                    set to [Free $lanes $mine]
                    while {[llength $lanes] <= $to} { lappend lanes "" }
                    lset lanes $to [list $pid $merge 1]
                    lappend parts [list bottom $to $merge 1]
                }
                lappend parts [list across $mine $to $merge 1]
            }
        }
        lappend parts $node
        while {[llength $lanes] && [lindex $lanes end] eq ""} { set lanes [lrange $lanes 0 end-1] }
        set most [expr {max($most, [llength $lanes], $mine + 1)}]
        dict set drawing $id $parts
    }
    list $most $drawing
}

# The first free lane (not BUT), or a new one.
proc graph::Free {lanes {but -1}} {
    set n 0
    foreach lane $lanes {
        if {$lane eq "" && $n != $but} { return $n }
        incr n
    }
    expr {max($n, $but + 1)}
}

proc graph::rowImage {parts lanes width height {current 0}} {
    variable most
    set lanes [expr {min($lanes, $most)}]
    set w [expr {max(1, $lanes) * $width + 2}]
    set image [image create photo -width $w -height $height]
    set mid [expr {$height / 2}]
    set node ""
    foreach part $parts {
        set args [lassign $part kind]
        switch -- $kind {
            full - top - bottom - stub {
                lassign $args lane colour thick
                if {$lane >= $lanes} continue
                set x [Center $lane $width]
                set y1 [expr {$kind in {bottom stub} ? $mid : 0}]
                set y2 [expr {$kind in {full bottom} ? $height : $kind eq "stub" ? $mid + $height / 3 : $mid + 1}]
                Put $image $colour [expr {$x - $thick / 2}] $y1 [expr {$x - $thick / 2 + $thick}] $y2 $w
            }
            across {
                lassign $args from to colour thick
                set x1 [Center [expr {min($from, $to)}] $width]
                set x2 [Center [expr {max($from, $to)}] $width]
                Put $image $colour $x1 [expr {$mid - $thick / 2}] [expr {$x2 + 1}] \
                    [expr {$mid - $thick / 2 + $thick}] $w
            }
            node { set node $args }
        }
    }
    if {[llength $node]} {
        lassign $node lane colour
        if {$lane < $lanes} {
            set x [Center $lane $width]
            set r [expr {max(2, $width * 3 / 10)}]
            if {$current} {
                Disc $image $x $mid [expr {$r + 2}] black $w
                Disc $image $x $mid [expr {$r + 1}] white $w
            }
            Disc $image $x $mid $r $colour $w
        }
    }
    return $image
}

proc graph::Center {lane width} {
    expr {$lane * $width + $width / 2 + 1}
}

# A rectangle within the image (a photo grows to what is put in it).
proc graph::Put {image colour x1 y1 x2 y2 w} {
    set x1 [expr {max(0, $x1)}]
    set x2 [expr {min($w, $x2)}]
    if {$x2 > $x1 && $y2 > $y1} { $image put $colour -to $x1 $y1 $x2 $y2 }
}

proc graph::Disc {image x y r colour w} {
    for {set dy [expr {-$r}]} {$dy <= $r} {incr dy} {
        set dx [expr {int(sqrt($r * $r - $dy * $dy) + 0.3)}]
        Put $image $colour [expr {$x - $dx}] [expr {$y + $dy}] [expr {$x + $dx + 1}] [expr {$y + $dy + 1}] $w
    }
}
