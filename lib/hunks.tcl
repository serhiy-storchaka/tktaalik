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
