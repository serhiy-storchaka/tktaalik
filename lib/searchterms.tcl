# The search terms of the tabs of tktaalik (Branches, Timeline):
#   word  key:value  -key:value  key:a,b  "quoted text"
# with dates (YYYY, YYYY-MM, YYYY-MM-DD, >=DATE, <DATE, A..B) and numbers
# (N, >N, <=N, N..M).  Errors are thrown as {TKFOSSIL QUERY}.

namespace eval terms {}

proc terms::error {msg} {
    throw {TKFOSSIL QUERY} $msg
}

# Split the search into {neg key value} terms:
#   -?  (key:)?  ("quoted text" | non-space characters)
proc terms::tokenize {query} {
    set re {(-?)(?:([A-Za-z_]+):)?("[^"]*"?|\S+)}
    lmap {- neg key value} [regexp -all -inline $re $query] {
        if {$key eq "" && [regexp {^([A-Za-z_]+):$} $value -> key]} {
            # "key:" alone: an empty value.
            set value ""
        } else {
            regexp {^"([^"]*)"?$} $value -> value
        }
        list [expr {$neg eq "-"}] [string tolower $key] $value
    }
}

proc terms::isGlob {text} {
    regexp {[*?\[]} $text
}

# YYYY, YYYY-MM or YYYY-MM-DD: {first-day day-after}.
proc terms::dateRange {text} {
    switch -regexp -- $text {
        {^[0-9]{4}$}                       { set start $text-01-01; set step year }
        {^[0-9]{4}-[0-9][0-9]$}            { set start $text-01;    set step month }
        {^[0-9]{4}-[0-9][0-9]-[0-9][0-9]$} { set start $text;       set step day }
        default { error "bad date \"$text\"; use YYYY, YYYY-MM or YYYY-MM-DD" }
    }
    # Tcl 9 rejects invalid dates, Tcl 8.6 normalizes them.
    if {[catch {clock scan $start -format %Y-%m-%d -timezone :UTC} t]
            || [clock format $t -format %Y-%m-%d -timezone :UTC] ne $start} {
        error "bad date \"$text\""
    }
    list $start [clock format [clock add $t 1 $step -timezone :UTC] -format %Y-%m-%d -timezone :UTC]
}

# A date term as {from before}: from <= day < before, "" for no limit.
proc terms::dateSpec {spec} {
    if {[regexp {^(.*)\.\.(.*)$} $spec -> lo hi]} {
        return [list [expr {$lo in {"" *} ? "" : [lindex [dateRange $lo] 0]}] \
            [expr {$hi in {"" *} ? "" : [lindex [dateRange $hi] 1]}]]
    }
    regexp {^(>=|<=|>|<)?(.*)$} $spec -> op text
    lassign [dateRange $text] start end
    switch -- $op {
        >  { list $end "" }
        >= { list $start "" }
        <  { list "" $start }
        <= { list "" $end }
        default { list $start $end }
    }
}

# A number term as {min max}, "" for no limit.
proc terms::numberSpec {spec} {
    if {[regexp {^(>=|<=|>|<)?0*([0-9]+)$} $spec -> op n]} {
        switch -- $op {
            >  { list [expr {$n + 1}] "" }
            >= { list $n "" }
            <  { list "" [expr {$n - 1}] }
            <= { list "" $n }
            default { list $n $n }
        }
    } elseif {[regexp {^(?:0*([0-9]+)|\*)?\.\.(?:0*([0-9]+)|\*)?$} $spec -> lo hi]} {
        list $lo $hi
    } else {
        error "bad number \"$spec\"; use N, >N, >=N, <N, <=N or N..M"
    }
}
