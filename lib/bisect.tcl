# The Timeline tab (lib/tktimeline.tcl): bisect -- good and bad check-ins,
# the checkout moved between them, bisect run.

# ----------------------------------------------------------------- bisect

# A bisect command in the checkout.
proc tktimeline::bisectRun {args} {
    variable root
    if {$root eq ""} { return {1 "There is no checkout."} }
    inCheckout {*}$args
}

# Whether a bisect command can update the checkout (its "auto-next"
# option, or "next"), and the checkout has changes it would merge.
proc tktimeline::bisectMoves {sub} {
    if {$sub in {next undo}} { return 1 }
    if {$sub ni {good bad skip}} { return 0 }
    lassign [bisectRun bisect options auto-next] code out
    expr {!$code && [regexp {\mon\M} $out]}
}

# Mark VERSION (or the checkout) good, bad or skipped; next; undo; reset.
proc tktimeline::bisect {sub {uuid ""}} {
    variable root
    if {$root eq ""} { bell; return }
    if {[bisectMoves $sub]} {
        lassign [inCheckout changes] code out
        if {!$code && [string trim $out] ne "" && ![ui::confirm -icon warning \
                -title Bisect "The checkout has changes." \
                "Bisect updates the checkout to the next check-in to test, and\
                    Fossil merges the changes into it."]} return
    }
    if {$sub eq "reset" && ![ui::confirm -title Bisect "Forget the bisect: the good and bad check-ins?"]} return
    set cmd [list bisect $sub]
    if {$uuid ne ""} { lappend cmd $uuid }
    lassign [bisectRun {*}$cmd] code out
    bisectShow "fossil [join $cmd]" $out $code
    changedHere
}

# The bisect window: what the last command printed (as the "display"
# option says, after "next"), the status, the log, the chart.
proc tktimeline::bisectShow {title text {failed 0}} {
    set w .timeline.bisect
    if {[tktaalik::dialogWindow $w Bisect]} {
        ttk::frame $w.f -padding 6
        pack $w.f -fill both -expand 1
        ttk::label $w.f.title -font TkHeadingFont
        text $w.f.t -width 90 -height 20 -font TkFixedFont -wrap none \
            -yscrollcommand [list $w.f.y set]
        ttk::scrollbar $w.f.y -command [list $w.f.t yview]
        ttk::frame $w.f.b
        foreach {name label cmd} {
            good Good {tktimeline::bisect good} bad Bad {tktimeline::bisect bad}
            skip Skip {tktimeline::bisect skip} next Next {tktimeline::bisect next}
            undo Undo {tktimeline::bisect undo}
            status Status {tktimeline::bisectInfo status} log Log {tktimeline::bisectInfo log}
            chart Chart {tktimeline::bisectInfo chart}
        } {
            ttk::button $w.f.b.$name -text $label -command $cmd
            pack $w.f.b.$name -side left -padx {0 4}
        }
        ttk::checkbutton $w.f.b.all -text "All" -variable tktimeline::bisectAll \
            -command {tktimeline::bisectInfo status}
        pack $w.f.b.all -side left
        ttk::button $w.f.b.close -text Close -command [list wm withdraw $w]
        pack $w.f.b.close -side right
        grid $w.f.title - -sticky w -pady {0 4}
        grid $w.f.t $w.f.y -sticky news
        grid $w.f.b - -sticky ew -pady {6 0}
        grid columnconfigure $w.f 0 -weight 1
        grid rowconfigure $w.f 1 -weight 1
    }
    $w.f.title configure -text $title -foreground [expr {$failed ? "red3" : ""}]
    $w.f.t configure -state normal
    $w.f.t delete 1.0 end
    $w.f.t insert end [string trim $text]
    $w.f.t configure -state disabled
}

# Show "bisect status" (with --all: all the check-ins), "log" or "chart".
proc tktimeline::bisectInfo {sub} {
    variable bisectAll
    set cmd [list bisect $sub]
    if {$sub eq "status" && $bisectAll} { lappend cmd --all }
    lassign [bisectRun {*}$cmd] code out
    bisectShow "fossil [join $cmd]" $out $code
}

# The bisect options: auto-next, direct-only, linear (on or off), display.
proc tktimeline::bisectOptions {} {
    variable bisectOpt
    lassign [bisectRun bisect options] code out
    if {$code} return
    foreach line [split $out \n] {
        if {[regexp {^\s*(\S+)\s+(\S+)} $line -> name value]} {
            set bisectOpt($name) [expr {$name eq "display" ? $value : $value in {on 1 yes true}}]
        }
    }
}

proc tktimeline::setBisectOption {name} {
    variable bisectOpt
    set value $bisectOpt($name)
    if {$name ne "display"} { set value [expr {$value ? "on" : "off"}] }
    lassign [bisectRun bisect options $name $value] code out
    if {$code} {
        tk_messageBox -icon error -title Bisect -message "fossil bisect options failed:" \
            -detail [string trim $out]
    }
}

# "fossil bisect run COMMAND": test each check-in with the command (exit
# status 0: good, 125: skip, other: bad), in the background.
proc tktimeline::bisectCommand {} {
    variable root
    variable bisectCmd
    variable bisectChan
    if {$root eq ""} { bell; return }
    if {[info exists bisectChan] && $bisectChan ne ""} { bell; return }
    if {![info exists bisectCmd]} { set bisectCmd "" }
    set w .timeline.bisectrun
    destroy $w
    toplevel $w
    wm title $w "Bisect: run a command"
    wm transient $w .
    ttk::frame $w.f -padding 10
    pack $w.f -fill both -expand 1
    ttk::label $w.f.l -justify left -text "A command run in the checkout for each\
        check-in to test:\nexit status 0 for good, 125 to skip, any other for bad."
    ttk::entry $w.f.e -textvariable tktimeline::bisectCmd -width 60
    ttk::frame $w.f.b
    ttk::button $w.f.b.ok -text Run -default active -command {set tktimeline::bisectAnswer 1}
    ttk::button $w.f.b.cancel -text Cancel -command {set tktimeline::bisectAnswer 0}
    pack $w.f.b.cancel $w.f.b.ok -side right -padx {4 0}
    grid $w.f.l -sticky w
    grid $w.f.e -sticky ew -pady 6
    grid $w.f.b -sticky e
    bind $w <Return> {set tktimeline::bisectAnswer 1}
    bind $w <Escape> {set tktimeline::bisectAnswer 0}
    wm protocol $w WM_DELETE_WINDOW {set tktimeline::bisectAnswer 0}
    focus $w.f.e
    variable bisectAnswer 0
    vwait ::tktimeline::bisectAnswer
    destroy $w
    set command [string trim $bisectCmd]
    if {!$bisectAnswer || $command eq ""} return
    if {[catch {fossil::arg $command}]} {
        tk_messageBox -icon info -title Bisect -message "The command cannot start with \"-\",\
            \"<\", \">\" or \"|\"."
        return
    }
    # (Without auto-next, fossil bisect run tests the same check-in again
    # and again.)
    lassign [bisectRun bisect options auto-next] code out
    if {!$code && ![regexp {\mon\M} $out]} {
        if {![ui::confirm -default ok -title Bisect \
                "Turn auto-next on?" "The bisect run moves the checkout to each\
                check-in to test only with the auto-next option (Bisect menu); without it, it\
                would test the same check-in until stopped."]} return
        bisectRun bisect options auto-next on
        bisectOptions
    }
    lassign [inCheckout changes] code out
    if {!$code && [string trim $out] ne "" && ![ui::confirm -icon warning \
            -title Bisect "The checkout has changes." \
            "The bisect run updates the checkout to each check-in to test, and\
                Fossil merges the changes into it each time."]} return
    if {[catch {fossil::inDir $root { set bisectChan [open |[list fossil bisect run $command 2>@1] r+] }} msg]} {
        set bisectChan ""
        ui::errorBox -title Bisect $msg
        return
    }
    chan close $bisectChan write
    fconfigure $bisectChan -blocking 0 -encoding utf-8
    bisectShow "fossil bisect run $command" ""
    set w .timeline.bisect
    $w.f.title configure -text "fossil bisect run $command (running)"
    ttk::button $w.f.b.stop -text Stop -command tktimeline::bisectStop
    pack $w.f.b.stop -side right -padx {0 4}
    fileevent $bisectChan readable [list tktimeline::bisectOutput $command]
}

proc tktimeline::bisectOutput {command} {
    variable bisectChan
    set w .timeline.bisect
    set text [read $bisectChan]
    $w.f.t configure -state normal
    $w.f.t insert end $text
    $w.f.t see end
    $w.f.t configure -state disabled
    if {![eof $bisectChan]} return
    fconfigure $bisectChan -blocking 1
    set failed [catch {close $bisectChan}]
    set bisectChan ""
    destroy $w.f.b.stop
    $w.f.title configure -text "fossil bisect run $command[expr {$failed ? " (failed)" : ""}]" \
        -foreground [expr {$failed ? "red3" : ""}]
    changedHere
}

proc tktimeline::bisectStop {} {
    variable bisectChan
    if {![info exists bisectChan] || $bisectChan eq ""} return
    # (Fossil; the command it runs finishes its step.)
    fossil::kill [pid $bisectChan]
}

# Stop a pull under way (the Stop button; on quit).
proc tktimeline::stopPull {} {
    variable pullChan
    if {![info exists pullChan] || $pullChan eq ""} return
    fossil::kill [pid $pullChan]
}

# On quit: what still runs (a pull, a bisect run).
proc tktimeline::stopAll {} {
    stopPull
    bisectStop
}

# The Bisect menu: its entries as there is a checkout, its options read.
proc tktimeline::bisectMenu {m} {
    variable root
    set state [expr {$root eq "" ? "disabled" : "normal"}]
    for {set i 0} {$i <= [$m index end]} {incr i} {
        if {[$m type $i] ni {separator tearoff}} { $m entryconfigure $i -state $state }
    }
    if {$root ne ""} { bisectOptions }
}
