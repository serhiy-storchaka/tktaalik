# The ui:: layer (lib/ui.tcl): message boxes, the clipboard, the server
# URL, dialogs and buttons, forms (fields, validation, preview, one at a
# time, F1), the text window.
source [file join [file dirname [info script]] common.tcl]
set ::boxArgs {}
set ::answer ok
set ::browsed {}

# Messages.
check "confirm: OK" {[ui::confirm -title T "Do it?" "Really."]}
set b [lindex $::boxArgs end]
check "confirm: the options" {[dict get $b -type] eq "okcancel" && [dict get $b -default] eq "cancel" && [dict get $b -icon] eq "question" && [dict get $b -title] eq "T" && [dict get $b -detail] eq "Really."}
set ::answer cancel
check "confirm: Cancel" {![ui::confirm "Do it?"]}
check "confirm without detail: none passed" {![dict exists [lindex $::boxArgs end] -detail]}
set ::answer ok
ui::errorBox -parent . -title E "Failed" "out"
set b [lindex $::boxArgs end]
check "errorBox" {[dict get $b -icon] eq "error" && [dict get $b -parent] eq "." && [dict get $b -message] eq "Failed"}
ui::infoBox "Note"
check "infoBox" {[dict get [lindex $::boxArgs end] -icon] eq "info"}
# (Tk on Windows crashes in "clipboard clear" before the main window
# exists; the application copies only once it is shown.)
update
ui::copy "copied text"
check "copy" {[clipboard get] eq "copied text"}

# openServer.
ui::openServer https://x.example/repo info/abc
check "openServer: [lindex $::browsed end]" {[lindex $::browsed end] eq "https://x.example/repo/info/abc"}
set ::boxArgs {}
ui::openServer "" info/abc -title Timeline
check "openServer: no URL, a message" {[dict get [lindex $::boxArgs 0] -message] eq "The repository has no server URL." && [dict get [lindex $::boxArgs 0] -title] eq "Timeline"}
set ::boxArgs {}
ui::openServer "" info/abc -quiet 1
check "openServer -quiet" {![llength $::boxArgs]}
ui::openServer https://x.example info -browse {::apply {{u} { set ::other $u }}}
check "openServer -browse" {$::other eq "https://x.example/info"}

# dialog, buttons.
set f [ui::dialog .ld Title -bar 1 -escape {set ::esc 1} -close {set ::closed 1} -help repository#remotes]
ui::buttons .ld.b Apply {set ::ok 1} {set ::ok 0}
update
check "dialog: frames" {$f eq ".ld.f" && [winfo exists .ld.b] && [wm title .ld] eq "Title" && [wm transient .ld] eq "."}
check "buttons" {[.ld.b.ok cget -text] eq "Apply" && [.ld.b.ok cget -default] eq "active" && [.ld.b.cancel cget -text] eq "Cancel"}
.ld.b.ok invoke
check "buttons: OK" {$::ok == 1}
check "dialog -escape -close" {[bind .ld <Escape>] eq {set ::esc 1} && [wm protocol .ld WM_DELETE_WINDOW] eq {set ::closed 1}}
check "dialog -help: F1 there" {[help::context .ld.f] eq "repository#remotes"}
destroy .ld

# later, setText.
set ::n 0
foreach i {1 2 3} { ui::later {incr ::n} 50 }
after 200 {set ::tick 1}; vwait ::tick
check "later: once ($::n)" {$::n == 1}
text .lt -state disabled
ui::setText .lt "abc"
check "setText" {[.lt get 1.0 end-1c] eq "abc" && [.lt cget -state] eq "disabled"}
destroy .lt

# form.
proc ok {after values} {
    after $after [list ::apply {{values} {
        foreach {k v} $values { set ::ui::f($k) $v }
        set ::ui::done ok
    }} $values]
}
array unset ::ui::f
ok 200 {name abc}
set r [ui::form .lf Form "Intro" {{name Name entry} {flag "A flag" check} {kind Kind choice {a b}} {file File save {}}} Make]
check "form: OK ($r, $::ui::f(name))" {$r == 1 && $::ui::f(name) eq "abc" && ![winfo exists .lf]}
whenOpen .lf { set ::ui::done cancel }
check "form: Cancel" {![ui::form .lf Form "" {{name Name entry}} Make]}
# Validation: a problem shown, the dialog stays.
set ::boxArgs {}
array unset ::ui::f
whenOpen .lf { set ::ui::f(name) bad; set ::ui::done ok
    after 300 { set ::ui::f(name) good; set ::ui::done ok } }
set r [ui::form .lf Form "" {{name Name entry}} Make -validate {::apply {{w} {
    expr {$::ui::f(name) eq "bad" ? "Not that." : ""} }}}]
check "form -validate: [lmap b $::boxArgs {dict get $b -message}]" {$r && $::ui::f(name) eq "good" && [dict get [lindex $::boxArgs 0] -message] eq "Not that."}
# Another array, another variable.
namespace eval ::lt { variable v; variable d "" }
whenOpen .lf { set ::lt::v(x) typed; set ::lt::d ok }
set r [ui::form .lf Form "" {{x X entry}} OK -array ::lt::v -done ::lt::d]
check "form -array -done" {$r && $::lt::v(x) eq "typed"}
# Preview: after a change, a moment later.
array unset ::ui::f
set ::ui::f(name) one
whenOpen .lf {
    set ::p1 [.lf.f.p.t get 1.0 end-1c]
    set ::ui::f(name) two
    after 500 { set ::p2 [.lf.f.p.t get 1.0 end-1c]; set ::ui::done ok }
}
ui::form .lf Form "" {{name Name entry}} OK -preview {::apply {{w} { return "would make $::ui::f(name)" }}} -help repository#settings
check "form -preview: $::p1 / $::p2" {$::p1 eq "would make one" && $::p2 eq "would make two"}
check "form -help" {[help::context .lf] eq "repository#settings"}
# One at a time.
whenOpen .lf {
    set ::second [ui::form .lf2 Second "" {{name Name entry}} OK]
    set ::busy [ui::formBusy]
    set ::ui::done cancel
}
ui::form .lf First "" {{name Name entry}} OK
check "form: one at a time" {$::second == 0 && $::busy == 1 && ![ui::formBusy]}
check "form: repoops::form through it" {[info body repoops::form] ne "" && [string match "*ui::form*" [info body repoops::form]]}

# textWindow.
ui::textWindow .ltw "Text" "line 1\nline 2"
update
check "textWindow" {[.ltw.t get 1.0 end-1c] eq "line 1\nline 2" && [.ltw.t cget -state] eq "disabled" && [wm title .ltw] eq "Text"}
check "textWindow: Escape closes" {[bind .ltw <Escape>] eq "destroy .ltw"}

# busy: the main window and the other toplevels shown, during the script
# only; its return, error and result passed on.
toplevel .lb; update
proc busyStates {} { list [tk busy status .] [tk busy status .lb] [tk busy cget .lb -cursor] }
check "busy: all windows, the watch: [ui::busy busyStates]" {[ui::busy busyStates] eq {1 1 watch}}
check "busy: released after" {![tk busy status .] && ![tk busy status .lb]}
proc busyReturns {} { ui::busy { return early }; return late }
check "busy: return in the script returns from the caller" {[busyReturns] eq "early"}
check "busy: error passed on, its code" {[catch {ui::busy { throw {LB TEST} oops }} msg opts]
    && $msg eq "oops" && [dict get $opts -errorcode] eq {LB TEST}}
check "busy: released after an error" {![tk busy status .] && ![tk busy status .lb]}
# The keys ignored while the script handles events (as web:: does), also
# those bound to the toplevel; the focus back after.
entry .lb.e; pack .lb.e
bind .lb <Key-x> {lappend ::busyKeys toplevel}
focus -force .lb.e; update
set ::busyKeys {}
ui::busy {
    event generate [focus] <Key-x>
    after 50 {set ::busyWaited 1}; vwait ::busyWaited
}
check "busy: keys ignored: [list $::busyKeys] [list [.lb.e get]]" {$::busyKeys eq "" && [.lb.e get] eq ""}
update
check "busy: the focus back: [focus]" {[focus] eq ".lb.e"}
event generate .lb.e <Key-x>; update
check "busy: keys after: [list $::busyKeys]" {$::busyKeys eq "toplevel"}
set held [ui::busyHold .]
check "busyHold .: the main window only" {$held eq "." && [tk busy status .] && ![tk busy status .lb]}
ui::busyRelease $held
check "busyRelease" {![tk busy status .]}
destroy .lb
# A tooltip with % in its text (a binding substitutes %).
ttk::label .ltip -text tip
pack .ltip
update
icons::tooltip .ltip "Ctrl+0: 100%; {braces} \\ \$x \[cmd\]"
event generate .ltip <Enter>
waitUntil {[winfo exists .iconsTip.l]}
check "tooltip with %: [.iconsTip.l cget -text]" {[.iconsTip.l cget -text] eq "Ctrl+0: 100%; {braces} \\ \$x \[cmd\]"}
icons::tipHide
destroy .ltip

# A line selected in a text, with its newline, pasted into entries: one
# line (a text still gets the newlines).
text .ptext
ttk::entry .pentry
ttk::combobox .pcombo
text .ptext2
pack .ptext .pentry .pcombo .ptext2
update
.ptext insert end "first\nabc\n\nx\ny\n"
.ptext tag add sel 2.0 3.0
tk_textCopy .ptext
focus -force .pentry
event generate .pentry <<Paste>>
check "entry paste: [.pentry get]" {[.pentry get] eq "abc"}
event generate .pcombo <<Paste>>
check "combobox paste: [.pcombo get]" {[.pcombo get] eq "abc"}
.ptext tag remove sel 1.0 end
.ptext tag add sel 4.0 end
tk_textCopy .ptext
.pentry delete 0 end
event generate .pentry <<Paste>>
check "entry paste of lines: [.pentry get]" {[.pentry get] eq "x y"}
event generate .ptext2 <<Paste>>
check "text paste keeps lines" {[.ptext2 get 1.0 end-1c] eq [.ptext get 4.0 end]}
destroy .ptext .pentry .pcombo .ptext2

# The text size: Ctrl+plus, Ctrl+minus, Ctrl+Wheel in a text, of all the
# texts (fonts of the widget and of its tags, tabs and margins; text
# filled later too); Ctrl+0 100%, the originals again, and not the key
# of the window.
proc px {font} { expr {abs([font metrics $font -linespace])} }
text .z1 -font TkFixedFont -tabs {100 left} -height 5
text .z2 -height 5
pack .z1 .z2
.z1 tag configure big -font {Helvetica -20} -lmargin1 10
.z1 insert end "a\tb\n" big
update
set fixed [px TkFixedFont]
set ::key0 0
bind . <Control-0> {set ::key0 1}
focus -force .z1; update
event generate .z1 <Control-plus>; update
event generate .z1 <Control-plus>; update
check "Ctrl+plus twice: [ui::textSize]" {[ui::textSize] == 1.25}
check "the widget's font: [.z1 cget -font]" {[px [.z1 cget -font]] > $fixed}
proc scaled {font by} { expr {round(abs([font actual $font -size]) * $by)} }
check "a tag's font: [.z1 tag cget big -font]" {[font actual [.z1 tag cget big -font] -size] == [scaled {Helvetica -20} 1.25]}
check "tabs and margins: [.z1 cget -tabs], [.z1 tag cget big -lmargin1]" {[.z1 cget -tabs] eq {125 left} && [.z1 tag cget big -lmargin1] == 13}
check "another text too" {[px [.z2 cget -font]] > [px TkFixedFont]}
.z1 tag configure later -font {Helvetica -16}
.z1 insert end "later\n" later
waitUntil {[.z1 tag cget later -font] ne {Helvetica -16}}
check "a tag made later: [.z1 tag cget later -font]" {[font actual [.z1 tag cget later -font] -size] == [scaled {Helvetica -16} 1.25]}
text .z3; pack .z3; update
waitUntil {[px [.z3 cget -font]] > [px TkFixedFont]}
check "a text made later" 1
event generate .z1 <Control-minus>; update
check "Ctrl+minus: [ui::textSize]" {[ui::textSize] == 1.1}
event generate .z1 <Control-MouseWheel> -delta 60; update
check "half a notch: not yet" {[ui::textSize] == 1.1}
event generate .z1 <Control-MouseWheel> -delta 60; update
check "a notch: [ui::textSize]" {[ui::textSize] == 1.25}
if {![package vsatisfies [package provide Tk] 9] && [tk windowingsystem] eq "x11"} {
    event generate .z1 <Control-Button-5>; update
    check "Ctrl+wheel down (Tk 8.6, X11): [ui::textSize]" {[ui::textSize] == 1.1}
}
# A real Ctrl+Wheel (XTEST on Xvfb): Control held, button 4 (up).
if {[realInput]} {
    set before [ui::textSize]
    raise .; focus -force .z1; update
    event generate .z1 <Motion> -warp 1 -x 20 -y 20; update; after 200; update
    exec $T(xbutton) 4 Control_L
    after 300; update; update
    check "a real Ctrl+Wheel: [ui::textSize]" {[ui::textSize] > $before}
} else {
    puts "note: no real wheel (no XTEST helper or not on Xvfb)"
}
event generate .z1 <Control-0>; update
check "Ctrl+0: 100%" {[ui::textSize] == 1}
check "the originals again" {[.z1 cget -font] eq "TkFixedFont" && [.z1 tag cget big -font] eq {Helvetica -20}
    && [.z1 cget -tabs] eq {100 left} && [.z1 tag cget big -lmargin1] eq 10 && [.z1 tag cget later -font] eq {Helvetica -16}}
check "Ctrl+0 not the window's key" {!$::key0}
for {set i 0} {$i < 20} {incr i} { ui::zoomText 1 }
check "not past the largest: [ui::textSize]" {[ui::textSize] == 3}
ui::textSize 7
check "an unknown size: 100%" {[ui::textSize] == 1}
# Kept in the settings for the next time.
ui::textSize 1.1
tktaalik::saveConfig
ui::textSize 1
tktaalik::loadConfig
check "kept in the settings: [ui::textSize]" {[ui::textSize] == 1.1 && [dict get [config::get $tktaalik::configFile tktaalik] textsize] == 1.1}
ui::textSize 1
bind . <Control-0> {}
destroy .z1 .z2 .z3
check "forgotten when destroyed" {![array size ui::zoomed]}
# ui::size: a window's size in characters and lines of the default font,
# so larger with larger fonts, and never beyond the screen.
toplevel .sized
ui::size .sized 50 10; update
set char [font measure TkDefaultFont 0]
set line [font metrics TkDefaultFont -linespace]
check "ui::size: [wm geometry .sized]" {[string match "[expr {50 * $char}]x[expr {10 * $line}]*" [wm geometry .sized]]}
set size [font configure TkDefaultFont -size]
font configure TkDefaultFont -size [expr {2 * [font actual TkDefaultFont -size]}]
ui::size .sized 50 10; update
check "ui::size, larger fonts: [wm geometry .sized]" {[string match "[expr {50 * [font measure TkDefaultFont 0]}]x*" [wm geometry .sized]] && [font measure TkDefaultFont 0] > $char}
font configure TkDefaultFont -size $size
ui::size .sized 10000 10000; update
check "ui::size, at most 90% of the screen: [wm geometry .sized]" {[string match "[expr {[winfo screenwidth .] * 9 / 10}]x[expr {[winfo screenheight .] * 9 / 10}]*" [wm geometry .sized]]}
destroy .sized
done
