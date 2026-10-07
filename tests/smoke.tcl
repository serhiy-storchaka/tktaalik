# The smoke test (tests/smoke.sh runs it): every tab and window of the
# application on the repository TKTAALIK_REPO, which is only read, the first
# item of each list selected; the timings, row counts and status lines are
# printed.  It fails on an error, a red status line or an error message.
source [file join [file dirname [info script]] common.tcl]
# Errors are counted, not fatal: the other tabs are still tried.
set ::errors 0
proc bgerror {msg} {
    incr ::errors
    puts "FAIL background error: [string map {\n { | }} [string range $::errorInfo 0 400]]"
}
proc tk_messageBox {args} {
    set icon [expr {[dict exists $args -icon] ? [dict get $args -icon] : "info"}]
    set text "[dict get $args -message] [expr {[dict exists $args -detail] ? [dict get $args -detail] : ""}]"
    if {$icon eq "error"} {
        incr ::errors
        puts "FAIL message: $text"
    } else {
        puts "  message: $text"
    }
    return ok
}
# Not a repository: no dialog to wait in, the start fails.
proc tk_getOpenFile {args} { return "" }
proc ms {script} { expr {[lindex [time {uplevel #0 $script}] 0] / 1000} }
proc step {label script} {
    if {[catch {uplevel #0 $script} result]} {
        incr ::errors
        puts "FAIL $label: [string map {\n { | }} [string range $::errorInfo 0 400]]"
        return -
    }
    return $result
}

set start [step start {ms {tktaalik::main tickets [list $T(repo)]; update}}]
wm geometry . 1270x900+0+0
puts "  [file tail $T(repo)]: started in $start ms ([wm title .])"
set lists {
    timeline .timeline.main.list.t  tickets .tickets.main.list.t
    branches .branches.main.list.t  tags .tags.main.list.t
    files .files.main.tree.t        commit .commit.main.files.t
    stash .stash.main.list.t        wiki .wiki.main.list.t
    forum .forum.main.list.t
}
set red {}
dict for {tab list} $lists {
    if {[.nb tab .$tab -state] eq "disabled"} {
        puts [format "  %-9s disabled (no checkout)" $tab]
        continue
    }
    set t [step "tab $tab" "ms {tktaalik::show $tab; update; update}"]
    set rows [expr {[winfo exists $list] ? [llength [$list children {}]] : "-"}]
    set text ""
    foreach w [list .$tab.status .$tab.b.status] {
        if {![winfo exists $w]} continue
        set var [$w cget -textvariable]
        set text [expr {$var ne "" ? [set ::$var] : [$w cget -text]}]
        if {![catch {$w cget -foreground} fg] && $fg eq "red3"} { lappend red "$tab: $text" }
    }
    puts [format "  %-9s %5s ms  %6s rows  %s" $tab $t $rows [string range $text 0 90]]
    # The details of the first item.
    if {[winfo exists $list] && [llength [$list children {}]]} {
        step "select in $tab" [list apply {{list} {
            $list selection set [lrange [$list children {}] 0 0]
            update; update
        }} $list]
    }
}
# The Search tab: a search over everything.
set t [step "search" {ms {
    tktaalik::show search; update
    set tkfulltext::query "fix crash"
    tkfulltext::search
    waitUntil {![dict size $tkfulltext::running]}
    update
}}]
puts [format "  %-9s %5s ms  %6s hits  %s" search $t [llength $tkfulltext::results] [string range $tkfulltext::status 0 90]]
foreach {ns name} {tkinfo Information tksettings Settings tkusers Users tkremotes Remotes
        tkuv {Unversioned files}} {
    set t [step "window $name" "ms {${ns}::window; update}"]
    set text [expr {[info exists ${ns}::status] ? [set ${ns}::status] : ""}]
    puts [format "  %-12s %5s ms  %s" $name $t [string range $text 0 90]]
}
check "no red status lines: $red" {![llength $red]}
check "no errors ($::errors)" {$::errors == 0}
done
