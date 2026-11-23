# Previews of files in a pane: images (as imageview shows them), Markdown
# and Fossil wiki (rendered by Fossil), HTML (htmltext), man pages
# (formatted by groff, else mandoc, if one is installed).
#
#   preview::kind NAME          what the preview of the file NAME is, by its
#                               extension: image, unsupported (an image
#                               that cannot be shown), markdown, wiki,
#                               html, man; "" for none
#   preview::create W           the pane W (a frame)
#   preview::show W NAME WRITE ?OPTION VALUE...?
#                               the file NAME in the pane W; WRITE (a
#                               command) is called with a path to write it
#                               to, and returns {exit-code message}.  Options:
#       -repo REPO      the repository whose Fossil renders Markdown and wiki
#       -command CMD    called with the href of a link clicked
#       -external CMD   as htmltext's: links opened in the browser
#       -include CMD    for a man page: called with the name of a ".so"
#                       request, returns {exit-code text}: the file it names
#   preview::message W TEXT     TEXT in the pane instead
#   preview::formatter          the program for man pages: {groff ...} or
#                               {mandoc ...}, "" if neither is installed

namespace eval preview {
    variable opts               ;# array: pane -> the options of show
    variable man                ;# array: pane -> {source columns} of the man page shown
    variable formatter          ;# the program for man pages, once found
    variable depth 8            ;# how deep ".so" requests go
}

proc preview::kind {name} {
    switch -- [imageview::kind $name] {
        image       { return image }
        unsupported { return unsupported }
    }
    set ext [string tolower [string trimleft [file extension $name] .]]
    switch -regexp -- $ext {
        {^(md|markdown|mkd)$} { return markdown }
        {^wiki$}              { return wiki }
        {^x?html?$}           { return html }
        {^([1-9][a-z]*|n|l|man)$} { return man }
    }
    return ""
}

proc preview::create {w} {
    ttk::frame $w
    ttk::frame $w.doc
    text $w.doc.t -wrap word -state disabled -font TkTextFont -padx 6 -pady 4 -yscrollcommand [list $w.doc.y set]
    ttk::scrollbar $w.doc.y -command [list $w.doc.t yview]
    grid $w.doc.t $w.doc.y -sticky news
    grid columnconfigure $w.doc 0 -weight 1
    grid rowconfigure $w.doc 0 -weight 1
    htmltext::styles $w.doc.t
    $w.doc.t tag configure message -foreground gray40
    $w.doc.t tag configure man -font TkFixedFont
    $w.doc.t tag configure man-b -font [list {*}[font actual TkFixedFont] -weight bold]
    $w.doc.t tag configure man-i -underline 1
    $w.doc.t tag raise sel
    pack $w.doc -fill both -expand 1
    # A man page: again for another width.
    bind $w.doc.t <Configure> [list ui::later [list preview::Reformat $w]]
    return $w
}

proc preview::message {w text} {
    variable man
    unset -nocomplain man($w)
    Doc $w
    set t $w.doc.t
    $t configure -state normal
    $t delete 1.0 end
    htmltext::reset $t
    $t insert end $text message
    $t configure -state disabled
}

# The text pane shown, not the image's.
proc preview::Doc {w} {
    destroy $w.img
    if {![winfo ismapped $w.doc]} { pack $w.doc -fill both -expand 1 }
}

proc preview::show {w name write args} {
    variable opts
    variable man
    set opts($w) [dict merge {-repo "" -command "" -external "" -include ""} $args]
    unset -nocomplain man($w)
    set kind [kind $name]
    switch -- $kind {
        "" {
            message $w "No preview of this kind of file."
            return
        }
        unsupported {
            message $w "This image cannot be shown here: [Unsupported $name]"
            return
        }
    }
    set dir [fossil::tempDir]
    try {
        # (Into a file: the bytes as they are.)
        set path [file join $dir [file tail $name]]
        lassign [{*}$write $path] code out
        if {$code} {
            message $w "Cannot read $name: $out"
            return
        }
        if {$kind eq "image"} {
            if {[catch {imageview::photo $name $path} image]} {
                message $w "$name cannot be shown: $image"
                return
            }
            pack forget $w.doc
            imageview::pane $w.img $image
            pack $w.img -fill both -expand 1
            return
        }
        set f [open $path r]
        fconfigure $f -encoding utf-8
        set text [read $f]
        close $f
    } finally {
        file delete -force $dir
    }
    Doc $w
    if {$kind eq "man"} {
        set man($w) [list [Expand $w $text 0] 0]
        Reformat $w
        return
    }
    set o $opts($w)
    switch -- $kind {
        markdown { set html [fossil::render [dict get $o -repo] text/x-markdown $text] }
        wiki     { set html [fossil::render [dict get $o -repo] text/x-fossil-wiki $text] }
        html     { set html $text }
    }
    set t $w.doc.t
    $t configure -state normal
    $t delete 1.0 end
    htmltext::reset $t
    if {$html eq ""} {
        $t insert end "Fossil did not render it: the text as it is.\n\n" message $text man
    } else {
        set hopts {}
        foreach {key opt} {-command -command -external -external} {
            if {[dict get $o $key] ne ""} { lappend hopts $opt [dict get $o $key] }
        }
        htmltext::insert $t $html -margin 4 {*}$hopts
    }
    $t configure -state disabled
    $t yview moveto 0
}

# Why an image cannot be shown.
proc preview::Unsupported {name} {
    set ext [string tolower [string trimleft [file extension $name] .]]
    if {$ext eq "svg"} { return "SVG needs Tk 9." }
    if {$ext in $::imageview::others} { return "Tk reads no $ext images." }
    return "it needs the Img extension (tkimg)."
}

# The man page TEXT with its ".so" requests replaced by the files they
# name (as the -include command gives them): man.macros of Tcl and Tk,
# the pages that only point at another one.
proc preview::Expand {w text level} {
    variable opts
    variable depth
    set include [dict get $opts($w) -include]
    set out {}
    foreach line [split $text \n] {
        if {[regexp {^[.']\s*so\s+(\S+)} $line -> other]} {
            if {$include ne "" && $level < $depth} {
                lassign [{*}$include $other] code more
                if {!$code} {
                    lappend out [Expand $w $more [expr {$level + 1}]]
                    continue
                }
            }
            # (groff stops at a file it cannot find.)
            lappend out ".\\\" $line"
            continue
        }
        lappend out $line
    }
    join $out \n
}

proc preview::formatter {} {
    variable formatter
    if {![info exists formatter]} {
        set formatter ""
        if {[auto_execok groff] ne ""} {
            set formatter groff
        } elseif {[auto_execok mandoc] ne ""} {
            set formatter mandoc
        }
    }
    return $formatter
}

# The man page shown formatted for the width of the pane (when it
# changed).
proc preview::Reformat {w} {
    variable man
    if {![info exists man($w)]} return
    set t $w.doc.t
    lassign $man($w) source shown
    set char [font measure TkFixedFont 0]
    set columns [expr {max(40, min(100, ([winfo width $t] - 2 * [$t cget -padx]) / $char - 2))}]
    if {$columns == $shown} return
    set man($w) [list $source $columns]
    $t configure -state normal
    $t delete 1.0 end
    htmltext::reset $t
    set program [formatter]
    if {$program eq ""} {
        $t insert end "Neither groff nor mandoc is installed to format man pages:\
            the text as it is.\n\n" message $source man
    } elseif {[catch {Format $program $source $columns} lines]} {
        $t insert end "$program cannot format it: $lines\n\n" message $source man
    } else {
        foreach line $lines {
            Overstrike $t $line
            $t insert end \n man
        }
    }
    $t configure -state disabled
}

# The lines of SOURCE formatted by PROGRAM for COLUMNS, as a terminal
# shows them: bold as a character struck over itself, underlined over "_".
proc preview::Format {program source columns} {
    set dir [fossil::tempDir]
    try {
        set path [file join $dir page]
        set f [open $path w]
        fconfigure $f -encoding utf-8
        puts -nonewline $f $source
        close $f
        set err [file join $dir errors]
        switch -- $program {
            groff {
                # (-mandoc: man and mdoc pages; -t: tables; no hyphens.)
                set cmd [list groff -k -t -mandoc -Tutf8 -P-c -rLL=${columns}n -rHY=0 $path]
            }
            mandoc {
                set cmd [list mandoc -Tutf8 -O width=$columns $path]
            }
        }
        set p [open |[list {*}[auto_execok [lindex $cmd 0]] {*}[lrange $cmd 1 end] 2> $err] r]
        fconfigure $p -encoding utf-8
        set out [read $p]
        if {[catch {close $p} msg]} {
            set f [open $err r]
            set errors [string trim [read $f]]
            close $f
            error [if {$errors ne ""} {set errors} else {set msg}]
        }
    } finally {
        file delete -force $dir
    }
    split [string trimright $out \n] \n
}

# A line of the formatter's output into T, with its bold and underlined
# runs.
proc preview::Overstrike {t line} {
    if {[string first \b $line] < 0} {
        $t insert end $line man
        return
    }
    set run ""
    set style man
    set n [string length $line]
    for {set i 0} {$i < $n} {incr i} {
        set c [string index $line $i]
        set new man
        if {[string index $line $i+1] eq "\b"} {
            set d [string index $line $i+2]
            if {$c eq $d} {
                set new {man man-b}
            } elseif {$c eq "_"} {
                set new {man man-i}
            }
            set c $d
            incr i 2
            # (Struck more than twice: as bold.)
            while {[string index $line $i+1] eq "\b"} { incr i 2 }
        }
        if {$new ne $style} {
            if {$run ne ""} { $t insert end $run $style }
            set run ""
            set style $new
        }
        append run $c
    }
    if {$run ne ""} { $t insert end $run $style }
}
