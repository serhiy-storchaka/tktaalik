# A text to write in one of several formats (Fossil wiki, Markdown, plain
# text, HTML), with its preview: the format chosen above it, the buttons of
# the markup, and the Preview button, which shows the text rendered in its
# place.  The preview is rendered by Fossil, as the text will
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
#   formattext::toggle W ?ON?
#       the preview shown (ON 1) or the text (0), else the other one (the
#       Preview button, Ctrl+Shift+P)
#   formattext::apply W ACTION
#       the markup of ACTION (bold, italic, code, link, heading, bullet,
#       number, quote, block; ticket, checkin, branch: a reference, chosen
#       in a window unless the selection names one) in the format chosen, around the selection or
#       on its lines (or at the cursor); again: taken off.  1 if done (0 for
#       plain text).  The buttons above the text do it, and keys as on
#       GitHub: Ctrl+B, Ctrl+I, Ctrl+E, Ctrl+K, Ctrl+Shift+8, 7 and "."
#       (bullet, number, quote); Ctrl+Shift+H, Ctrl+Shift+E (heading, block),
#       Ctrl+Shift+T, C, B (ticket, check-in, branch).
#   formattext::get W        the text written
#   formattext::mimetype W   the mimetype of the format chosen

source [file join [file dirname [file normalize [info script]]] fossil.tcl]
source [file join [file dirname [file normalize [info script]]] htmltext.tcl]
source [file join [file dirname [file normalize [info script]]] refpick.tcl]

namespace eval formattext {
    variable opts             ;# array: W -> its options
    variable previewOn        ;# array: W -> 1 while the preview is shown
    # What each action writes, by format: {ref TEMPLATE ?WITHTEXT?} a
    # reference chosen (refpick): %h the hash (10 digits), %u the name in a
    # URL, %t the text (the selection, else the hash or name), WITHTEXT
    # instead when there is a text; {wrap OPEN CLOSE} around the
    # selection; {link TEMPLATE} with %t the text, %u the URL; on each line
    # of it {prefix TEXT}, {number} (1. 2. ...), {line OPEN CLOSE}; around
    # its lines {block OPEN CLOSE}, {list OPEN CLOSE} (each line an item).
    variable markup {
        text/x-markdown {
            bold {wrap ** **} italic {wrap _ _} code {wrap ` `}
            link {link {[%t](%u)}} heading {prefix {## }} bullet {prefix {- }}
            number {number} quote {prefix {> }} block {block ``` ```}
            ticket {ref {[%t](/tktview/%h)}} checkin {ref {[%t](/info/%h)}}
            branch {ref {[%t](/timeline?r=%u)}}
        }
        text/x-fossil-wiki {
            bold {wrap <b> </b>} italic {wrap <i> </i>} code {wrap <code> </code>}
            link {link {[%u|%t]}} heading {line <h2> </h2>} bullet {prefix {  *  }}
            number {prefix {  #  }} quote {block <blockquote> </blockquote>}
            block {block <verbatim> </verbatim>}
            ticket {ref {[%h]} {[%h|%t]}} checkin {ref {[%h]} {[%h|%t]}}
            branch {ref {[/timeline?r=%u|%t]}}
        }
        text/html {
            bold {wrap <b> </b>} italic {wrap <i> </i>} code {wrap <code> </code>}
            link {link {<a href="%u">%t</a>}} heading {line <h2> </h2>}
            bullet {list <ul> </ul>} number {list <ol> </ol>}
            quote {block <blockquote> </blockquote>} block {block <pre> </pre>}
            ticket {ref {<a href="/tktview/%h">%t</a>}} checkin {ref {<a href="/info/%h">%t</a>}}
            branch {ref {<a href="/timeline?r=%u">%t</a>}}
        }
    }
    # The buttons: action, label, tooltip.
    variable buttons [list \
        bold B "Bold (Ctrl+B)" italic I "Italic (Ctrl+I)" code <> "Code (Ctrl+E)" \
        link Link "Link (Ctrl+K)" heading H "Heading (Ctrl+Shift+H)" bullet \u2022 "Bulleted list (Ctrl+Shift+8)" \
        number 1. "Numbered list (Ctrl+Shift+7)" quote \u201c "Quote (Ctrl+Shift+.)" block "{ }" "Code block (Ctrl+Shift+E)" \
        ticket Ticket "Ticket reference (Ctrl+Shift+T)" checkin Check-in "Check-in reference (Ctrl+Shift+C)" \
        branch Branch "Branch reference (Ctrl+Shift+B)"]
    # The icons shown instead of the labels (with icons.tcl).
    variable icons {link link ticket k-ticket checkin k-checkin branch k-branch}
    # Their keys, as on GitHub (where it has them); the shifted ones by the
    # characters of a US keyboard (Shift+8 is *).
    variable keys {
        b bold i italic e code k link H heading E block
        asterisk bullet ampersand number greater quote T ticket C checkin B branch
    }
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
        bind $w.top.format <<ComboboxSelected>> [list formattext::changed $w]
    }
    pack $w.top.l $w.top.format -side left -padx {0 6}
    Toolbar $w
    # The preview: in place of the text while the button is down.
    ttk::checkbutton $w.top.preview -text Preview -style Toolbutton -takefocus 0 \
        -variable ::formattext::previewOn($w) -command [list formattext::Show $w]
    if {[info commands ::icons::tooltip] ne ""} {
        icons::tooltip $w.top.preview "The text as it will be shown, rendered by Fossil (Ctrl+Shift+P)"
    }
    pack $w.top.preview -side right
    set ::formattext::previewOn($w) 0
    # The text and the preview in turn, in the place of the same size.
    ttk::frame $w.body
    ttk::frame $w.src
    text $w.src.t -height [dict get $o -height] -width 70 -wrap word -undo 1 \
        -font TkFixedFont -yscrollcommand [list $w.src.y set]
    ttk::scrollbar $w.src.y -command [list $w.src.t yview]
    pack $w.src.y -side right -fill y
    pack $w.src.t -fill both -expand 1
    ttk::frame $w.pre
    text $w.pre.t -height [dict get $o -height] -width 70 -wrap word -font TkTextFont \
        -padx 8 -pady 6 -state disabled -cursor arrow -yscrollcommand [list $w.pre.y set]
    ttk::scrollbar $w.pre.y -command [list $w.pre.t yview]
    pack $w.pre.y -side right -fill y
    pack $w.pre.t -fill both -expand 1
    $w.src.t insert end [dict get $o -text]
    $w.src.t edit reset
    $w.src.t edit modified 0
    pack $w.top -fill x -pady {0 4}
    pack $w.body -fill both -expand 1
    pack $w.src -in $w.body -fill both -expand 1
    # Ctrl+Shift+P: the preview, and back.
    foreach widget [list $w.src.t $w.pre.t] {
        bind $widget <Control-P> [list formattext::toggle $w]
    }
    # The keys of the markup (in plain text, what Tk does with them).
    variable keys
    foreach {key action} $keys {
        bind $w.src.t <Control-$key> "if {\[formattext::apply [list $w] $action\]} break"
    }
    Buttons $w
    bind $w <Destroy> [list formattext::forget $w %W]
    return $w
}

proc formattext::Toolbar {w} {
    variable buttons
    if {"formattextBold" ni [font names]} {
        font create formattextBold {*}[font actual TkDefaultFont] -weight bold
        font create formattextItalic {*}[font actual TkDefaultFont] -slant italic
        ttk::style configure FormatBold.Toolbutton -font formattextBold
        ttk::style configure FormatItalic.Toolbutton -font formattextItalic
    }
    ttk::separator $w.top.sep -orient vertical
    pack $w.top.sep -side left -fill y -padx 4
    foreach {action label tip} $buttons {
        set style [expr {$action eq "bold" ? "FormatBold.Toolbutton"
            : $action eq "italic" ? "FormatItalic.Toolbutton" : "Toolbutton"}]
        ttk::button $w.top.$action -text $label -style $style -takefocus 0 -width 0 \
            -command [list formattext::apply $w $action]
        # (The references with their icons, as in the Timeline.)
        variable icons
        if {[dict exists $icons $action] && [info commands ::icons::get] ne ""} {
            $w.top.$action configure -image [icons::get [dict get $icons $action]]
        }
        if {[info commands ::icons::tooltip] ne ""} { icons::tooltip $w.top.$action $tip }
        pack $w.top.$action -side left
    }
}

# The buttons usable in the format chosen (none for plain text).
proc formattext::Buttons {w} {
    variable buttons
    variable markup
    variable opts
    set mimetype [mimetype $w]
    foreach {action label tip} $buttons {
        # (References need the repository.)
        set on [expr {!$::formattext::previewOn($w) && [dict exists $markup $mimetype $action]
            && ([lindex [dict get $markup $mimetype $action] 0] ne "ref" || [dict get $opts($w) -repo] ne "")}]
        $w.top.$action state [expr {$on ? "!disabled" : "disabled"}]
    }
}

proc formattext::changed {w} {
    Buttons $w
    preview $w
}

proc formattext::forget {w window} {
    variable opts
    variable previewOn
    if {$window eq $w} { unset -nocomplain opts($w) previewOn($w) }
}

proc formattext::widget {w} { return $w.src.t }

proc formattext::get {w} {
    $w.src.t get 1.0 "end - 1 char"
}

proc formattext::mimetype {w} {
    variable opts
    set o $opts($w)
    set label [if {[dict get $o -fixed] ne ""} {dict get $o -fixed} else {set ::[dict get $o -variable]}]
    dict get [dict get $o -formats] $label
}

# The preview shown (ON 1), or the text (0), or the other one.
proc formattext::toggle {w {on ""}} {
    variable previewOn
    set previewOn($w) [expr {$on eq "" ? !$previewOn($w) : $on}]
    Show $w
}

# The text or its preview, as the Preview button says.
proc formattext::Show {w} {
    variable previewOn
    # (Its size kept from the text's: the window does not change when the
    # preview, in another font, is shown.)
    if {[pack propagate $w.body]} {
        $w.body configure -width [winfo width $w.body] -height [winfo height $w.body]
        pack propagate $w.body 0
    }
    if {$previewOn($w)} {
        pack forget $w.src
        pack $w.pre -in $w.body -fill both -expand 1
        preview $w
        focus $w.pre.t
    } else {
        pack forget $w.pre
        pack $w.src -in $w.body -fill both -expand 1
        focus $w.src.t
    }
    Buttons $w
}

# The text rendered, in the preview (when shown).
proc formattext::preview {w} {
    variable opts
    variable previewOn
    if {!$previewOn($w)} return
    set text [get $w]
    set d $w.pre.t
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

# ------------------------------------------------------------- markup

proc formattext::apply {w action} {
    variable markup
    set mimetype [mimetype $w]
    if {![dict exists $markup $mimetype $action]} { return 0 }
    set t $w.src.t
    # (From the preview: back to the text.)
    variable previewOn
    if {$previewOn($w)} { toggle $w 0 }
    focus $t
    set spec [dict get $markup $mimetype $action]
    if {[lindex $spec 0] eq "ref"} {
        variable opts
        if {[dict get $opts($w) -repo] eq ""} { return 0 }
        Reference $w $action
        return 1
    }
    # One step for Undo.
    set auto [$t cget -autoseparators]
    $t configure -autoseparators 0
    $t edit separator
    try {
        switch -- [lindex $spec 0] {
            wrap { Wrap $t {*}[lrange $spec 1 end] }
            link { Link $t [lindex $spec 1] }
            default { Lines $t $spec }
        }
    } finally {
        $t edit separator
        $t configure -autoseparators $auto
    }
    return 1
}

# Put TEXT in place of FROM..TO, then select FIRST..LAST of it (offsets in
# TEXT), or put the cursor at FIRST if they are the same.
proc formattext::Replace {t from to text first last} {
    set from [$t index $from]
    $t delete $from $to
    $t insert $from $text
    $t tag remove sel 1.0 end
    if {$first != $last} { $t tag add sel "$from + $first chars" "$from + $last chars" }
    $t mark set insert "$from + $last chars"
    $t see insert
}

proc formattext::Wrap {t open close} {
    set o [string length $open]
    set c [string length $close]
    if {[llength [$t tag ranges sel]]} {
        set from [$t index sel.first]
        set to [$t index sel.last]
        set text [$t get $from $to]
        set n [string length $text]
        # Already marked: the marks inside the selection, or around it.
        if {$n > $o + $c && [string first $open $text] == 0
                && [string range $text end-[expr {$c - 1}] end] eq $close} {
            set inner [string range $text $o end-$c]
            Replace $t $from $to $inner 0 [string length $inner]
        } elseif {[$t get "$from - $o chars" $from] eq $open && [$t get $to "$to + $c chars"] eq $close} {
            Replace $t "$from - $o chars" "$to + $c chars" $text 0 $n
        } else {
            Replace $t $from $to $open$text$close $o [expr {$o + $n}]
        }
    } else {
        Replace $t insert insert $open$close $o $o
    }
}

# A link: the selection is its text (or its URL, if it is one); the
# placeholder left selected, to be typed over.
proc formattext::Link {t template} {
    set text text
    set url url
    set from [$t index insert]
    set to $from
    if {[llength [$t tag ranges sel]]} {
        set from [$t index sel.first]
        set to [$t index sel.last]
        set selected [$t get $from $to]
        if {[regexp {^[a-z]+://\S+$} $selected]} { set url $selected } else { set text $selected }
    }
    set result [string map [list %t $text %u $url] $template]
    # The placeholder to select: the URL unless it was given.
    set mark [expr {$url eq "url" ? "%u" : "%t"}]
    set at [string first $mark $template]
    set first [string length [string map [list %t $text %u $url] [string range $template 0 $at-1]]]
    set last [expr {$first + [string length [if {$mark eq "%u"} {set url} else {set text}]]}]
    Replace $t $from $to $result $first $last
}

# The markup of the lines of the selection (or of the cursor's line).
proc formattext::Lines {t spec} {
    if {[llength [$t tag ranges sel]]} {
        set from [$t index "sel.first linestart"]
        set end [$t index sel.last]
        # (A selection ending at the start of a line does not take it.)
        if {[$t compare $end > $from] && [$t compare $end == "$end linestart"]} {
            set end [$t index "$end - 1 char"]
        }
        set to [$t index "$end lineend"]
    } else {
        set from [$t index "insert linestart"]
        set to [$t index "insert lineend"]
    }
    set lines [split [$t get $from $to] \n]
    # (An empty line: one line, empty.)
    if {![llength $lines]} { set lines [list ""] }
    lassign $spec kind open close
    switch -- $kind {
        prefix { set result [Prefix $lines $open] }
        number { set result [Number $lines] }
        line { set result [EachLine $lines $open $close] }
        block {
            # Already a block: the lines of its marks taken off, inside the
            # selection or around it.
            if {[llength $lines] > 1 && [lindex $lines 0] eq $open && [lindex $lines end] eq $close} {
                set result [lrange $lines 1 end-1]
            } elseif {[$t get "$from - 1 lines linestart" "$from - 1 lines lineend"] eq $open
                    && [$t compare $from > 1.0] && [$t compare "$to + 1 lines" <= end]
                    && [$t get "$to + 1 lines linestart" "$to + 1 lines lineend"] eq $close} {
                set from [$t index "$from - 1 lines linestart"]
                set to [$t index "$to + 1 lines lineend"]
                set result $lines
            } else {
                set result [list $open {*}$lines $close]
            }
        }
        list {
            if {[llength $lines] > 1 && [lindex $lines 0] eq $open && [lindex $lines end] eq $close} {
                set result [lmap line [lrange $lines 1 end-1] {
                    regsub {^<li>(.*)</li>$} $line {\1}
                }]
            } else {
                set result [list $open {*}[lmap line $lines {
                    if {[string trim $line] eq ""} {set line} else {string cat "<li>$line</li>"}
                }] $close]
            }
        }
    }
    set text [join $result \n]
    # An empty line made a block: the cursor inside it, else all selected.
    if {$kind eq "block" && [string trim [join $lines ""]] eq "" && [llength $result] == 3} {
        set at [expr {[string length $open] + 1}]
        Replace $t $from $to $text $at $at
    } else {
        Replace $t $from $to $text 0 [string length $text]
    }
}

# The lines with PREFIX (the empty ones left alone), or without it if all
# have it.
proc formattext::Prefix {lines prefix} {
    set marked [lsearch -all -inline -not -exact $lines ""]
    if {![llength $marked]} { return [list $prefix[join $lines ""]] }
    set n [string length $prefix]
    if {[llength [lsearch -all -inline -not -glob $marked [string map {* \\* ? \\? [ \\[} $prefix]*]] == 0} {
        return [lmap line $lines { if {$line ne ""} {string range $line $n end} }]
    }
    lmap line $lines { if {$line ne ""} {string cat "$prefix$line"} }
}

proc formattext::Number {lines} {
    set marked [lsearch -all -inline -not -exact $lines ""]
    if {[llength $marked] && [llength [lsearch -all -inline -not -regexp $marked {^\d+\. }]] == 0} {
        return [lmap line $lines { regsub {^\d+\. } $line "" }]
    }
    if {![llength $marked]} { return [list "1. [join $lines ""]"] }
    set i 0
    lmap line $lines { if {$line ne ""} {string cat "[incr i]. $line"} }
}

proc formattext::EachLine {lines open close} {
    set marked [lsearch -all -inline -not -exact $lines ""]
    set o [string length $open]
    set c [string length $close]
    set all [expr {[llength $marked] > 0}]
    foreach line $marked {
        if {[string first $open $line] != 0 || [string range $line end-[expr {$c - 1}] end] ne $close} { set all 0 }
    }
    if {$all} { return [lmap line $lines { if {$line ne ""} {string range $line $o end-$c} }] }
    if {![llength $marked]} { return [list $open[join $lines ""]$close] }
    lmap line $lines { if {$line ne ""} {string cat "$open$line$close"} }
}

# ---------------------------------------------------------- references

# A reference of KIND (ticket, checkin, branch): to the one the selection
# names, else to one chosen in a window (searched for the selection), with
# the selection as its text.  It goes where the selection (or the cursor)
# was, also if the text is edited meanwhile.
proc formattext::Reference {w kind} {
    variable opts
    set t $w.src.t
    set repo [dict get $opts($w) -repo]
    set selected ""
    if {[llength [$t tag ranges sel]]} {
        $t mark set formattextFrom sel.first
        $t mark set formattextTo sel.last
        set selected [$t get sel.first sel.last]
    } else {
        $t mark set formattextFrom insert
        $t mark set formattextTo insert
    }
    $t mark gravity formattextFrom left
    $t mark gravity formattextTo right
    if {[catch {refpick::resolve $repo $kind $selected} id]} { set id "" }
    if {$id ne ""} {
        InsertReference $w $kind $id ""
        return
    }
    # (Many lines: no search for them, the text only.)
    set query [if {[string first \n $selected] < 0} {set selected}]
    refpick::choose $w $repo $kind $query [list formattext::InsertReference $w $kind $id $selected]
}

# (ID "": the one chosen, appended.)
proc formattext::InsertReference {w kind given text {chosen ""}} {
    variable markup
    if {![winfo exists $w]} return
    set id [if {$given ne ""} {set given} else {set chosen}]
    set t $w.src.t
    set spec [dict get $markup [mimetype $w] $kind]
    lassign $spec - template withText
    set name [if {$kind eq "branch"} {set id} else {string range $id 0 9}]
    if {$text eq ""} { set text $name } elseif {$withText ne ""} { set template $withText }
    if {[mimetype $w] eq "text/html"} { set text [string map {& &amp; < &lt; > &gt;} $text] }
    set result [string map [list %h $name %u [fossil::urlquery $id] %t $text] $template]
    set auto [$t cget -autoseparators]
    $t configure -autoseparators 0
    $t edit separator
    Replace $t formattextFrom formattextTo $result [string length $result] [string length $result]
    $t edit separator
    $t configure -autoseparators $auto
    focus $t
}
