# The icons of attachments by their kind (patch, Tcl, C, text, image,
# binary).  Attached images shown in a window, on a ticket and on a wiki page: PNG,
# GIF, PPM, SVG with Tk 9, and with the Img extension (tkimg) JPEG, BMP...
# Images that cannot be viewed (no Img, SVG with Tk 8.6, WEBP): View
# disabled, a double-click opens the server's page.  With Img on the
# TCLLIBPATH the JPEG part is shown, else it is checked disabled.  On a
# scratch copy.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
set R $W/tk.fossil
set img9 [package vsatisfies [package provide Tk] 9]
set withImg [expr {![catch {package require img::jpeg}]}]
puts "  Img: [expr {$withImg ? [package provide img::jpeg] : "none"}]"
# A PNG of 40x20, red with a blue corner, made by Tk; a JPEG of it with
# Img (else bytes that only claim to be one); an SVG; a WEBP.
set img [image create photo -width 40 -height 20]
$img put red -to 0 0 40 20
$img put blue -to 0 0 4 4
$img write $T(tmp)/shot.png -format png
if {$withImg} {
    $img write $T(tmp)/photo.jpg -format jpeg
} else {
    set f [open $T(tmp)/photo.jpg wb]; puts -nonewline $f "\xff\xd8\xff\xe0 not really"; close $f
}
image delete $img
set f [open $T(tmp)/draw.svg w]
puts $f {<svg xmlns="http://www.w3.org/2000/svg" width="30" height="10"><rect width="30" height="10" fill="#00ff00"/></svg>}
close $f
set f [open $T(tmp)/pic.webp wb]; puts -nonewline $f "RIFF\0\0\0\0WEBP"; close $f
# A file of each other kind: a patch, Tcl and C sources, text, binary.
foreach {name data} {fix.diff "--- a\n+++ b\n" demo.tcl "puts hi\n" tkDemo.c "int x;\n"
        notes.txt "text\n" data.bin "a\0b"} {
    set f [open $T(tmp)/$name wb]; puts -nonewline $f [subst $data]; close $f
}

set uuid [lindex [sql "SELECT tkt_uuid FROM ticket ORDER BY tkt_mtime DESC LIMIT 1" $R] 0 0]
start tickets $R
set ::urls {}
proc tktsearch::openUrl {path} { lappend ::urls $path }
proc tk_popup {m args} { set ::posted $m }
tktsearch::setQuery id:[string range $uuid 0 9]; update
waitUntil {$tktsearch::shownTicket eq $uuid}
set ::openFrom [lmap n {shot.png photo.jpg draw.svg pic.webp fix.diff demo.tcl tkDemo.c notes.txt data.bin} {
    file join $T(tmp) $n
}]
whenOpen .tickets.attach {set ::ui::done ok}
tktsearch::attachFiles $uuid
set tv .tickets.main.details.nb.attachments.tv
proc item {name} {
    foreach i [$::tv children {}] { if {[$::tv set $i file] eq $name} { return $i } }
}
# The window of the attachment NAME's image.
proc win {name} { imageview::windowFor .tickets [dict get $tktsearch::attached([item $name]) src] }
proc imageWindows {} { lsearch -all -inline -glob [winfo children .tickets] .tickets.image* }
# The state of View in the context menu of NAME, and the entry in bold.
proc menuOf {name} {
    set i [item $name]
    $::tv see $i; update
    lassign [$::tv bbox $i] x y
    set ::posted ""
    tktsearch::attachmentMenu $::tv [expr {$x + 5}] [expr {$y + 3}] 0 0
    set m $::posted
    set bold ""
    for {set k 0} {$k <= [$m index end]} {incr k} {
        if {[$m type $k] eq "command" && [$m entrycget $k -font] ne ""} { set bold [$m entrycget $k -label] }
    }
    list [$m entrycget View -state] $bold
}
.tickets.main.details.nb select .tickets.main.details.nb.attachments; update
check "kinds: [lmap n {a.PNG b.jpg c.svg d.webp e.txt} {imageview::kind $n}]" \
    {[imageview::kind a.PNG] eq "image" && [imageview::kind e.txt] eq "" && [imageview::kind d.webp] eq "unsupported"
     && [imageview::kind b.jpg] eq [expr {$withImg ? "image" : "unsupported"}]
     && [imageview::kind c.svg] eq [expr {$img9 ? "image" : "unsupported"}]}

# Each with the icon of its kind (binary: content with a NUL byte, or an
# image that cannot be viewed); View disabled only for binary.
foreach {name kind} [list shot.png image photo.jpg [expr {$withImg ? "image" : "binary"}] \
        draw.svg [expr {$img9 ? "image" : "binary"}] pic.webp binary fix.diff patch demo.tcl tcl \
        tkDemo.c c notes.txt text data.bin binary] {
    set got [$tv item [item $name] -image]
    check "$name: the icon of $kind" {$got eq [icons::get a-$kind row]}
    if {$kind ne "image"} {
        check "$name: View [expr {$kind eq "binary" ? "disabled" : "normal"}]" \
            {[lindex [menuOf $name] 0] eq [expr {$kind eq "binary" ? "disabled" : "normal"}]}
    }
}
# (The icon in the tree column, with no room for an expander before it.)
$tv see [item shot.png]; update
lassign [$tv bbox [item shot.png] #0] x0 - w0
check "the icon column: [expr {[icons::rowSize] + 8}] pixels" {$w0 == [icons::rowSize] + 8}

# A PNG: View; double-click shows it in a window.
check "PNG: [menuOf shot.png]" {[menuOf shot.png] eq {normal View}}
tktsearch::openAttachment [item shot.png]; update
set w [win shot.png]
check "a window: [expr {[winfo exists $w] ? [wm title $w] : ""}]" {[winfo exists $w] && [wm title $w] eq "shot.png — 40 × 20"}
set shown [$w.c itemcget [lindex [$w.c find all] 0] -image]
check "the image: [image width $shown]x[image height $shown]" {[image width $shown] == 40 && [image height $shown] == 20}
check "its pixels: [$shown get 1 1] [$shown get 30 10]" {[$shown get 1 1] eq {0 0 255} && [$shown get 30 10] eq {255 0 0}}
# Zoom: Ctrl+plus, Ctrl+minus, Ctrl+0, Ctrl+Wheel; the level shown.
proc shownSize {w} {
    set i [$w.c itemcget [lindex [$w.c find all] 0] -image]
    return [image width $i]x[image height $i]
}
focus -force $w.c; update
check "100%: [$w.b.zoom cget -text]" {[$w.b.zoom cget -text] eq "100%" && [shownSize $w] eq "40x20"}
event generate $w <Control-plus>; update
check "Ctrl+plus: [$w.b.zoom cget -text] [shownSize $w]" {[$w.b.zoom cget -text] eq "150%" && [shownSize $w] eq "60x30"}
event generate $w <Control-minus>; event generate $w <Control-minus>; update
check "Ctrl+minus twice: [$w.b.zoom cget -text] [shownSize $w]" {[$w.b.zoom cget -text] eq "75%" && [shownSize $w] eq "30x15"}
event generate $w <Control-0>; update
check "Ctrl+0: [$w.b.zoom cget -text]" {[$w.b.zoom cget -text] eq "100%" && [shownSize $w] eq "40x20"}
event generate $w.c <Control-MouseWheel> -delta 120 -x 5 -y 5; update
check "Ctrl+Wheel up: [$w.b.zoom cget -text]" {[$w.b.zoom cget -text] eq "150%"}
event generate $w.c <Control-MouseWheel> -delta -120 -x 5 -y 5; update
check "Ctrl+Wheel down: [$w.b.zoom cget -text]" {[$w.b.zoom cget -text] eq "100%"}
for {set k 0} {$k < 20} {incr k} { event generate $w <Control-plus> }
update
check "at most 800%: [$w.b.zoom cget -text] [shownSize $w]" {[$w.b.zoom cget -text] eq "800%" && [shownSize $w] eq "320x160"}
for {set k 0} {$k < 20} {incr k} { event generate $w <Control-minus> }
update
check "at least 13% (1/8): [$w.b.zoom cget -text] [shownSize $w]" {[$w.b.zoom cget -text] eq "13%" && [shownSize $w] eq "5x3"}
event generate $w <Control-0>; update
# The same image at once again (no copy): the original.
check "100% shows the image itself" {[$w.c itemcget [lindex [$w.c find all] 0] -image] eq $shown}

# Another image beside it; the first one again: raised, not twice.
set other [expr {$img9 ? "draw.svg" : $withImg ? "photo.jpg" : ""}]
if {$other ne ""} {
    tktsearch::openAttachment [item $other]; update
    check "two windows: [imageWindows]" {[llength [imageWindows]] == 2 && [winfo exists $w] && [winfo exists [win $other]]}
    destroy [win $other]; update
}
tktsearch::openAttachment [item shot.png]; update
check "the same one again: one window, its image kept" \
    {[llength [imageWindows]] == 1 && [$w.c itemcget [lindex [$w.c find all] 0] -image] eq $shown}
destroy $w; update
check "closed: its image deleted" {$shown ni [image names]}

# Fitted to a smaller window: made smaller (a large image, whatever the
# smallest window is).
set big [image create photo -width 1600 -height 900]
$big put green -to 0 0 1600 900
imageview::window .big "big" $big
wm geometry .big 400x300; update
set imageview::fit(.big) 1; imageview::Layout .big; update
set small [.big.c itemcget [lindex [.big.c find all] 0] -image]
check "fitted: [image width $small]x[image height $small] in [winfo width .big.c]x[winfo height .big.c]" \
    {[image width $small] <= [winfo width .big.c] && [image height $small] <= [winfo height .big.c] && [image width $small] < 1600}
# (Fitted: the largest level that fits, shown.)
lassign $imageview::level(.big) p q
check "fitted: the level shown: [.big.b.zoom cget -text]" {[.big.b.zoom cget -text] eq "[expr {round(100.0 * $p / $q)}]%"}
# Zooming at the pointer: the point of the image under it stays there
# (larger than the window: it can scroll); no longer fitted.
imageview::Zoom .big 0; update
.big.c xview moveto 0.3; .big.c yview moveto 0.3; update
set p 1; set q 1
set imageview::fit(.big) 1
set x 100; set y 80
proc imagePoint {x y} {
    lassign $imageview::level(.big) p q
    list [expr {round([.big.c canvasx $x] * $q / double($p))}] [expr {round([.big.c canvasy $y] * $q / double($p))}]
}
set before [imagePoint $x $y]
imageview::Zoom .big 1 $x $y; update
set after [imagePoint $x $y]
check "zoomed in at the pointer: [.big.b.zoom cget -text], the point $before -> $after" \
    {$imageview::level(.big) ne [list $p $q] && abs([lindex $after 0] - [lindex $before 0]) <= 6
     && abs([lindex $after 1] - [lindex $before 1]) <= 6 && !$imageview::fit(.big)}
# The wheel scrolls (a notch: 30 pixels), Shift+Wheel sideways; Ctrl+Wheel
# zooms instead.
imageview::Zoom .big 0; update
.big.c xview moveto 0; .big.c yview moveto 0; update
event generate .big.c <MouseWheel> -delta -120 -x 50 -y 50; update
check "the wheel scrolls down: [.big.c canvasy 0]" {[.big.c canvasy 0] == 30 && [.big.c canvasx 0] == 0}
event generate .big.c <Shift-MouseWheel> -delta -120 -x 50 -y 50; update
check "Shift+Wheel sideways: [.big.c canvasx 0]" {[.big.c canvasx 0] == 30 && [.big.c canvasy 0] == 30}
event generate .big.c <MouseWheel> -delta 120 -x 50 -y 50; update
check "back up, the zoom as it was: [.big.c canvasy 0], [.big.b.zoom cget -text]" \
    {[.big.c canvasy 0] == 0 && [.big.b.zoom cget -text] eq "100%"}
# A real wheel (XTEST on Xvfb): button 5 down, as a mouse sends it.
if {[realInput]} {
    raise .big; focus -force .big.c; update
    event generate .big.c <Motion> -warp 1 -x 50 -y 50; update; after 200; update
    exec $T(xbutton) 5
    after 300; update; update
    check "a real wheel scrolls down: [.big.c canvasy 0]" {[.big.c canvasy 0] == 30}
} else {
    puts "note: no real wheel (no XTEST helper or not on Xvfb)"
}
destroy .big; update
check "closed: both images deleted" {$big ni [image names] && $small ni [image names]}

# Images that can or cannot be viewed: JPEG (Img), SVG (Tk 9), WEBP (none).
foreach {name can} [list photo.jpg $withImg draw.svg $img9 pic.webp 0] {
    set ::urls {}
    if {$can} {
        check "$name: [menuOf $name]" {[menuOf $name] eq {normal View}}
        tktsearch::openAttachment [item $name]; update
        set w [win $name]
        set shown [expr {[winfo exists $w] ? [$w.c itemcget [lindex [$w.c find all] 0] -image] : ""}]
        check "$name shown: [expr {$shown eq "" ? "no" : "[image width $shown]x[image height $shown]"}]" \
            {$shown ne "" && [image width $shown] == ($name eq "draw.svg" ? 30 : 40)}
        destroy $w; update
    } else {
        check "$name: View disabled, the browser in bold: [menuOf $name]" {[menuOf $name] eq {disabled {Open in browser}}}
        tktsearch::openAttachment [item $name]; update
        check "$name: double-click opens the server's page: $::urls" \
            {![llength [imageWindows]] && [string match "attachview?tkt=*&file=$name" [lindex $::urls end]]}
    }
}

# A wiki page's image; and one it cannot view.
fossilIn $W attachment add "Migrating scripts to Tk 9" $T(tmp)/shot.png -R $R
fossilIn $W attachment add "Migrating scripts to Tk 9" $T(tmp)/pic.webp -R $R
tktaalik::show wiki; update
.wiki.main.list.t selection set [list "wiki-Migrating scripts to Tk 9"]; update
set att .wiki.main.page.att.tv
proc witem {name} {
    foreach i [$::att children {}] { if {[$::att set $i file] eq $name} { return $i } }
}
tkwiki::openAttachment [witem shot.png]; update
set ww [imageview::windowFor .wiki [dict get $tkwiki::attached([witem shot.png]) src]]
check "the wiki's image: [expr {[winfo exists $ww] ? [wm title $ww] : ""}]" \
    {[winfo exists $ww] && [string match "shot.png*40*20" [wm title $ww]]}
destroy $ww
$att see [witem pic.webp]; update
lassign [$att bbox [witem pic.webp]] x y
set ::posted ""
tkwiki::attachmentMenu $att [expr {$x + 5}] [expr {$y + 3}] 0 0
check "the wiki's WEBP: View [$::posted entrycget View -state]" {[$::posted entrycget View -state] eq "disabled"}
done
