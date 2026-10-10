# The hunks of a unified diff, and a text with only some of them applied:
# for committing or stashing part of a file's changes (Fossil has no
# staging area).
#
#   hunks::parse DIFF          the hunks of the diff of one file: a list of
#                              dicts {key old oldCount new newCount lead
#                              trail line} (old, new: the first line, from
#                              0; lead, trail: the unchanged lines around
#                              the changes; line: the header's line in
#                              DIFF, from 0; key: the hunk's text)
#   hunks::parts HUNK          the runs of changes of HUNK (a dict of
#                              hunks::parse), each a hunk of its own: its
#                              key, line (of its first change in DIFF),
#                              old, oldCount, new, newCount, lead, trail;
#                              one if the hunk has a single run
#   hunks::lines DATA          DATA split into lines with their line ends
#   hunks::apply BASE WORK HUNKS KEYS
#                              BASE with the changes of the hunks whose key
#                              is in KEYS, taken from WORK (BASE, WORK:
#                              bytes; the hunks of the diff from BASE to
#                              WORK)
#
# Only the line numbers of the diff are used, the lines themselves come
# from the files: line ends and encodings are kept byte for byte (the
# diff, read through exec, has lost its CRs).  BASE with all the hunks
# must give WORK back: the caller checks that before relying on it.

namespace eval hunks {}

proc hunks::parse {diff} {
    set result {}
    set lines [split $diff \n]
    set n [llength $lines]
    for {set i 0} {$i < $n} {incr i} {
        set header [lindex $lines $i]
        if {![regexp {^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@} $header -> old oc new nc]} continue
        if {$oc eq ""} { set oc 1 }
        if {$nc eq ""} { set nc 1 }
        # (A range of no lines starts after the line given.)
        set old [expr {$oc == 0 ? $old : $old - 1}]
        set new [expr {$nc == 0 ? $new : $new - 1}]
        set restOld $oc
        set restNew $nc
        set kinds {}
        set body [list $header]
        set j [expr {$i + 1}]
        while {($restOld > 0 || $restNew > 0) && $j < $n} {
            set line [lindex $lines $j]
            switch -- [string index $line 0] {
                - { incr restOld -1; lappend kinds - }
                + { incr restNew -1; lappend kinds + }
                \\ { lappend body $line; incr j; continue }
                default { incr restOld -1; incr restNew -1; lappend kinds " " }
            }
            lappend body $line
            incr j
        }
        set lead 0
        while {$lead < [llength $kinds] && [lindex $kinds $lead] eq " "} { incr lead }
        set trail 0
        while {$trail < [llength $kinds] - $lead && [lindex $kinds end-$trail] eq " "} { incr trail }
        lappend result [dict create key [join $body \n] old $old oldCount $oc new $new newCount $nc \
            lead $lead trail $trail line $i]
        set i [expr {$j - 1}]
    }
    return $result
}

proc hunks::parts {h} {
    set body [lrange [split [dict get $h key] \n] 1 end]
    set result {}
    set old [dict get $h old]
    set new [dict get $h new]
    # Walking the lines: a run is from a change to the next unchanged line.
    set run ""
    set i 0
    foreach line $body {
        set c [string index $line 0]
        if {$c eq "\\"} { incr i; continue }
        if {$c in {- +}} {
            if {$run eq ""} { set run [dict create old $old new $new oldCount 0 newCount 0 first $i] }
            if {$c eq "-"} { dict incr run oldCount; incr old } else { dict incr run newCount; incr new }
        } else {
            if {$run ne ""} { lappend result $run; set run "" }
            incr old
            incr new
        }
        incr i
    }
    if {$run ne ""} { lappend result $run }
    set n 0
    set parts {}
    foreach r $result {
        set part [dict create key "[dict get $h key]\n#$n" line [expr {[dict get $h line] + 1 + [dict get $r first]}] \
            old [dict get $r old] oldCount [dict get $r oldCount] new [dict get $r new] \
            newCount [dict get $r newCount] lead 0 trail 0]
        # (The last one with the hunk's unchanged lines after it: at the end
        # of the files, the last line's end goes with it.)
        if {$n == [llength $result] - 1} {
            set t [dict get $h trail]
            dict incr part oldCount $t
            dict incr part newCount $t
            dict set part trail $t
        }
        lappend parts $part
        incr n
    }
    return $parts
}

proc hunks::lines {data} {
    regexp -all -inline {[^\n]*\n|[^\n]+$} $data
}

proc hunks::apply {base work hunks keys} {
    set b [lines $base]
    set w [lines $work]
    set result ""
    set at 0
    foreach h $hunks {
        if {[dict get $h key] ni $keys} continue
        dict with h {
            set from [expr {$old + $lead}]
            set to [expr {$old + $oldCount - $trail}]
            set wfrom [expr {$new + $lead}]
            set wto [expr {$new + $newCount - $trail}]
        }
        # (At the end of both: the last line too, for its line end, which
        # the diff does not show.)
        if {$to + $trail == [llength $b] && $wto + $trail == [llength $w]} {
            set to [llength $b]
            set wto [llength $w]
        }
        append result [join [lrange $b $at $from-1] ""] [join [lrange $w $wfrom $wto-1] ""]
        set at $to
    }
    append result [join [lrange $b $at end] ""]
}
