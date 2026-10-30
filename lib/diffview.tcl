# A diff window for the tabs of tktaalik: the changed files on the left,
# the diff on the right, unified or side by side.
#
#   diffview::run TITLE ?-dir DIR? ?-mode unified|sidebyside? ?-command CMD?
#           ?-select FILE? -- ARGS...
#       Runs "fossil diff -i ARGS" (or the command CMD ARGS, e.g. fossil
#       stash show), in DIR, in the background and shows the result in a
#       new window; with -select, at FILE.
#   diffview::show TITLE TEXT ?-mode MODE? ?-transient W?
#       Shows a unified diff (from Fossil, or a patch in git or diff -u
#       format); with -transient, kept above the window W.
#   diffview::panel W ?-mode MODE? ?-title TITLE?
#       The same view in the new frame W, in a tab (no title, no Close);
#   diffview::runIn W ?-dir DIR? ?-command CMD? ?-select FILE?
#           ?-mark FILES? ?-only FILES? ?-options 0|1? ?-done CMD? -- ARGS...
#       runs a command into it as diffview::run does, again for each one
#       (-mark: the files in bold; -only: only these files; -options 0:
#       no Options menu, ARGS carry the options; -done: CMD N run with
#       the number of files when shown); diffview::mark W FILES ?TAG?
#       (TAG hit: bold, conflict: red, warn: orange), diffview::clear W.
#
# The windows of diffview::run have Fossil's diff options in their Options
# menu (-w, -Z, --strip-trailing-cr, --invert, -c N): changing one runs the
# command again.
#
# Small diffs are shown whole, the file list jumps to a file; big ones show
# one file at a time.

namespace eval diffview {
    variable count 0            ;# windows made
    variable data               ;# array: window -> dict {files mode title}
    variable maxLines 20000     ;# more: one file at a time
    # Fossil's diff options: variable -> option.  (Context: -c N.)
    variable flags {
        space -w  eol -Z  cr --strip-trailing-cr  invert --invert
    }
}

# Split a unified diff into files: a list of {name header lines added
# deleted}.  Text before the first file (a patch's description) is a file
# named "".
proc diffview::parse {text} {
    set files {}
    set name ""
    set header {}
    set lines {}
    set added 0
    set deleted 0
    set all [split $text \n]
    set n [llength $all]
    for {set i 0} {$i < $n} {incr i} {
        set line [lindex $all $i]
        if {[string match "--- *" $line] && [string match "+++ *" [lindex $all $i+1]]} {
            # A new file: the header lines before it go with it.
            # (fossil stash show: "CHANGED name" before each file)
            set start {}
            while {[llength $lines] && [regexp {^(?:Index: |=====|diff |index |new file|deleted file|similarity |rename |old mode|new mode|(?:ADDED|DELETED?|CHANGED|EDITED|RENAMED|REMOVED) )} [lindex $lines end]]} {
                set start [linsert $start 0 [lindex $lines end]]
                set lines [lrange $lines 0 end-1]
            }
            while {[llength $lines] && [lindex $lines end] eq ""} { set lines [lrange $lines 0 end-1] }
            if {$name ne "" || [string trim [join $lines \n]] ne ""} {
                lappend files [list $name $header $lines $added $deleted]
            }
            set old [fileName [string range $line 4 end]]
            set new [fileName [string range [lindex $all $i+1] 4 end]]
            set name [if {$new eq "/dev/null"} {set old} else {set new}]
            set header [concat $start [list $line [lindex $all $i+1]]]
            set lines {}
            set added 0
            set deleted 0
            incr i
            continue
        }
        if {$name ne ""} {
            if {[string match "+*" $line]} { incr added }
            if {[string match "-*" $line]} { incr deleted }
        }
        lappend lines $line
    }
    while {[llength $lines] && [lindex $lines end] eq ""} { set lines [lrange $lines 0 end-1] }
    if {$name ne "" || [string trim [join $lines \n]] ne ""} {
        lappend files [list $name $header $lines $added $deleted]
    }
    return $files
}

# The name in a "---" or "+++" line: without a date after a tab, and
# without git's a/ and b/.
proc diffview::fileName {text} {
    set text [lindex [split $text \t] 0]
    regsub {^[ab]/} [string trim $text] {} text
    return $text
}

# ----------------------------------------------------------------- window

proc diffview::newWindow {title mode} {
    variable count
    set w .diffview[incr count]
    toplevel $w
    wm title $w $title
    ui::size $w 150 40
    panel $w -title $title -mode $mode
    ttk::button $w.bar.close -text Close -command [list destroy $w]
    pack $w.bar.close -side right -padx {4 0} -before $w.bar.sidebyside
    bind $w <Escape> [list destroy $w]
    return $w
}

# The bar, the files, the diff and the status line, in W (a toplevel, or
# a frame made here).
proc diffview::panel {w args} {
    variable data
    set opts [dict merge {-title "" -mode unified} $args]
    set title [dict get $opts -title]
    if {![winfo exists $w]} { ttk::frame $w }
    set data($w) [dict create files {} mode [dict get $opts -mode] title $title marks {} whole 1]

    ttk::frame $w.bar -padding 4
    ttk::label $w.bar.title -text $title -font TkHeadingFont
    foreach {m label} {unified Unified sidebyside "Side by side"} {
        ttk::radiobutton $w.bar.$m -text $label -value $m -style Toolbutton \
            -variable diffview::mode($w) -command [list diffview::render $w]
    }
    set ::diffview::mode($w) [dict get $opts -mode]
    pack $w.bar.title -side left
    pack $w.bar.sidebyside $w.bar.unified -side right -padx {4 0}
    # Which versions are compared (fossil diff -h), when known.
    ttk::label $w.versions -foreground gray35 -padding {8 0}

    ttk::panedwindow $w.p -orient horizontal
    ui::splitByWeights $w.p
    # The files.
    ttk::frame $w.p.files
    ttk::treeview $w.p.files.t -columns {added deleted file} -show headings \
        -selectmode browse -yscrollcommand [list $w.p.files.y set]
    $w.p.files.t tag configure hit -font TkHeadingFont
    $w.p.files.t tag configure conflict -foreground red3
    $w.p.files.t tag configure warn -foreground darkorange3
    ttk::scrollbar $w.p.files.y -command [list $w.p.files.t yview]
    set char [font measure TkDefaultFont 0]
    foreach {col heading width anchor} {added + 6 e deleted \u2212 6 e file File 30 w} {
        $w.p.files.t heading $col -text $heading -anchor $anchor
        $w.p.files.t column $col -width [expr {$width * $char}] -anchor $anchor \
            -stretch [expr {$col eq "file"}]
    }
    grid $w.p.files.t $w.p.files.y -sticky news
    grid columnconfigure $w.p.files 0 -weight 1
    grid rowconfigure $w.p.files 0 -weight 1
    # The diff: one text, or two side by side with one scroll bar.
    ttk::frame $w.p.diff
    foreach side {u l r} {
        text $w.p.diff.$side -font TkFixedFont -wrap none -state disabled -width 40 \
            -xscrollcommand [list $w.p.diff.x$side set] \
            -yscrollcommand [list diffview::scrolled $w $side]
        ttk::scrollbar $w.p.diff.x$side -orient horizontal -command [list $w.p.diff.$side xview]
        set d $w.p.diff.$side
        $d tag configure added -background #e6ffec
        $d tag configure removed -background #ffebe9
        $d tag configure addedText -foreground darkgreen
        $d tag configure removedText -foreground darkred
        $d tag configure hunk -foreground blue4 -background gray95
        $d tag configure meta -foreground gray45
        $d tag configure file -font TkHeadingFont -background gray88 -spacing1 6 -spacing3 4
        $d tag configure lineno -foreground gray55
        $d tag configure filler -background gray94
        # The selection over the colours: tags made later are above it.
        $d tag raise sel
    }
    ttk::scrollbar $w.p.diff.y -command [list diffview::yview $w]
    $w.p add $w.p.files -weight 1
    $w.p add $w.p.diff -weight 4

    ttk::label $w.status -padding {6 2} -anchor w
    pack $w.bar -fill x
    pack $w.status -side bottom -fill x
    pack $w.p -fill both -expand 1

    bind $w.p.files.t <<TreeviewSelect>> [list diffview::fileSelected $w]
    popup::attach $w.p.files.t [list diffview::filesMenu $w]
    popup::copyKey $w.p.files.t [list diffview::listedName $w]
    bind $w <Destroy> [list diffview::forget $w %W]
    layout $w
    return $w
}

proc diffview::forget {w window} {
    variable data
    if {$window ne $w} return
    if {[info exists data($w)] && [dict exists $data($w) chan]} { catch {close [dict get $data($w) chan]} }
    unset -nocomplain data($w) ::diffview::mode($w)
    array unset ::diffview::opt $w,*
}

# The Options menu of a window of diffview::run: Fossil's diff options.
# The gdiff-command setting where the diff runs (DIR, or -R in ARGS).
proc diffview::externalSetting {dir arglist} {
    set i [lsearch -exact $arglist -R]
    set where [expr {$i >= 0 ? [list -R [lindex $arglist $i+1]] : {}}]
    lassign [fossil::run -dir $dir settings gdiff-command {*}$where] code out
    if {$code || ![regexp {^gdiff-command\s+\([^)]*\)\s+(.*)$} [string trim $out] -> value]} { return "" }
    return [string trim $value]
}

# The External diff button, for the commands that have a gdiff variant.
proc diffview::externalButton {w} {
    variable data
    if {[gdiffCommand $w] ne ""} {
        ttk::button $w.bar.external -text "External diff" -command [list diffview::external $w]
        pack $w.bar.external -side right -padx {4 0} \
            -before [expr {[winfo exists $w.bar.options] ? "$w.bar.options" : "$w.bar.sidebyside"}]
        set dir [dict get $data($w) dir]
        set setting [externalSetting $dir [dict get $data($w) args]]
        icons::tooltip $w.bar.external [expr {$setting eq ""
            ? "In Fossil's own graphical diff (the gdiff-command setting is not set)"
            : "In $setting (the gdiff-command setting)"}]
    }
}

proc diffview::optionsMenu {w} {
    variable flags
    set m $w.bar.options.m
    ttk::menubutton $w.bar.options -text Options -menu $m -direction below
    menu $m -tearoff 0
    foreach {var label} {
        space  "Ignore all white space (-w)"
        eol    "Ignore white space at line ends (-Z)"
        cr     "Ignore carriage returns (--strip-trailing-cr)"
        invert "Invert: the other way round (--invert)"
    } {
        set ::diffview::opt($w,$var) 0
        $m add checkbutton -label $label -variable ::diffview::opt($w,$var) \
            -command [list diffview::rerun $w]
    }
    $m add separator
    # (Without -c: Fossil's default, 5 lines.)
    set ::diffview::opt($w,context) ""
    $m add cascade -label "Lines of context" -menu $m.context
    menu $m.context -tearoff 0
    foreach n {"" 0 1 3 10 25 100 -1} {
        set label [expr {$n eq "" ? "Default (5)" : $n < 0 ? "Whole files" : $n}]
        $m.context add radiobutton -label $label -value $n \
            -variable ::diffview::opt($w,context) -command [list diffview::rerun $w]
    }
    pack $w.bar.options -side right -padx {4 0} -before $w.bar.sidebyside
}

# The options chosen in window w, as arguments of fossil.
proc diffview::optionArgs {w} {
    variable flags
    set args {}
    if {![info exists ::diffview::opt($w,context)]} { return {} }
    foreach {var flag} $flags {
        if {$::diffview::opt($w,$var)} { lappend args $flag }
    }
    if {$::diffview::opt($w,context) ne ""} { lappend args -c $::diffview::opt($w,context) }
    return $args
}

# Run the command of window w (again, with its options).
proc diffview::start {w} {
    variable data
    if {[dict exists $data($w) chan]} { catch {close [dict get $data($w) chan]} }
    $w.status configure -text "Comparing\u2026"
    # (fossil diff: with which versions, -h.)
    set versions [expr {[dict get $data($w) command] eq {fossil diff -i} ? "-h" : ""}]
    fossil::inDir [dict get $data($w) dir] {
        # (The options before the arguments: those can end with file names.)
        set cmd [list {*}[fossil::command [dict get $data($w) command]] {*}$versions {*}[optionArgs $w] \
            {*}[dict get $data($w) args] << "" 2>@1]
        set chan [fossil::lenient [open |$cmd r]]
    }
    dict set data($w) chan $chan
    fconfigure $chan -blocking 0 -encoding utf-8 -translation auto
    fileevent $chan readable [list diffview::readDiff $w $chan ""]
}

# The same diff in the external diff program (the gdiff-command setting;
# without it Fossil's own): the gdiff variant of the command, in the
# background.  "" if the command has none.
proc diffview::gdiffCommand {w} {
    variable data
    set map {
        {fossil diff -i} {fossil gdiff}
        {fossil stash show} {fossil stash gshow}
        {fossil stash diff} {fossil stash gdiff}
        {fossil patch diff -f} {fossil patch gdiff -f}
    }
    set c [dict get $data($w) command]
    if {[dict exists $map $c]} {dict get $map $c}
}

proc diffview::external {w} {
    variable data
    set g [gdiffCommand $w]
    if {$g eq ""} return
    # (Not -i: with it Fossil ignores gdiff-command, and prints a diff.)
    set args [lsearch -all -inline -not -exact [dict get $data($w) args] -i]
    if {[catch {fossil::inDir [dict get $data($w) dir] {
        set cmd [list {*}[fossil::command $g] {*}[optionArgs $w] {*}$args << "" &]
        exec {*}$cmd
    }} msg]} {
        ui::errorBox -parent $w -title "External diff" "fossil gdiff failed:" $msg
    }
}

proc diffview::rerun {w} {
    variable data
    # Keep the file shown.
    set t $w.p.files.t
    set i [lindex [$t selection] 0]
    if {$i ne ""} { dict set data($w) select [$t set $i file] }
    start $w
}

# One text for a unified diff, two for side by side.
proc diffview::layout {w} {
    set f $w.p.diff
    foreach c [winfo children $f] { grid forget $c }
    if {$::diffview::mode($w) eq "unified"} {
        grid $f.u $f.y -sticky news
        grid $f.xu -sticky ew
        grid columnconfigure $f 0 -weight 1 -uniform {}
        grid columnconfigure $f 1 -weight 0 -uniform {}
        grid columnconfigure $f 2 -weight 0 -uniform {}
    } else {
        grid $f.l $f.r $f.y -sticky news
        grid $f.xl $f.xr -sticky ew
        grid columnconfigure $f 0 -weight 1 -uniform side
        grid columnconfigure $f 1 -weight 1 -uniform side
        grid columnconfigure $f 2 -weight 0 -uniform {}
    }
    grid rowconfigure $f 0 -weight 1
}

# The scroll bar moves the shown texts; a text scrolled (by the wheel, the
# keys) moves the scroll bar and the other text.
proc diffview::yview {w args} {
    if {$::diffview::mode($w) eq "unified"} {
        $w.p.diff.u yview {*}$args
    } else {
        $w.p.diff.l yview {*}$args
        $w.p.diff.r yview {*}$args
    }
}

proc diffview::scrolled {w side first last} {
    if {![winfo exists $w.p.diff.y]} return
    $w.p.diff.y set $first $last
    if {$side eq "l"} {
        $w.p.diff.r yview moveto $first
    } elseif {$side eq "r"} {
        $w.p.diff.l yview moveto $first
    }
}

# ----------------------------------------------------------------- showing

proc diffview::show {title text args} {
    set opts [dict merge {-mode unified -transient ""} $args]
    set w [newWindow $title [dict get $opts -mode]]
    # (Above that window, as long as it is open: viewers of attachments,
    # which a click in the list would cover.)
    if {[dict get $opts -transient] ne ""} { wm transient $w [dict get $opts -transient] }
    setText $w $text
    return $w
}

proc diffview::run {title args} {
    set mode unified
    set i [lsearch -exact $args -mode]
    if {$i >= 0 && $i < [lsearch -exact $args --]} {
        set mode [lindex $args $i+1]
        set args [lreplace $args $i $i+1]
    }
    set w [newWindow $title $mode]
    runIn $w {*}$args
    return $w
}

proc diffview::runIn {w args} {
    variable data
    set opts [dict create -dir "" -command {fossil diff -i} -select "" -mark {} -options 1 -done ""]
    dict unset data($w) only
    while {[llength $args] && [lindex $args 0] ne "--"} {
        set args [lassign $args opt value]
        dict set opts $opt $value
    }
    set args [lrange $args 1 end]
    dict set data($w) select [dict get $opts -select]
    dict set data($w) marks [dict create hit [dict get $opts -mark]]
    if {[dict exists $opts -only]} { dict set data($w) only [dict get $opts -only] }
    dict set data($w) dir [dict get $opts -dir]
    dict set data($w) command [dict get $opts -command]
    dict set data($w) done [dict get $opts -done]
    if {[dict get $opts -options] && ![winfo exists $w.bar.options]} { optionsMenu $w }
    # The diff options among the arguments (the Commit tab's): ticked in
    # the menu instead, so that they can be changed here.
    variable flags
    set rest {}
    for {set i 0} {$i < [llength $args]} {incr i} {
        set a [lindex $args $i]
        # (Not lsearch -stride: Tcl 8.6 has none.)
        set var ""
        foreach {v flag} $flags { if {$flag eq $a} { set var $v } }
        if {![winfo exists $w.bar.options]} {
            lappend rest $a
        } elseif {$var ne ""} {
            set ::diffview::opt($w,$var) 1
        } elseif {$a in {-c --context} && $i + 1 < [llength $args]} {
            set ::diffview::opt($w,context) [lindex $args [incr i]]
        } else {
            lappend rest $a
        }
    }
    dict set data($w) args $rest
    if {![winfo exists $w.bar.external]} { externalButton $w }
    start $w
    return $w
}

# Nothing shown (and the command running stopped).
proc diffview::clear {w} {
    variable data
    if {[dict exists $data($w) chan]} {
        catch {close [dict get $data($w) chan]}
        dict unset data($w) chan
    }
    dict set data($w) files {}
    $w.p.files.t delete [$w.p.files.t children {}]
    pack forget $w.versions
    render $w
    $w.status configure -text ""
}

# The files FILES marked in the list with TAG (instead of the ones marked
# with it before).
proc diffview::mark {w files {tag hit}} {
    variable data
    dict set data($w) marks $tag $files
    set t $w.p.files.t
    foreach item [$t children {}] {
        set name [listedName $w $item]
        $t item $item -tags [lmap {tag files} [dict get $data($w) marks] {
            if {$name ni $files} continue
            set tag
        }]
    }
}

proc diffview::readDiff {w chan text} {
    if {![winfo exists $w]} {
        catch {close $chan}
        return
    }
    variable data
    # (A run replaced by another one, with other options.)
    if {![dict exists $data($w) chan] || [dict get $data($w) chan] ne $chan} {
        catch {close $chan}
        return
    }
    append text [::read $chan]
    if {![eof $chan]} {
        fileevent $chan readable [list diffview::readDiff $w $chan $text]
        return
    }
    catch {close $chan}
    dict unset data($w) chan
    setText $w [regsub {\n?child process exited abnormally$} $text ""]
}

proc diffview::setText {w text} {
    variable data
    # The versions compared (diff -h): above the diff, not in it.
    set from ""
    set to ""
    pack forget $w.versions
    if {[regexp -line {^Fossil-Diff-From:\s+(.*)$} $text -> from]
            && [regexp -line {^Fossil-Diff-To:\s+(.*)$} $text -> to]} {
        regsub -line {^Fossil-Diff-From:.*\n^Fossil-Diff-To:.*\n(?:^-+\n)?} $text "" text
        if {$to eq "(workdir)"} { set to "the checkout's files" }
        $w.versions configure -text "From [string trim $from]  \u2192  to [string trim $to]"
        pack $w.versions -after $w.bar -fill x
    }
    set files [parse $text]
    if {[dict exists $data($w) only]} {
        set only [dict get $data($w) only]
        set files [lmap f $files { if {[lindex $f 0] ni $only} continue; set f }]
    }
    dict set data($w) files $files
    set t $w.p.files.t
    $t delete [$t children {}]
    set added 0
    set deleted 0
    set lines 0
    set i 0
    foreach f $files {
        lassign $f name header body a d
        set label [if {$name eq ""} {string cat "(description)"} else {set name}]
        $t insert {} end -id $i -values [list [expr {$a ? $a : ""}] [expr {$d ? $d : ""}] $label]
        incr added $a
        incr deleted $d
        incr lines [llength $body]
        incr i
    }
    variable maxLines
    dict set data($w) whole [expr {$lines <= $maxLines}]
    # Not a diff (a text file shown here): the text alone, no file list.
    set plain [expr {[llength $files] == 1 && [lindex $files 0 0] eq ""}]
    if {$plain && "$w.p.files" in [$w.p panes]} {
        $w.p forget $w.p.files
    } elseif {!$plain && "$w.p.files" ni [$w.p panes]} {
        $w.p insert 0 $w.p.files -weight 1
    }
    mark $w [if {[dict exists $data($w) marks hit]} {dict get $data($w) marks hit}]
    if {![llength $files]} {
        set msg [string trim $text]
        $w.status configure -text [expr {$msg eq "" ? "No differences." : $msg}]
    } else {
        $w.status configure -text "Text: [llength [lindex $files 0 2]] lines (not a diff)"
    }
    if {[llength $files] && !$plain} {
        $w.status configure -text "[llength $files] file[expr {[llength $files] == 1 ? "" : "s"}],\
            +$added \u2212$deleted[expr {[dict get $data($w) whole] ? "" : "  \u00b7  big: one file at a time"}]"
    }
    render $w
    if {[llength $files]} {
        # The file asked for, else the first.
        set first 0
        if {[dict exists $data($w) select]} {
            set i [lsearch -exact -index 0 $files [dict get $data($w) select]]
            if {$i >= 0} { set first $i }
        }
        $t selection set $first
        $t focus $first
        $t see $first
        fileSelected $w
    }
    if {[dict exists $data($w) done] && [dict get $data($w) done] ne ""} {
        uplevel #0 [list {*}[dict get $data($w) done] [llength [lsearch -all -inline -not -exact -index 0 $files ""]]]
    }
}

proc diffview::fileSelected {w} {
    variable data
    set i [lindex [$w.p.files.t selection] 0]
    if {$i eq ""} return
    if {![dict get $data($w) whole]} {
        render $w $i
        return
    }
    foreach side {u l r} {
        set d $w.p.diff.$side
        if {"f$i" in [$d mark names]} { $d yview f$i }
    }
}

# Show all files (or file $only), unified or side by side.
proc diffview::render {w {only ""}} {
    variable data
    layout $w
    set files [dict get $data($w) files]
    if {$only eq "" && ![dict get $data($w) whole]} {
        set only [lindex [$w.p.files.t selection] 0]
        if {$only eq ""} { set only 0 }
    }
    foreach side {u l r} {
        $w.p.diff.$side configure -state normal
        $w.p.diff.$side delete 1.0 end
    }
    set i 0
    foreach f $files {
        if {$only eq "" || $i == $only} {
            if {$::diffview::mode($w) eq "unified"} {
                unified $w.p.diff.u $i $f
            } else {
                sideBySide $w.p.diff.l $w.p.diff.r $i $f
            }
        }
        incr i
    }
    foreach side {u l r} { $w.p.diff.$side configure -state disabled }
}

proc diffview::unified {d i f} {
    lassign $f name header body
    $d mark set f$i end-1c
    $d mark gravity f$i left
    if {$name ne ""} { $d insert end "$name\n" file }
    foreach line $header { $d insert end $line\n meta }
    foreach line $body {
        switch -glob -- $line {
            "@@*" { $d insert end $line\n hunk }
            "+*"  { $d insert end $line\n {added addedText} }
            "-*"  { $d insert end $line\n {removed removedText} }
            "\\*" { $d insert end $line\n meta }
            default { $d insert end $line\n }
        }
    }
}

# Two columns with the line numbers; a change is a row of removed lines
# next to the added ones, the shorter side filled up.
proc diffview::sideBySide {l r i f} {
    lassign $f name header body
    foreach d [list $l $r] {
        $d mark set f$i end-1c
        $d mark gravity f$i left
        $d insert end "[if {$name eq ""} {string cat "(description)"} else {set name}]\n" file
    }
    if {$name eq ""} {
        # A patch's description: on the left only.
        foreach line $body {
            $l insert end $line\n
            $r insert end \n filler
        }
        return
    }
    set old 0
    set new 0
    set minus {}
    set plus {}
    # \0: the end, after the last change.
    foreach line [concat $body [list \0]] {
        if {[string match "-*" $line]} { lappend minus [string range $line 1 end]; continue }
        if {[string match "+*" $line]} { lappend plus [string range $line 1 end]; continue }
        # The end of a change: its rows.
        set rows [expr {max([llength $minus], [llength $plus])}]
        for {set k 0} {$k < $rows} {incr k} {
            if {$k < [llength $minus]} {
                $l insert end [format "%5d " [incr old]] {removed lineno} \
                    [lindex $minus $k]\n {removed removedText}
            } else {
                $l insert end \n filler
            }
            if {$k < [llength $plus]} {
                $r insert end [format "%5d " [incr new]] {added lineno} \
                    [lindex $plus $k]\n {added addedText}
            } else {
                $r insert end \n filler
            }
        }
        set minus {}
        set plus {}
        if {$line eq "\0" || $line eq ""} continue
        if {[regexp {^@@ -([0-9]+)(?:,[0-9]+)? \+([0-9]+)} $line -> o n]} {
            set old [expr {$o - 1}]
            set new [expr {$n - 1}]
            $l insert end $line\n hunk
            $r insert end $line\n hunk
        } elseif {[string match " *" $line]} {
            set text [string range $line 1 end]
            $l insert end [format "%5d " [incr old]] lineno $text\n
            $r insert end [format "%5d " [incr new]] lineno $text\n
        } elseif {[string match "\\*" $line]} {
            # "\ No newline at end of file"
        } else {
            $l insert end $line\n meta
            $r insert end $line\n meta
        }
    }
}

# The name of a file in the list of the diff W (Ctrl+C).
proc diffview::listedName {w item} {
    variable data
    lindex [dict get $data($w) files] $item 0
}

# The context menu of a file of the diff.
proc diffview::filesMenu {w m item} {
    variable data
    set file [lindex [dict get $data($w) files] $item]
    lassign $file name header body
    popup::copy $m "Copy its diff" [join [concat $header $body] \n]
}
