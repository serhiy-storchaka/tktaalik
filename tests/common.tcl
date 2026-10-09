# The common part of the tests (tests/run.sh runs them): the application
# sourced without starting it, its settings in a temporary directory, and
# check/done for the results.  The environment:
#
#   TKTAALIK_REPO     a copy of the Tk repository (tk.fossil), only read
#   TKTAALIK_REPO2    optional: a repository with another ticket schema
#   TKTAALIK_FORUM    optional: a repository with a forum (the Fossil forum)
#   TKTAALIK_SCRATCH  a scratch checkout (tests/scratch.sh), for the tests
#                     that write; never the real repository
#   TKTAALIK_TMP      where the tests keep their files
#   TKTAALIK_XBUTTON  optional: the XTEST helper (tests/xbutton.c)

set ::tktaalik_test 1
# Windows: the files the tests write (open in their own scripts, at the
# top level) with LF line endings, as on the other systems: Fossil refuses
# to commit CR/LF ones, and diffs would be of every line.  The
# application's own files are left as they are.
if {$::tcl_platform(platform) eq "windows"} {
    rename open ::TestsOpen
    proc open {name args} {
        set chan [::TestsOpen $name {*}$args]
        if {[uplevel 1 {namespace current}] eq "::" && [lindex $args 0] in {w a w+ a+ r+}} {
            fconfigure $chan -translation lf
        }
        return $chan
    }
    # A posted menu runs a loop of its own until the user closes it: a
    # test would wait forever.  Only what opening it runs, the
    # -postcommand; the entries can be read as on the other systems.  (Loaded
    # first, so that menu.tcl does not bring the real one back.)
    auto_load tk_popup
    proc tk_popup {menu x y {entry {}}} {
        uplevel #0 [$menu cget -postcommand]
    }
}
fconfigure stdout -buffering line
set T(dir) [file dirname [file normalize [info script]]]
set T(name) [file rootname [file tail $::argv0]]
foreach {key var} {repo TKTAALIK_REPO repo2 TKTAALIK_REPO2 forum TKTAALIK_FORUM scratch TKTAALIK_SCRATCH
        xbutton TKTAALIK_XBUTTON tmp TKTAALIK_TMP} {
    set T($key) [expr {[info exists ::env($var)] ? $::env($var) : ""}]
}
if {$T(repo) eq ""} {
    puts stderr "TKTAALIK_REPO is not set: see tests/run.sh"
    exit 2
}
if {$T(tmp) eq ""} { set T(tmp) [file join [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}] tktaalik-tests] }
set T(tmp) [file join $T(tmp) $T(name)]
file delete -force $T(tmp)
file mkdir $T(tmp)
set T(passed) 0
set T(failed) 0

proc bgerror {msg} {
    puts "FAIL background error: $::errorInfo"
    exit 3
}

source [file join $T(dir) .. tktaalik]
set tktaalik::configFile $T(tmp)/app.conf
# (Every namespace with a settings file: in the temporary directory.)
foreach ns [namespace children ::] {
    if {[info exists ${ns}::configFile]} { set ${ns}::configFile $T(tmp)/[namespace tail $ns].conf }
}

proc check {label cond} {
    global T
    if {[uplevel 1 [list expr $cond]]} {
        puts "ok   $label"
        incr T(passed)
    } else {
        puts "FAIL $label"
        incr T(failed)
    }
}

# Skip the whole test if a setting it needs is missing.
proc need {key} {
    global T
    if {$T($key) eq ""} {
        puts "== $T(name): skipped (no [string toupper TKTAALIK_$key])"
        exit 0
    }
}

# Skip the whole test if Fossil's "fossil sql" lacks the search functions
# (Fossil 2.28 and newer: see fossil::hasSearch).
proc needSearch {} {
    global T
    if {![fossil::hasSearch $T(repo)]} {
        puts "== $T(name): skipped (this Fossil's \"fossil sql\" has no search functions)"
        exit 0
    }
}

proc done {} {
    global T
    puts "== $T(name): $T(passed) passed, $T(failed) failed"
    exit [expr {$T(failed) ? 1 : 0}]
}

# ------------------------------------------------------------------ kit
#
# For every test (one that needs something else defines its own):
#
#   tk_messageBox       faked: the message appended to ::boxes, all the
#                       options to ::boxArgs, the detail to ::details.  The
#                       answer: ::answers by message, else by type (ok,
#                       okcancel, yesno, yesnocancel), else ::answer ("ok";
#                       in a yes/no box "ok" is Yes and "cancel" No)
#   tk_getSaveFile      $::saveTo ("" if unset)
#   tk_getOpenFile      $::openFrom ("" if unset)
#   fossil::browse      no browser: the URL appended to ::browsed
#   start TAB ?PATH? ?SIZE?
#                       the application on PATH (the repository by default),
#                       tab TAB shown, the window SIZE (1200x900)
#   waitUntil COND ?MS? events handled until COND (an expression, in the
#                       caller) is true; after MS (30000) a failure, and the
#                       test ends
#   whenOpen W SCRIPT   SCRIPT (global) as soon as the window W is shown:
#                       for the answers in a modal dialog
#   labels M            the labels of the entries of menu M
#   sql Q ?REPO?        fossil::sql on REPO, by default $::R if set, else
#                       the repository
#   fossilIn DIR ARG... fossil ARG... run in DIR: its output (an error's
#                       too), trimmed

set ::boxes {}
set ::boxArgs {}
set ::details {}
set ::answers {}
set ::answer ok
set ::browsed {}

proc tk_messageBox {args} {
    set m [expr {[dict exists $args -message] ? [dict get $args -message] : ""}]
    lappend ::boxes $m
    lappend ::boxArgs $args
    if {[dict exists $args -detail]} { lappend ::details [dict get $args -detail] }
    set type [expr {[dict exists $args -type] ? [dict get $args -type] : "ok"}]
    if {[dict exists $::answers $m]} {
        set a [dict get $::answers $m]
    } elseif {[dict exists $::answers $type]} {
        set a [dict get $::answers $type]
    } else {
        set a $::answer
    }
    switch -- $type {
        ok          { return ok }
        okcancel    { return [string map {yes ok no cancel} $a] }
        yesno       { return [string map {ok yes cancel no} $a] }
        yesnocancel { return [string map {ok yes} $a] }
        default     { return $a }
    }
}

proc tk_getSaveFile {args} { expr {[info exists ::saveTo] ? $::saveTo : ""} }
proc tk_getOpenFile {args} { expr {[info exists ::openFrom] ? $::openFrom : ""} }
proc fossil::browse {url} { lappend ::browsed $url }

proc start {tab {path ""} {size 1200x900}} {
    if {$path eq ""} { set path $::T(repo) }
    tktaalik::main $tab [list $path]
    wm geometry . $size+0+0
    update
}

proc waitUntil {cond {ms 30000}} {
    set end [expr {[clock milliseconds] + $ms}]
    while {![uplevel 1 [list expr $cond]]} {
        if {[clock milliseconds] > $end} {
            puts "FAIL timed out after $ms ms waiting for: $cond"
            incr ::T(failed)
            done
        }
        after 20 {set ::tick 1}
        vwait ::tick
    }
    update
}

proc whenOpen {w script {ms 30000}} {
    after 20 [list ::WhenOpen $w $script [expr {[clock milliseconds] + $ms}]]
}

proc WhenOpen {w script end} {
    if {[winfo exists $w] && [winfo ismapped $w]} {
        uplevel #0 $script
    } elseif {[clock milliseconds] > $end} {
        puts "FAIL timed out waiting for the window $w"
        incr ::T(failed)
    } else {
        after 20 [list ::WhenOpen $w $script $end]
    }
}

proc labels {m} {
    set r {}
    if {[$m index end] eq "none"} { return $r }
    for {set i 0} {$i <= [$m index end]} {incr i} {
        if {[$m type $i] in {command cascade checkbutton radiobutton}} { lappend r [$m entrycget $i -label] }
    }
    return $r
}

proc sql {q {repo ""}} {
    if {$repo eq ""} { set repo [expr {[info exists ::R] ? $::R : $::T(repo)}] }
    fossil::sql $repo $q
}

proc fossilIn {dir args} {
    lassign [fossil::run -dir $dir {*}$args] code out
    string trim $out
}
