# Images (attachments) shown in a window of their own, in the formats Tk
# reads itself: PNG, GIF and PPM/PGM, and SVG with Tk 9; with the Img
# extension (tkimg) installed also JPEG, BMP, TIFF and others.  Img is
# optional: it is loaded the first time an image of its formats is
# viewed; without it such images cannot be viewed here.
#
#   imageview::kind NAME        by the file name's extension: image (it can
#                               be viewed), unsupported (an image that
#                               cannot: Img is missing, or SVG with Tk 8.6),
#                               "" (not an image)
#   imageview::fileKind NAME BINARY
#                               what an attachment NAME is, for its icon
#                               (icons a-KIND) and whether it can be
#                               viewed: patch, tcl, c, text, image (can
#                               be shown), binary (also an image that
#                               cannot); BINARY: its content has NUL bytes
#   imageview::canView KIND     whether a file of that kind can be viewed
#   imageview::binarySql SRC    an SQL expression for "fossil sql": whether
#                               the artifact SRC (a column) has a NUL byte
#                               in its first 8 KB (0 if it is not here)
#   imageview::listStyle        the style of the attachment lists: their
#                               tree column holds the icon, with no room
#                               for the expanders
#   imageview::showArtifact REPO SRC NAME ?-parent W?
#                               the artifact SRC of REPO (the content of
#                               the attachment NAME) in a window of its
#                               own (raised if it is open already); one
#                               for each image, any number open
#   imageview::windowFor W SRC  the window of the artifact SRC (under W)
#   imageview::window W TITLE IMAGE
#                               IMAGE (deleted with the window) in the
#                               toplevel W: scrolled, or fitted to it;
#                               zoomed with Ctrl+Wheel, Ctrl+plus and
#                               Ctrl+minus (Ctrl+0: 100%), scrolled with
#                               the wheel (Shift: sideways)

namespace eval imageview {
    variable fit                ;# array: window -> fitted to the window
    variable shown              ;# array: window -> the image at 100%
    variable small              ;# array: window -> the image as shown, scaled
    variable zoom               ;# array: window -> the level chosen (not fitted)
    variable level              ;# array: window -> the level shown
    # The levels of zoom, as photo images scale: subsample, then zoom by
    # whole numbers (2/3: every third pixel left out, then each doubled).
    variable levels {
        {1 8} {1 6} {1 4} {1 3} {1 2} {2 3} {3 4} {1 1} {3 2} {2 1} {3 1} {4 1} {6 1} {8 1}
    }
    variable largest 16384      ;# the largest side of an image zoomed
    variable loaded             ;# array: package of Img -> it could be loaded
    # Extension -> the photo format, and the package of Img for it ("": Tk
    # reads it itself).
    variable formats {
        png {png ""}  gif {gif ""}  ppm {ppm ""}  pgm {ppm ""}  pnm {ppm ""}
        jpg {jpeg img::jpeg}  jpeg {jpeg img::jpeg}  bmp {bmp img::bmp}
        tif {tiff img::tiff}  tiff {tiff img::tiff}  ico {ico img::ico}
        tga {tga img::tga}  pcx {pcx img::pcx}  xbm {xbm img::xbm}
        xpm {xpm img::xpm}  sgi {sgi img::sgi}  ras {sun img::sun}
    }
    # Images no format here reads.
    variable others {webp heic heif avif}
}

proc imageview::Format {name} {
    variable formats
    set ext [string tolower [string trimleft [file extension $name] .]]
    if {$ext eq "svg"} {
        return [expr {[package vsatisfies [package provide Tk] 9] ? {svg ""} : {}}]
    }
    expr {[dict exists $formats $ext] ? [dict get $formats $ext] : {}}
}

proc imageview::kind {name} {
    variable loaded
    variable others
    set ext [string tolower [string trimleft [file extension $name] .]]
    set format [Format $name]
    if {![llength $format]} {
        return [expr {$ext eq "svg" || $ext in $others ? "unsupported" : ""}]
    }
    lassign $format - package
    if {$package eq ""} { return image }
    if {![info exists loaded($package)]} {
        set loaded($package) [expr {![catch {package require $package}]}]
    }
    expr {$loaded($package) ? "image" : "unsupported"}
}

proc imageview::fileKind {name binary} {
    set ext [string tolower [string trimleft [file extension $name] .]]
    switch -- [kind $name] {
        image { return image }
        unsupported { return binary }
    }
    if {$ext in {patch diff}} { return patch }
    if {$binary} { return binary }
    if {$ext in {tcl tm test tk itcl}} { return tcl }
    if {$ext in {c h m cpp cc cxx hpp hh mm}} { return c }
    return text
}

proc imageview::binarySql {src} {
    # (content() fails for an artifact that is not here: not called then.)
    string cat "CASE WHEN coalesce((SELECT size FROM blob WHERE uuid=$src),-1) < 0 THEN 0" \
        " ELSE instr(substr(content($src),1,8192),x'00')>0 END"
}

proc imageview::canView {kind} {
    expr {$kind ne "binary"}
}

proc imageview::listStyle {} {
    # (The layout of Treeview.Item without its indicator; of the theme in
    # use, chosen at the start.)
    ttk::style layout Attachments.Treeview.Item {
        Treeitem.padding -sticky nswe -children {
            Treeitem.image -side left -sticky {} Treeitem.text -sticky nswe
        }
    }
    return Attachments.Treeview
}

proc imageview::windowFor {parent src} {
    return [string trimright $parent .].image[string range $src 0 15]
}

proc imageview::showArtifact {repo src name args} {
    set parent [expr {[dict exists $args -parent] ? [dict get $args -parent] : "."}]
    if {[kind $name] ne "image"} return
    set w [windowFor $parent $src]
    if {[winfo exists $w]} {
        wm deiconify $w
        raise $w
        focus $w.c
        return
    }
    set dir [fossil::tempDir]
    try {
        # (Into a file: bytes as they are.)
        set path [file join $dir image]
        lassign [fossil::run artifact -R $repo $src $path] code out
        if {$code} {
            ui::errorBox -parent $parent -title Attachment "Cannot read the attachment:" $out
            return
        }
        if {[catch {image create photo -format [lindex [Format $name] 0] -file $path} image]} {
            ui::errorBox -parent $parent -title Attachment "$name cannot be shown." $image
            return
        }
    } finally {
        file delete -force $dir
    }
    window $w "$name \u2014 [image width $image] \u00d7 [image height $image]" $image
}

proc imageview::window {w title image} {
    variable fit
    variable shown
    variable zoom
    destroy $w
    toplevel $w
    wm title $w $title
    wm transient $w .
    set shown($w) $image
    set fit($w) 0
    set zoom($w) {1 1}
    ttk::frame $w.b -padding 6
    ttk::checkbutton $w.b.fit -text "Fit to the window" -variable imageview::fit($w) \
        -command [list imageview::Layout $w]
    ttk::label $w.b.zoom -width 6 -anchor e
    icons::tooltip $w.b.zoom "Ctrl+Wheel, Ctrl+plus, Ctrl+minus: zoom; Ctrl+0: 100%"
    ttk::button $w.b.close -text Close -command [list destroy $w]
    pack $w.b.fit $w.b.zoom -side left
    pack $w.b.close -side right
    pack $w.b -side bottom -fill x
    ttk::frame $w.f
    # (A unit of scrolling: 10 pixels, a notch of the wheel 3 of them.)
    canvas $w.c -highlightthickness 0 -xscrollcommand [list $w.x set] -yscrollcommand [list $w.y set] \
        -xscrollincrement 10 -yscrollincrement 10
    ttk::scrollbar $w.x -orient horizontal -command [list $w.c xview]
    ttk::scrollbar $w.y -command [list $w.c yview]
    grid $w.c $w.y -in $w.f -sticky news
    grid $w.x -in $w.f -sticky ew
    grid columnconfigure $w.f 0 -weight 1
    grid rowconfigure $w.f 0 -weight 1
    pack $w.f -fill both -expand 1
    # (As large as the image, up to most of the screen.)
    $w.c configure -width [expr {min([image width $image], [winfo screenwidth $w] * 3 / 4)}] \
        -height [expr {min([image height $image], [winfo screenheight $w] * 3 / 4)}]
    bind $w.c <Configure> [list imageview::Layout $w]
    bind $w <Escape> [list destroy $w]
    bind $w.c <Destroy> [list imageview::Forget $w]
    # Zoom: the wheel at the pointer, the keys at the middle.
    foreach key {Control-plus Control-equal Control-KP_Add} {
        bind $w <$key> [list imageview::Zoom $w 1]
    }
    foreach key {Control-minus Control-KP_Subtract} {
        bind $w <$key> [list imageview::Zoom $w -1]
    }
    bind $w <Control-0> [list imageview::Zoom $w 0]
    bind $w.c <Control-MouseWheel> [list imageview::Zoom $w %D %x %y]
    # Scrolling: the wheel, Shift+Wheel sideways.
    bind $w.c <MouseWheel> [list imageview::Wheel $w.c y %D]
    bind $w.c <Shift-MouseWheel> [list imageview::Wheel $w.c x %D]
    # (Tk 8.6 on X11: the wheel is buttons 4 and 5; in Tk 9 they are the
    # side buttons.)
    if {![package vsatisfies [package provide Tk] 9] && [tk windowingsystem] eq "x11"} {
        bind $w.c <Control-Button-4> [list imageview::Zoom $w 1 %x %y]
        bind $w.c <Control-Button-5> [list imageview::Zoom $w -1 %x %y]
        bind $w.c <Button-4> [list $w.c yview scroll -3 units]
        bind $w.c <Button-5> [list $w.c yview scroll 3 units]
        bind $w.c <Shift-Button-4> [list $w.c xview scroll -3 units]
        bind $w.c <Shift-Button-5> [list $w.c xview scroll 3 units]
    }
    Layout $w
    focus $w.c
    return $w
}

# Scroll the canvas C along AXIS (x, y) by the wheel's DELTA, as Tk's
# lists do: 120 (a notch) is 3 units.
proc imageview::Wheel {c axis delta} {
    if {[package vsatisfies [package provide Tk] 9]} {
        # (Also the smaller steps of a touchpad, added up.)
        tk::MouseWheel $c $axis $delta -40.0 units
    } else {
        $c ${axis}view scroll [expr {$delta >= 0 ? -$delta / 40 : (39 - $delta) / 40}] units
    }
}

# The level of zoom that fits the image in the canvas (at most 100%).
proc imageview::FitLevel {w} {
    variable levels
    variable shown
    set cw [expr {max([winfo width $w.c], 1)}]
    set ch [expr {max([winfo height $w.c], 1)}]
    set best [lindex $levels 0]
    foreach l $levels {
        lassign $l p q
        if {$p > $q} break
        if {[image width $shown($w)] * $p / $q <= $cw && [image height $shown($w)] * $p / $q <= $ch} {
            set best $l
        }
    }
    return $best
}

# Zoom in (BY > 0), out (BY < 0) or back to 100% (BY 0), keeping the point
# X Y of the canvas (default: its middle) where it is.
proc imageview::Zoom {w by {x ""} {y ""}} {
    variable levels
    variable level
    variable zoom
    variable fit
    variable shown
    variable largest
    if {![winfo exists $w.c]} return
    set i [lsearch -exact $levels $level($w)]
    if {$by == 0} {
        set new {1 1}
    } else {
        set i [expr {$by > 0 ? $i + 1 : $i - 1}]
        if {$i < 0 || $i >= [llength $levels]} return
        set new [lindex $levels $i]
        lassign $new p q
        # (Not larger than a photo image can well be.)
        if {max([image width $shown($w)], [image height $shown($w)]) * $p / $q > $largest} return
    }
    if {$x eq ""} {
        set x [expr {[winfo width $w.c] / 2}]
        set y [expr {[winfo height $w.c] / 2}]
    }
    set fit($w) 0
    set zoom($w) $new
    Layout $w $x $y
}

# The image at the level of zoom chosen, or fitted to the window; scrolled
# so that the point X Y of the canvas stays where it is.
proc imageview::Layout {w {x ""} {y ""}} {
    variable fit
    variable shown
    variable small
    variable zoom
    variable level
    if {![winfo exists $w.c]} return
    set image $shown($w)
    set new [expr {$fit($w) ? [FitLevel $w] : $zoom($w)}]
    if {[info exists level($w)] && $level($w) eq $new && [llength [$w.c find all]]} return
    # The point of the image at X Y, as a part of its width and height.
    if {$x ne "" && [info exists level($w)]} {
        lassign $level($w) p q
        set fx [expr {[$w.c canvasx $x] * $q / double($p) / [image width $image]}]
        set fy [expr {[$w.c canvasy $y] * $q / double($p) / [image height $image]}]
    }
    $w.c delete all
    if {[info exists small($w)]} {
        image delete $small($w)
        unset small($w)
    }
    lassign $new p q
    set show $image
    if {$new ne {1 1}} {
        set show [image create photo]
        $show copy $image -subsample $q $q -zoom $p $p
        set small($w) $show
    }
    set level($w) $new
    $w.c create image 0 0 -anchor nw -image $show
    set sw [image width $show]
    set sh [image height $show]
    $w.c configure -scrollregion [list 0 0 $sw $sh]
    $w.b.zoom configure -text "[expr {round(100.0 * $p / $q)}]%"
    if {[info exists fx]} {
        $w.c xview moveto [expr {($fx * $sw - $x) / double(max($sw, 1))}]
        $w.c yview moveto [expr {($fy * $sh - $y) / double(max($sh, 1))}]
    }
}

proc imageview::Forget {w} {
    variable fit
    variable shown
    variable small
    variable zoom
    variable level
    if {[info exists shown($w)]} { catch {image delete $shown($w)} }
    if {[info exists small($w)]} { catch {image delete $small($w)} }
    unset -nocomplain shown($w) fit($w) small($w) zoom($w) level($w)
}
