# HTML in a text widget: the subset that Fossil's wiki and Markdown
# renderers produce, shown with text tags.
#
#   htmltext::insert W HTML ?OPTION VALUE...?
#       Appends HTML to the text widget W.  Options:
#       -tags LIST      tags for all the text (e.g. a panel's background)
#       -margin PIXELS  the left margin of the text (lists and quotes are
#                       indented from it)
#       -font FONT      the font of the text (default TkTextFont); code
#                       and preformatted text are in TkFixedFont
#       -command CMD    called with the href when a link is clicked
#       -external CMD   called with an href: true if clicking the link opens
#                       it in the browser; such links get a small arrow
#                       after them (an image: not copied with the text).
#                       Default: links with a scheme of the web or mail
#                       (https:, mailto:...).  Without -command no link
#                       is followed, so none is external.
#       -autolink {RE CMD}
#                       text matching the regular expression RE (outside
#                       code and links) becomes a link if CMD, called with
#                       the match and its subexpressions, returns an href
#   htmltext::reset W
#       Forgets the links of W (call it when the text is deleted).
#
# Paragraphs, headings, b/strong, i/em, u, s/del, code/tt/kbd, pre,
# ul/ol/li, dl, blockquote, table rows, a, br, hr and img (its alt text)
# are shown; other tags are ignored, their content is not.

namespace eval htmltext {
    variable links           ;# W,N -> href
    variable count           ;# W -> the number of links
    variable cursor          ;# W -> its cursor outside links
    variable linkCursor hand2   ;# the cursor over links
    variable entities {
        lt < gt > amp & quot \" apos ' nbsp \u00a0 mdash \u2014 ndash \u2013
        hellip \u2026 copy \u00a9 reg \u00ae trade \u2122 laquo \u00ab
        raquo \u00bb lsquo \u2018 rsquo \u2019 ldquo \u201c rdquo \u201d
        bull \u2022 middot \u00b7 times \u00d7 rarr \u2192 larr \u2190
        uarr \u2191 darr \u2193 deg \u00b0 plusmn \u00b1 para \u00b6
        sect \u00a7 euro \u20ac
    }
}

proc htmltext::reset {w} {
    variable links
    variable count
    array unset links $w,*
    set count($w) 0
    foreach tag [$w tag names] {
        if {[string match ht-href-* $tag]} { $w tag delete $tag }
    }
}

proc htmltext::decode {text} {
    variable entities
    if {[string first & $text] < 0} { return $text }
    set out ""
    while {[regexp -indices {&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);} $text m name]} {
        lassign $m from to
        append out [string range $text 0 [expr {$from - 1}]]
        set n [string range $text {*}$name]
        if {[regexp {^#[xX]([0-9a-fA-F]+)$} $n -> hex]} {
            append out [format %c [expr {"0x$hex"}]]
        } elseif {[regexp {^#([0-9]+)$} $n -> dec]} {
            append out [format %c [scan $dec %d]]
        } elseif {[dict exists $entities $n]} {
            append out [dict get $entities $n]
        } else {
            append out [string range $text $from $to]
        }
        set text [string range $text [expr {$to + 1}] end]
    }
    append out $text
}

# The attributes of a tag: name -> value.
proc htmltext::attributes {text} {
    set result {}
    foreach {- name - v1 v2 v3} [regexp -all -inline \
            {([a-zA-Z_:-]+)\s*(=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?} $text] {
        dict set result [string tolower $name] [decode $v1$v2$v3]
    }
    return $result
}

proc htmltext::insert {w html args} {
    variable count
    set opts [dict merge {-tags {} -margin 0 -font TkTextFont -command {} -autolink {} -external {}} $args]
    if {![info exists count($w)]} { set count($w) 0 }
    styles $w
    # The state, passed to the procs below by name.
    set st [dict create w $w opts $opts bold 0 italic 0 mono 0 heading 0 \
        underline 0 strike 0 link "" pre 0 preStart 0 skip 0 quote 0 lists {} \
        cell 0 lineStart 1 gap 1 hang 0 empty 1 marker 0]
    set pos 0
    set len [string length $html]
    while {$pos < $len} {
        set lt [string first < $html $pos]
        if {$lt < 0} { set lt $len }
        if {$lt > $pos} {
            chars st [decode [string range $html $pos [expr {$lt - 1}]]]
        }
        if {$lt >= $len} break
        if {[string range $html $lt [expr {$lt + 3}]] eq "<!--"} {
            set end [string first --> $html $lt]
            set pos [expr {$end < 0 ? $len : $end + 3}]
            continue
        }
        set gt [string first > $html $lt]
        if {$gt < 0} {
            chars st [string range $html $lt end]
            break
        }
        set tag [string range $html [expr {$lt + 1}] [expr {$gt - 1}]]
        set pos [expr {$gt + 1}]
        if {[regexp {^(/?)([a-zA-Z][a-zA-Z0-9]*)(.*?)/?$} $tag -> close name rest]} {
            element st [expr {$close ne ""}] [string tolower $name] $rest
        } else {
            # Not a tag: a "<" in the text.
            chars st <$tag>
        }
    }
    # Leave the widget at the start of a line, without room after the
    # last block.
    if {![dict get $st lineStart]} { newline st }
    if {[dict get $st gap] && ![dict get $st empty]} { $w delete "end - 2 chars" }
}

# The end of a link: after one that opens outside the application, the
# arrow (part of the link: it can be clicked too).
proc htmltext::endLink {stVar} {
    upvar 1 $stVar st
    set link [dict get $st link]
    dict set st link ""
    if {"ht-external" ni $link} return
    set w [dict get $st w]
    $w image create end -image [arrow] -padx 2 -align center
    foreach tag [list {*}[dict get $st opts -tags] [marginTag st] ht-link {*}$link] {
        $w tag add $tag "end - 2 chars"
    }
    dict set st lineStart 0
}

# The arrow of external links ("\u2197"), as high as about half a line of
# text, in the colour of links: drawn once.
proc htmltext::arrow {} {
    set size [expr {max(7, int([font metrics TkTextFont -linespace] * 0.55))}]
    set name ::htmltext::arrow$size
    if {$name in [image names]} { return $name }
    image create photo $name -width $size -height $size
    set colour #0b57d0
    set t [expr {$size >= 12 ? 2 : 1}]
    set e [expr {$size - 1}]
    # The shaft, from the lower left corner to the upper right one.
    for {set i 0} {$i < $size} {incr i} {
        set x $i
        set y [expr {$e - $i}]
        $name put $colour -to $x [expr {max(0, $y - $t + 1)}] [expr {$x + 1}] [expr {$y + 1}]
    }
    # The head: along the top and down the right side.
    set h [expr {$size / 2}]
    $name put $colour -to [expr {$size - $h}] 0 $size $t
    $name put $colour -to [expr {$size - $t}] 0 $size $h
    return $name
}

# Align the columns of the table just inserted: tab stops after the widest
# cell of each column (wrapped lines go on under the last one).
proc htmltext::alignTable {stVar} {
    upvar 1 $stVar st
    variable count
    if {![dict exists $st tableStart]} return
    set w [dict get $st w]
    set start [dict get $st tableStart]
    dict unset st tableStart
    set first [expr {int($start)}]
    set last [expr {int([$w index "end - 1 char"])}]
    set gap [font measure TkTextFont "000"]
    set widths {}
    for {set l $first} {$l <= $last} {incr l} {
        set cells [split [$w get $l.0 "$l.0 lineend"] \t]
        if {[llength $cells] < 2} continue
        # (The header is bold: measured so.)
        set font [expr {[lsearch -glob [$w tag names $l.0] ht-font-*-1??] >= 0 ? "TkHeadingFont" : "TkTextFont"}]
        set i 0
        foreach cell [lrange $cells 0 end-1] {
            set width [font measure $font $cell]
            if {$i >= [llength $widths]} { lappend widths 0 }
            lset widths $i [expr {max([lindex $widths $i], $width)}]
            incr i
        }
    }
    if {![llength $widths]} return
    set x [dict get $st opts -margin]
    set stops {}
    foreach width $widths {
        incr x [expr {$width + $gap}]
        lappend stops $x
    }
    set tag ht-table[incr count($w)]
    $w tag configure $tag -tabs $stops -lmargin2 [lindex $stops end]
    $w tag add $tag $first.0 "$last.0 lineend + 1 char"
}

# The tags that do not depend on the state.
proc htmltext::styles {w} {
    if {"ht-link" in [$w tag names]} return
    set line [font metrics TkTextFont -linespace]
    $w tag configure ht-gap -font [list {*}[font actual TkTextFont] -size -[expr {$line / 2}]]
    $w tag configure ht-code -background gray90
    $w tag configure ht-quote -foreground gray30
    $w tag configure ht-rule -foreground gray60
    $w tag configure ht-strike -overstrike 1
    $w tag configure ht-underline -underline 1
    $w tag configure ht-link -foreground #0b57d0 -underline 1
    $w tag bind ht-link <Enter> [list ::apply {{w} {
        if {[$w cget -cursor] ne $::htmltext::linkCursor} { set ::htmltext::cursor($w) [$w cget -cursor] }
        $w configure -cursor $::htmltext::linkCursor
    }} $w]
    $w tag bind ht-link <Leave> [list ::apply {{w} {
        if {[info exists ::htmltext::cursor($w)]} { $w configure -cursor $::htmltext::cursor($w) }
    }} $w]
}

# The font of the current style, as a tag.
proc htmltext::fontTag {stVar} {
    upvar 1 $stVar st
    set w [dict get $st w]
    set base [dict get $st opts -font]
    if {[dict get $st mono]} { set base TkFixedFont }
    set h [dict get $st heading]
    set name ht-font-[string map {" " _} $base]-[dict get $st bold][dict get $st italic]$h
    if {$name ni [$w tag names]} {
        set font [font actual $base]
        if {$h} {
            # Headings: larger, bold.
            set size [dict get $font -size]
            set scale [lindex {1 1.6 1.4 1.2 1.1 1 1} $h]
            dict set font -size [expr {$size < 0 ? -round(-$size * $scale) : round($size * $scale)}]
            dict set font -weight bold
        }
        if {[dict get $st bold]} { dict set font -weight bold }
        if {[dict get $st italic]} { dict set font -slant italic }
        $w tag configure $name -font $font
    }
    return $name
}

# The margin of the current line, as a tag.
proc htmltext::marginTag {stVar} {
    upvar 1 $stVar st
    set w [dict get $st w]
    set level [llength [dict get $st lists]]
    set quote [dict get $st quote]
    set hang [expr {[dict get $st hang] && $level}]
    set left [dict get $st opts -margin]
    set name ht-margin-$level-$quote-$hang-$left
    if {$name ni [$w tag names]} {
        set indent [font measure TkTextFont 0000]
        set left [expr {$left + $quote * $indent}]
        set second [expr {$left + $level * $indent}]
        set first [expr {$hang ? $second - $indent : $second}]
        $w tag configure $name -lmargin1 $first -lmargin2 $second
        # A tab after a list marker goes to the text.
        if {$level} { $w tag configure $name -tabs [list $second] }
    }
    return $name
}

proc htmltext::emit {stVar text {extra {}}} {
    upvar 1 $stVar st
    if {$text eq ""} return
    set w [dict get $st w]
    set tags [list {*}[dict get $st opts -tags] [fontTag st] [marginTag st]]
    if {[dict get $st quote]} { lappend tags ht-quote }
    if {[dict get $st underline]} { lappend tags ht-underline }
    if {[dict get $st strike]} { lappend tags ht-strike }
    if {[dict get $st mono] && ![dict get $st pre]} { lappend tags ht-code }
    if {[dict get $st link] ne ""} { lappend tags ht-link {*}[dict get $st link] }
    lappend tags {*}$extra
    $w insert end $text $tags
    dict set st marker 0
    dict set st lineStart [string match *\n $text]
    dict set st gap 0
    dict set st empty 0
}

proc htmltext::newline {stVar} {
    upvar 1 $stVar st
    emit st \n
    # Lines after the first of a list item are not hanging.
    dict set st hang 0
}

# Start a block on a new line.
proc htmltext::block {stVar} {
    upvar 1 $stVar st
    if {![dict get $st lineStart]} { newline st }
}

# Some room between blocks (half a line), once.
proc htmltext::gap {stVar} {
    upvar 1 $stVar st
    block st
    if {[dict get $st gap] || [dict get $st empty]} return
    set w [dict get $st w]
    $w insert end \n [list {*}[dict get $st opts -tags] ht-gap [marginTag st]]
    dict set st gap 1
}

# Text: whitespace collapses, except in preformatted text; links are made
# of what matches -autolink.
proc htmltext::chars {stVar text} {
    upvar 1 $stVar st
    if {[dict get $st skip]} return
    if {[dict get $st pre]} {
        # The newline right after <pre> is not content.
        if {[dict get $st preStart]} { regsub {^\r?\n} $text "" text }
        dict set st preStart 0
    } else {
        regsub -all {\s+} $text " " text
        if {[dict get $st lineStart]} { set text [string trimleft $text] }
    }
    if {$text eq ""} return
    set auto [dict get $st opts -autolink]
    if {$auto eq "" || [dict get $st link] ne "" || ([dict get $st mono] && ![dict get $st pre])} {
        textLines st $text
        return
    }
    lassign $auto re cmd
    while {[regexp -indices -- $re $text match]} {
        lassign $match from to
        textLines st [string range $text 0 [expr {$from - 1}]]
        set m [string range $text $from $to]
        set href [uplevel #0 [list {*}$cmd {*}[regexp -inline -- $re $m]]]
        if {$href ne ""} {
            dict set st link [linkTag st $href]
            emit st $m
            endLink st
        } else {
            emit st $m
        }
        set text [string range $text [expr {$to + 1}] end]
    }
    textLines st $text
}

# Text line by line, so that each line has its margin.
proc htmltext::textLines {stVar text} {
    upvar 1 $stVar st
    set lines [split $text \n]
    foreach line [lrange $lines 0 end-1] {
        emit st $line
        newline st
    }
    emit st [lindex $lines end]
}

proc htmltext::linkTag {stVar href} {
    upvar 1 $stVar st
    variable links
    variable count
    set w [dict get $st w]
    set n [incr count($w)]
    set links($w,$n) $href
    set tag ht-href-$n
    set external [dict get $st opts -external]
    if {[dict get $st opts -command] eq ""} {
        set out 0
    } elseif {$external eq ""} {
        set out [regexp -nocase {^(?:https?|ftp|mailto|news):} $href]
    } else {
        set out [uplevel #0 [list {*}$external $href]]
    }
    set cmd [dict get $st opts -command]
    if {$cmd ne ""} {
        $w tag bind $tag <ButtonRelease-1> [list ::apply {{cmd href} {
            uplevel #0 [list {*}$cmd $href]
        }} $cmd $href]
    }
    if {$out} { return [list $tag ht-external] }
    return $tag
}

proc htmltext::element {stVar close name rest} {
    upvar 1 $stVar st
    if {[dict get $st skip] && !($close && $name in {script style})} return
    switch -- $name {
        script - style {
            dict set st skip [expr {!$close}]
        }
        p - div {
            if {$close} {
                block st
                if {$name eq "p"} { gap st }
            } elseif {![dict get $st marker]} {
                # (The first paragraph of a list item goes after its marker.)
                gap st
            }
        }
        h1 - h2 - h3 - h4 - h5 - h6 {
            gap st
            dict set st heading [expr {$close ? 0 : [string index $name 1]}]
            if {$close} { gap st }
        }
        b - strong { dict set st bold [expr {!$close}] }
        i - em - cite - var { dict set st italic [expr {!$close}] }
        u - ins { dict set st underline [expr {!$close}] }
        s - del - strike { dict set st strike [expr {!$close}] }
        code - tt - kbd - samp {
            if {![dict get $st pre]} { dict set st mono [expr {!$close}] }
        }
        pre {
            gap st
            dict set st pre [expr {!$close}]
            dict set st mono [expr {!$close}]
            dict set st preStart [expr {!$close}]
        }
        br { newline st }
        hr {
            gap st
            emit st [string repeat \u2500 24] ht-rule
            gap st
        }
        ul - ol - dl {
            # Room around a list, not around a list in a list.
            set lists [dict get $st lists]
            if {$close} {
                block st
                dict set st lists [set lists [lrange $lists 0 end-1]]
                if {![llength $lists]} { gap st }
            } else {
                if {![llength $lists]} { gap st } else { block st }
                dict lappend st lists [list $name 0]
            }
        }
        li - dt - dd {
            block st
            if {$close} return
            set lists [dict get $st lists]
            if {![llength $lists]} { set lists {{ul 0}} }
            lassign [lindex $lists end] type n
            lset lists end [list $type [incr n]]
            dict set st lists $lists
            switch -- $name {
                dt { dict set st hang 0; dict set st bold 1; return }
                dd { dict set st hang 0; dict set st bold 0; return }
            }
            # The marker in the hanging indent, the text at the tab stop.
            dict set st hang 1
            # (Not expr: "1.\t" would be the number 1.0.)
            emit st [if {$type eq "ol"} {string cat $n. \t} else {string cat \u2022 \t}]
            dict set st marker 1
        }
        blockquote {
            gap st
            dict incr st quote [expr {$close ? -1 : 1}]
        }
        table {
            # The cells are separated by tabs; at the end, the tab stops
            # from the widest cell of each column.
            gap st
            if {$close} {
                alignTable st
            } else {
                dict set st tableStart [[dict get $st w] index "end - 1 char"]
            }
        }
        tr {
            block st
            dict set st cell 0
        }
        td - th {
            if {$close} {
                if {$name eq "th"} { dict set st bold 0 }
                return
            }
            if {[dict get $st cell]} { emit st "\t" }
            dict incr st cell
            if {$name eq "th"} { dict set st bold 1 }
        }
        a {
            endLink st
            if {!$close} {
                set attrs [attributes $rest]
                if {[dict exists $attrs href] && [dict get $attrs href] ne ""} {
                    dict set st link [linkTag st [dict get $attrs href]]
                }
            }
        }
        img {
            set attrs [attributes $rest]
            set alt [expr {[dict exists $attrs alt] && [dict get $attrs alt] ne ""
                ? [dict get $attrs alt] : "image"}]
            set italic [dict get $st italic]
            dict set st italic 1
            emit st "\[$alt\]"
            dict set st italic $italic
        }
    }
}
