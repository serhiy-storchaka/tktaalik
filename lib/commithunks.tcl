# The Commit tab: committing or stashing part of a file's changes, the
# hunks ticked in its diff (lib/hunks.tcl).  Fossil has no staging area:
# the files are written with only the changes chosen, committed or
# stashed, and written back; a stash of all the changes (a snapshot) is
# kept meanwhile, and dropped once the files are back.

namespace eval tkcommit {
    variable hunksOff           ;# array: path -> keys of the units unticked
    variable hunksSplit         ;# array: path -> keys of the hunks split
    variable shownHunks {}      ;# the hunks of the diff shown (their dicts)
    variable shownDiff ""       ;# that diff, as Fossil gave it
}

# A unit of choice is a hunk, or a part of one (a run of changes) once the
# hunk is split: its dict (as hunks::parse or hunks::parts give them), with
# hunk, the number of its hunk, and part, its number in it ("" for a whole
# hunk).

# Whether the changes of PATH can be chosen hunk by hunk: an edited file,
# no merge in progress (Fossil commits all then), and the plain diff
# against the checkout (white space ignored or inverted, the hunks are not
# the changes).
proc tkcommit::hunksChoosable {path} {
    variable files
    variable merging
    if {$merging || ![dict exists $files $path] || [dict get $files $path] ne "EDITED"} { return 0 }
    foreach a [diffArgs] {
        if {$a in {-w -Z --strip-trailing-cr --invert} || [string match --from=* $a]} { return 0 }
    }
    return 1
}

# Whether the hunk KEY of PATH is to be committed.
proc tkcommit::hunkOn {path key} {
    variable checked
    variable hunksOff
    expr {$checked($path) && !([info exists hunksOff($path)] && $key in $hunksOff($path))}
}

# Whether only part of PATH is chosen.
proc tkcommit::partly {path} {
    variable checked
    variable hunksOff
    expr {$checked($path) && [info exists hunksOff($path)] && [llength $hunksOff($path)]}
}

# The units of PATH for its HUNKS.
proc tkcommit::units {path hunks} {
    variable hunksSplit
    set split [expr {[info exists hunksSplit($path)] ? $hunksSplit($path) : {}}]
    set result {}
    set n 0
    foreach h $hunks {
        set parts [hunks::parts $h]
        if {[dict get $h key] in $split && [llength $parts] > 1} {
            set p 0
            foreach part $parts {
                lappend result [dict merge $part [dict create hunk $n part $p]]
                incr p
            }
        } else {
            lappend result [dict merge $h [dict create hunk $n part ""]]
        }
        incr n
    }
    return $result
}

# The diff of PATH (OUT, as "fossil diff" gave it) in the text D, with a
# check box on each hunk, and on each part of a hunk split; a hunk of
# several runs of changes not split yet has a mark to split it.
proc tkcommit::showHunks {d path out} {
    variable shownHunks
    variable shownDiff
    variable hunksOff
    variable hunksSplit
    set shownHunks [hunks::parse $out]
    set shownDiff $out
    # (Choices the file no longer has are forgotten.)
    set hkeys [lmap h $shownHunks { dict get $h key }]
    if {[info exists hunksSplit($path)]} {
        set hunksSplit($path) [lmap k $hunksSplit($path) { if {$k ni $hkeys} continue; set k }]
    }
    set units [units $path $shownHunks]
    set ukeys [lmap u $units { dict get $u key }]
    if {[info exists hunksOff($path)]} {
        set hunksOff($path) [lmap k $hunksOff($path) { if {$k ni $ukeys} continue; set k }]
    }
    # Where the boxes go: the line of each hunk, and of each part.
    set at {}
    foreach u $units {
        dict lappend at [dict get $u line] $u
    }
    foreach h $shownHunks n [lsearch -all $shownHunks *] {
        if {![dict exists $at [dict get $h line]]} { dict set at [dict get $h line] [list [dict create hunk $n part "" header 1]] }
    }
    set n -1
    set p ""
    set i 0
    foreach line [split $out \n] {
        set tags {}
        if {[dict exists $at $i]} {
            set u [lindex [dict get $at $i] 0]
            set n [dict get $u hunk]
            if {[dict get $u part] eq "" || [dict exists $u header]} {
                # A hunk's header: its box (of all its parts, if split).
                set p ""
                $d insert end [Box [hunkState $path $n]] [list box hbox$n hk$n] " " hk$n
            } else {
                set p [dict get $u part]
                $d insert end [Box [expr {[hunkOn $path [dict get $u key]] ? "on" : "off"}]] \
                    [list box pbox hk$n hp$n.$p] " " [list hk$n hp$n.$p]
            }
        } elseif {$p ne "" && [string index $line 0] ni {- + \\}} {
            set p ""
        }
        switch -glob -- $line {
            "+++ *" - "--- *" - "Index: *" - "=====*" { set tag meta }
            "@@*"   { set tag hunk }
            "+*"    { set tag added }
            "-*"    { set tag removed }
            default { set tag "" }
        }
        if {$n >= 0} { lappend tags hk$n }
        if {$p ne ""} { lappend tags hp$n.$p }
        $d insert end $line [concat $tag $tags]
        if {$tag eq "hunk" && [llength [hunks::parts [lindex $shownHunks $n]]] > 1
                && !([info exists hunksSplit($path)] && [dict get [lindex $shownHunks $n] key] in $hunksSplit($path))} {
            $d insert end "  " hk$n "\u2702" [list split split$n hk$n]
        }
        $d insert end \n [concat $tag $tags]
        incr i
    }
    # Greyed: the units unticked.
    foreach u $units {
        set tag [expr {[dict get $u part] eq "" ? "hk[dict get $u hunk]" : "hp[dict get $u hunk].[dict get $u part]"}]
        if {![hunkOn $path [dict get $u key]]} {
            set range [$d tag ranges $tag]
            if {[llength $range]} { $d tag add off {*}$range }
        }
    }
}

proc tkcommit::Box {state} {
    dict get {on \u2611 off \u2610 some \u25a3} $state
}

# The state of the hunk N of the diff shown: on, off, or some (of its
# parts).
proc tkcommit::hunkState {path n} {
    variable shownHunks
    set keys [lmap u [units $path $shownHunks] {
        if {[dict get $u hunk] != $n} continue
        dict get $u key
    }]
    set on [llength [lmap k $keys { if {![hunkOn $path $k]} continue; set k }]]
    expr {$on == [llength $keys] ? "on" : $on == 0 ? "off" : "some"}
}

# Tick or untick the units KEYS of the file shown together: all on if one
# is off, else all off.
proc tkcommit::toggleUnits {keys} {
    variable current
    variable shownHunks
    variable hunksOff
    variable checked
    set path $current
    if {$path eq "" || ![llength $keys]} return
    set all [lmap u [units $path $shownHunks] { dict get $u key }]
    if {![info exists hunksOff($path)]} { set hunksOff($path) {} }
    if {!$checked($path)} {
        # A file not checked: only these now.
        set checked($path) 1
        set hunksOff($path) [lmap k $all { if {$k in $keys} continue; set k }]
    } elseif {[llength [lmap k $keys { if {[hunkOn $path $k]} continue; set k }]]} {
        set hunksOff($path) [lmap k $hunksOff($path) { if {$k in $keys} continue; set k }]
    } else {
        lappend hunksOff($path) {*}$keys
        # None left: the file not checked (all of it, if checked again).
        if {![llength [lmap k $all { if {$k in $hunksOff($path)} continue; set k }]]} {
            set checked($path) 0
            set hunksOff($path) {}
        }
    }
    Redraw
    .commit.main.files.t set $path check [mark $path]
    updateStatus
}

# The diff shown again (its boxes), where it was scrolled to.
proc tkcommit::Redraw {} {
    variable current
    variable shownDiff
    set d .commit.main.diff.text
    set top [lindex [$d yview] 0]
    set left [lindex [$d xview] 0]
    set insert [$d index insert]
    $d configure -state normal
    $d delete 1.0 end
    showHunks $d $current $shownDiff
    $d configure -state disabled
    $d yview moveto $top
    $d xview moveto $left
    $d mark set insert $insert
}

# Tick or untick the hunk K of the diff shown (all its parts if split).
proc tkcommit::toggleHunk {k} {
    variable current
    variable shownHunks
    if {$current eq "" || $k < 0 || $k >= [llength $shownHunks]} return
    toggleUnits [lmap u [units $current $shownHunks] {
        if {[dict get $u hunk] != $k} continue
        dict get $u key
    }]
}

# The box or the line at IDX (a click on a box, Space): its part if the
# hunk is split and IDX is in one, else its hunk.
proc tkcommit::toggleAt {idx} {
    variable current
    variable shownHunks
    lassign [unitAt $idx] k p
    if {$k < 0} return
    if {$p eq ""} {
        toggleHunk $k
    } else {
        toggleUnits [lmap u [units $current $shownHunks] {
            if {[dict get $u hunk] != $k || [dict get $u part] ne $p} continue
            dict get $u key
        }]
    }
}

# Split the hunk at IDX into its parts (a click on its mark, the key S),
# each ticked as the hunk was.
proc tkcommit::splitAt {idx} {
    variable current
    variable shownHunks
    variable hunksSplit
    variable hunksOff
    set k [hunkAt $idx]
    if {$current eq "" || $k < 0} return
    set path $current
    set h [lindex $shownHunks $k]
    set parts [hunks::parts $h]
    if {[llength $parts] < 2} { bell; return }
    if {![info exists hunksSplit($path)]} { set hunksSplit($path) {} }
    if {[dict get $h key] in $hunksSplit($path)} return
    lappend hunksSplit($path) [dict get $h key]
    if {[info exists hunksOff($path)] && [dict get $h key] in $hunksOff($path)} {
        set hunksOff($path) [lmap k2 $hunksOff($path) { if {$k2 eq [dict get $h key]} continue; set k2 }]
        lappend hunksOff($path) {*}[lmap part $parts { dict get $part key }]
    }
    Redraw
    updateStatus
}

# The hunk at the index IDX of the diff text: its number, -1 if none.
proc tkcommit::hunkAt {idx} {
    lindex [unitAt $idx] 0
}

# The hunk and part at IDX: {number part}, part "" if not in one; -1 if
# not in a hunk.
proc tkcommit::unitAt {idx} {
    set k -1
    set p ""
    foreach tag [.commit.main.diff.text tag names $idx] {
        if {[regexp {^hk(\d+)$} $tag -> n]} { set k $n }
        if {[regexp {^hp\d+\.(\d+)$} $tag -> q]} { set p $q }
    }
    list $k $p
}

# -------------------------------------------------------- committing part

# The files of PATHS of which only part is chosen, each as a dict {path
# base work part rest ticked total}: the checkout's version, the file as
# it is, it with only the hunks ticked, with only the others; an error if
# that cannot be done.
proc tkcommit::partialFiles {paths} {
    variable root
    variable merging
    set result {}
    if {$merging} { return {} }
    foreach path $paths {
        if {![partly $path]} continue
        if {![hunksChoosable $path]} {
            error "Changes of $path are chosen, but its diff is not the plain one now\
                (white space ignored, inverted, or against another version): choose\
                the plain diff (Commit \u25b8 Diff options), or check the whole file."
        }
        lassign [fossil diff -i -N {*}[diffArgs] [filearg $path]] code out
        if {$code} { error "fossil diff failed for $path: $out" }
        # (The hunks, or their parts where split.)
        set hunks [units $path [hunks::parse $out]]
        set keys [lmap h $hunks { dict get $h key }]
        set ticked [lmap k $keys { if {![hunkOn $path $k]} continue; set k }]
        set others [lmap k $keys { if {[hunkOn $path $k]} continue; set k }]
        if {![llength $others]} continue
        set dir [fossil::tempDir]
        try {
            lassign [fossil::inDir $root {
                fossil::runTo [file join $dir base] cat -r current [filearg $path]
            }] code out
            if {$code} { error "fossil cat failed for $path: $out" }
            set base [ReadBytes [file join $dir base]]
        } finally {
            file delete -force $dir
        }
        set work [ReadBytes [file join $root $path]]
        if {[hunks::apply $base $work $hunks $keys] ne $work} {
            error "The changes of $path cannot be taken apart: its diff does not give\
                the file back (a change Fossil's diff does not show, such as line ends).\
                Check the whole file, or none of it."
        }
        lappend result [dict create path $path base $base work $work \
            part [hunks::apply $base $work $hunks $ticked] \
            rest [hunks::apply $base $work $hunks $others] \
            ticked [llength $ticked] total [llength $keys]]
    }
    return $result
}

proc tkcommit::ReadBytes {file} {
    set f [open $file rb]
    try { read $f } finally { close $f }
}

proc tkcommit::WriteBytes {file data} {
    set f [open $file wb]
    try { puts -nonewline $f $data } finally { close $f }
}

# A question about PARTS (of partialFiles): what WHAT (committed,
# stashed) gets of them.
proc tkcommit::askPartial {title parts what} {
    set lines [lmap p $parts {
        string cat "[dict get $p path]: [dict get $p ticked] of [dict get $p total] changes"
    }]
    ui::ask -title $title "Only part of [expr {[llength $parts] == 1 ? "a file" : "[llength $parts] files"}] is $what:" \
        "[join $lines \n]\n\nThe other changes stay in the checkout.  Meanwhile all\
        changes are kept in a stash, dropped when the files are back."
}

# Run SCRIPT in the caller (TITLE: of its messages) with the files of PARTS holding only their part
# (the field FIELD: part, or base for a stash), then write them back as
# FINAL (work, or rest).  A snapshot of every change is kept meanwhile and
# dropped once the files are written back; if that fails it is kept, and
# said.  0 if the snapshot could not be made (SCRIPT not run), else 1.
proc tkcommit::withPartial {title parts field final script} {
    variable root
    lassign [fossil stash snapshot -m "Tktaalik: all the changes, before taking part of them"] code out
    if {$code} {
        ui::errorBox -title $title "fossil stash snapshot failed:" $out
        return 0
    }
    set id [lindex [fossil::checkoutSql $root "SELECT max(stashid) FROM stash"] 0 0]
    set failed {}
    try {
        foreach p $parts { WriteBytes [file join $root [dict get $p path]] [dict get $p $field] }
        uplevel 1 $script
    } finally {
        foreach p $parts {
            if {[catch {WriteBytes [file join $root [dict get $p path]] [dict get $p $final]} msg]} {
                lappend failed "[dict get $p path]: $msg"
            }
        }
        if {[llength $failed]} {
            ui::errorBox -title $title "Some files could not be written back." \
                "[join $failed \n]\n\nAll the changes are in stash $id (Stash tab: Apply)."
        } else {
            fossil stash drop $id
        }
    }
    return 1
}

# ------------------------------------------------------- stashing part

# Stash the checked files, of some only the hunks ticked; the rest stays.
proc tkcommit::stashChecked {} {
    set paths [toCommit]
    if {![llength $paths]} {
        ui::infoBox -title Stash "No files are checked."
        return
    }
    if {[catch {partialFiles $paths} parts]} {
        ui::errorBox -title Stash "The changes cannot be stashed in part." $parts
        return
    }
    set what [lmap path $paths {
        set p [lsearch -inline -index 1 $parts $path]
        expr {$p eq "" ? $path : "$path: [dict get $p ticked] of [dict get $p total] changes"}
    }]
    set ::ui::f(comment) ""
    if {![ui::form .commit.stashpart "Stash the checked changes" \
            "These changes are stashed (fossil stash save) and taken out of the checkout;\
            the rest stays:\n\n[join $what \n][expr {[llength $parts] ? "\n\nMeanwhile all\
            changes are kept in another stash, dropped when the files are back." : ""}]" \
            {{comment Comment: entry}} Stash -help commit#stashing-part-of-the-changes]} return
    set args [list stash save]
    if {[string trim $::ui::f(comment)] ne ""} { lappend args -m [string trim $::ui::f(comment)] }
    foreach path $paths { lappend args [filearg $path] }
    if {[llength $parts]} {
        if {![withPartial Stash $parts part rest {
            lassign [fossil {*}$args] code out
        }]} return
    } else {
        lassign [fossil {*}$args] code out
    }
    if {$code} { ui::errorBox -title Stash "fossil stash save failed:" $out }
    foreach p $parts { unset -nocomplain ::tkcommit::hunksOff([dict get $p path]) ::tkcommit::hunksSplit([dict get $p path]) }
    refresh
    set ::tkcommit::status [expr {$code ? "Not stashed" : "Stashed"}]
}
