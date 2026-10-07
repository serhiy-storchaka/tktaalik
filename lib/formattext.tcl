# A text to write in one of several formats (Fossil wiki, Markdown, plain
# text, HTML), with its preview: the Write and Preview tabs, and the format
# chosen above them.  The preview is rendered by Fossil, as the text will
# be shown (fossil::render, lib/htmltext.tcl).
#
#   formattext::create W ?OPTION VALUE...?
#       Makes the frame W.  Options:
#       -formats DICT   label -> mimetype, in the order offered
#       -variable VAR   the global variable with the label of the format
#       -fixed LABEL    the format, not to be chosen (the menu is not shown)
#       -repo PATH      the repository the text is rendered for
#       -text TEXT      the text to start with
#       -height LINES   of the text (default 10)
#   formattext::widget W     the text widget (for bindings, focus)
#   formattext::get W        the text written
#   formattext::mimetype W   the mimetype of the format chosen

source [file join [file dirname [file normalize [info script]]] fossil.tcl]
source [file join [file dirname [file normalize [info script]]] htmltext.tcl]

namespace eval formattext {
    variable opts             ;# array: W -> its options
}

proc formattext::create {w args} {
    variable opts
    set o [dict merge {-formats {} -variable "" -fixed "" -repo "" -text "" -height 10} $args]
    set opts($w) $o
    ttk::frame $w
    ttk::frame $w.top
    ttk::label $w.top.l -text "Format:"
    set formats [dict get $o -formats]
    if {[dict get $o -fixed] ne ""} {
        ttk::label $w.top.format -text [dict get $o -fixed]
    } else {
        set var [dict get $o -variable]
        if {![info exists ::$var] || ![dict exists $formats [set ::$var]]} {
            set ::$var [lindex [dict keys $formats] 0]
        }
        ttk::combobox $w.top.format -textvariable ::$var -state readonly -width 14 \
            -values [dict keys $formats]
        bind $w.top.format <<ComboboxSelected>> [list formattext::preview $w]
    }
    ttk::label $w.top.hint -text "Ctrl+Shift+P: preview" -foreground gray40
    pack $w.top.l $w.top.format -side left -padx {0 6}
    pack $w.top.hint -side right
    ttk::notebook $w.nb
    ttk::frame $w.nb.src
    text $w.nb.src.t -height [dict get $o -height] -width 70 -wrap word -undo 1 \
        -font TkFixedFont -yscrollcommand [list $w.nb.src.y set]
    ttk::scrollbar $w.nb.src.y -command [list $w.nb.src.t yview]
    pack $w.nb.src.y -side right -fill y
    pack $w.nb.src.t -fill both -expand 1
    ttk::frame $w.nb.pre
    text $w.nb.pre.t -height [dict get $o -height] -width 70 -wrap word -font TkTextFont \
        -padx 8 -pady 6 -state disabled -cursor arrow -yscrollcommand [list $w.nb.pre.y set]
    ttk::scrollbar $w.nb.pre.y -command [list $w.nb.pre.t yview]
    pack $w.nb.pre.y -side right -fill y
    pack $w.nb.pre.t -fill both -expand 1
    $w.nb add $w.nb.src -text Write -underline 0
    $w.nb add $w.nb.pre -text Preview -underline 0
    ttk::notebook::enableTraversal $w.nb
    $w.nb.src.t insert end [dict get $o -text]
    $w.nb.src.t edit reset
    $w.nb.src.t edit modified 0
    pack $w.top -fill x -pady {0 4}
    pack $w.nb -fill both -expand 1
    bind $w.nb <<NotebookTabChanged>> [list formattext::preview $w]
    # Ctrl+Shift+P: the preview, and back.
    foreach widget [list $w.nb.src.t $w.nb.pre.t] {
        bind $widget <Control-P> [list formattext::toggle $w]
    }
    bind $w <Destroy> [list formattext::forget $w %W]
    return $w
}

proc formattext::forget {w window} {
    variable opts
    if {$window eq $w} { unset -nocomplain opts($w) }
}

proc formattext::widget {w} { return $w.nb.src.t }

proc formattext::get {w} {
    $w.nb.src.t get 1.0 "end - 1 char"
}

proc formattext::mimetype {w} {
    variable opts
    set o $opts($w)
    set label [expr {[dict get $o -fixed] ne "" ? [dict get $o -fixed] : [set ::[dict get $o -variable]]}]
    dict get [dict get $o -formats] $label
}

proc formattext::toggle {w} {
    if {[$w.nb select] eq "$w.nb.src"} {
        $w.nb select $w.nb.pre
        focus $w.nb.pre.t
    } else {
        $w.nb select $w.nb.src
        focus $w.nb.src.t
    }
}

# The text rendered, in the Preview tab (when shown).
proc formattext::preview {w} {
    variable opts
    if {[$w.nb select] ne "$w.nb.pre"} return
    set text [get $w]
    set d $w.nb.pre.t
    $d configure -state normal
    $d delete 1.0 end
    htmltext::reset $d
    if {[string trim $text] eq ""} {
        $d insert end "Nothing written yet."
    } else {
        set html [fossil::render [dict get $opts($w) -repo] [mimetype $w] $text]
        # (Plain text: as written.)
        if {$html eq ""} { set html "<pre>[string map {& &amp; < &lt; > &gt;} $text]</pre>" }
        htmltext::insert $d $html
    }
    $d configure -state disabled
}
