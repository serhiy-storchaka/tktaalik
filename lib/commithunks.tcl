# The Commit tab: committing or stashing part of a file's changes, the
# hunks ticked in its diff (lib/hunks.tcl).  Fossil has no staging area:
# the files are written with only the changes chosen, committed or
# stashed, and written back; a stash of all the changes (a snapshot) is
# kept meanwhile, and dropped once the files are back.

namespace eval tkcommit {
    variable hunksOff           ;# array: path -> keys of the hunks unticked
    variable shownHunks {}      ;# the hunks of the diff shown (their dicts)
}

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

# The diff of PATH (OUT, as "fossil diff" gave it) in the text D, with a
# check box on each hunk.
proc tkcommit::showHunks {d path out} {
    variable shownHunks
    variable hunksOff
    set shownHunks [hunks::parse $out]
    # (Choices of hunks the file no longer has are forgotten.)
    if {[info exists hunksOff($path)]} {
        set keys [lmap h $shownHunks { dict get $h key }]
        set hunksOff($path) [lmap k $hunksOff($path) { if {$k ni $keys} continue; set k }]
    }
    set starts [lmap h $shownHunks { dict get $h line }]
    set n -1
    set i 0
    foreach line [split $out \n] {
        if {[set k [lsearch -exact $starts $i]] >= 0} {
            set n $k
            set on [hunkOn $path [dict get [lindex $shownHunks $n] key]]
            $d insert end [expr {$on ? "\u2611" : "\u2610"}] [list box hk$n] " " hk$n
        }
        switch -glob -- $line {
            "+++ *" - "--- *" - "Index: *" - "=====*" { set tag meta }
            "@@*"   { set tag hunk }
            "+*"    { set tag added }
            "-*"    { set tag removed }
            default { set tag "" }
        }
        $d insert end $line\n [concat $tag [expr {$n >= 0 ? "hk$n" : ""}]]
        incr i
    }
    for {set k 0} {$k < [llength $shownHunks]} {incr k} { greyHunk $d $path $k }
}

proc tkcommit::greyHunk {d path k} {
    variable shownHunks
    set range [$d tag ranges hk$k]
    if {![llength $range]} return
    if {[hunkOn $path [dict get [lindex $shownHunks $k] key]]} {
        $d tag remove off {*}$range
    } else {
        $d tag add off {*}$range
    }
}

# Tick or untick the hunk K of the diff shown (a click on its box, Space).
proc tkcommit::toggleHunk {k} {
    variable current
    variable shownHunks
    variable hunksOff
    variable checked
    if {$current eq "" || $k < 0 || $k >= [llength $shownHunks]} return
    set path $current
    set keys [lmap h $shownHunks { dict get $h key }]
    set key [lindex $keys $k]
    if {![info exists hunksOff($path)]} { set hunksOff($path) {} }
    if {!$checked($path)} {
        # A file not checked: only this hunk now.
        set checked($path) 1
        set hunksOff($path) [lsearch -all -inline -exact -not $keys $key]
    } elseif {$key in $hunksOff($path)} {
        set hunksOff($path) [lsearch -all -inline -exact -not $hunksOff($path) $key]
    } else {
        lappend hunksOff($path) $key
        # None left: the file not checked (all its hunks, if checked again).
        if {![llength [lmap x $keys { if {$x in $hunksOff($path)} continue; set x }]]} {
            set checked($path) 0
            set hunksOff($path) {}
        }
    }
    set d .commit.main.diff.text
    $d configure -state normal
    for {set i 0} {$i < [llength $keys]} {incr i} {
        set at [lindex [$d tag ranges hk$i] 0]
        if {$at eq ""} continue
        $d replace $at "$at + 1 char" [expr {[hunkOn $path [lindex $keys $i]] ? "\u2611" : "\u2610"}] \
            [list box hk$i]
        greyHunk $d $path $i
    }
    $d configure -state disabled
    .commit.main.files.t set $path check [mark $path]
    updateStatus
}

# The hunk at the index IDX of the diff text: its number, -1 if none.
proc tkcommit::hunkAt {idx} {
    foreach tag [.commit.main.diff.text tag names $idx] {
        if {[regexp {^hk(\d+)$} $tag -> k]} { return $k }
    }
    return -1
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
        set hunks [hunks::parse $out]
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
    foreach p $parts { unset -nocomplain ::tkcommit::hunksOff([dict get $p path]) }
    refresh
    set ::tkcommit::status [expr {$code ? "Not stashed" : "Stashed"}]
}
