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
#   imageview::showArtifact REPO SRC NAME ?-parent W?
#                               the artifact SRC of REPO (the content of
#                               the attachment NAME) in a window of its
#                               own (raised if it is open already); one
#                               for each image, any number open
#   imageview::windowFor W SRC  the window of the artifact SRC (under W)
#   imageview::window W TITLE IMAGE
#                               IMAGE (deleted with the window) in the
#                               toplevel W: scrolled, or fitted to it

namespace eval imageview {
    variable fit                ;# array: window -> fitted to the window
    variable shown              ;# array: window -> the image at 100%
    variable small              ;# array: window -> the image made smaller
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
    destroy $w
    toplevel $w
    wm title $w $title
    wm transient $w .
    set shown($w) $image
    set fit($w) 0
    ttk::frame $w.b -padding 6
    ttk::checkbutton $w.b.fit -text "Fit to the window" -variable imageview::fit($w) \
        -command [list imageview::Layout $w]
    ttk::button $w.b.close -text Close -command [list destroy $w]
    pack $w.b.fit -side left
    pack $w.b.close -side right
    pack $w.b -side bottom -fill x
    ttk::frame $w.f
    canvas $w.c -highlightthickness 0 -xscrollcommand [list $w.x set] -yscrollcommand [list $w.y set]
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
    Layout $w
    focus $w.c
    return $w
}

# The image at 100%, or made smaller (by a whole factor) to fit.
proc imageview::Layout {w} {
    variable fit
    variable shown
    variable small
    if {![winfo exists $w.c]} return
    set image $shown($w)
    $w.c delete all
    if {[info exists small($w)]} {
        image delete $small($w)
        unset small($w)
    }
    set show $image
    if {$fit($w)} {
        set cw [winfo width $w.c]
        set ch [winfo height $w.c]
        set n [expr {max(1, int(ceil(max([image width $image] / double(max($cw, 1)),
            [image height $image] / double(max($ch, 1))))))}]
        if {$n > 1} {
            set show [image create photo]
            $show copy $image -subsample $n $n
            set small($w) $show
        }
    }
    $w.c create image 0 0 -anchor nw -image $show
    $w.c configure -scrollregion [list 0 0 [image width $show] [image height $show]]
}

proc imageview::Forget {w} {
    variable fit
    variable shown
    variable small
    if {[info exists shown($w)]} { catch {image delete $shown($w)} }
    if {[info exists small($w)]} { catch {image delete $small($w)} }
    unset -nocomplain shown($w) fit($w) small($w)
}
