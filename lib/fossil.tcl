# Running Fossil from the tabs of tktaalik.
#
#   fossil::run ARG...          run fossil, return {exit-code output}
#   fossil::sql REPO STATEMENT  a read-only query, return a list of rows
#   fossil::checkoutSql DIR STATEMENT  the same in the checkout DIR (its
#                               tables too: vvar, vfile, stash, ...)
#   fossil::hasSearch REPO      whether "fossil sql" has Fossil's search
#                               functions (search_init, title, body...)
#   fossil::card TEXT           TEXT as an argument of an artifact's card
#                               (fossilized: \s for a space...)
#   fossil::buildArtifact REPO TEXT PATH
#                               the artifact TEXT (its cards but the Z
#                               card) written to PATH with its Z card:
#                               its hash (REPO's hash policy)
#   fossil::importArtifact REPO PATH HASH
#                               the artifact in PATH stored in REPO,
#                               public (for what no command makes)
#   fossil::hashFile REPO PATH  the hash of the file PATH, as REPO names
#                               artifacts (its hash policy)
#   fossil::attachRecord REPO NAME TARGET SRC COMMENT USER
#                               the attachment NAME of TARGET (a ticket's
#                               UUID, a page name, a technote ID) recorded
#                               in REPO as Fossil's web pages do: the
#                               artifact SRC (brought in before), or none
#                               ("": the attachment deleted)
#   fossil::tempDir             a new private temporary directory
#   fossil::sqlMode             the ".mode" line for its queries (ascii,
#                               control characters not escaped)
#   fossil::sqlstr TEXT         TEXT as an SQL string literal
#   fossil::outcol EXPR         a text column safe for fossil::sql
#   fossil::arg TEXT            TEXT checked to be safe as an exec argument

namespace eval fossil {
    variable rendered {}        ;# format, text -> HTML (fossil::render)
}

# Run fossil (in the current directory, or -dir DIR) with stdin empty (or
# -input TEXT), so that it cannot wait for an answer.  Return {exit-code
# output}.  The arguments must not look like exec redirections: see
# fossil::arg.
# The Fossil executable: $FOSSIL if set (a path, or a name on PATH), else
# "fossil" from PATH.
proc fossil::exe {} {
    expr {[info exists ::env(FOSSIL)] && $::env(FOSSIL) ne "" ? $::env(FOSSIL) : "fossil"}
}

# "--nosync" for the fossil command COMMAND if this Fossil takes it, else
# nothing: merge and branch take it only since Fossil 2.26 (older ones
# refuse it; they sync only with autosync on, which Tktaalik refuses
# anyway).  Found once from the command's help.
proc fossil::nosync {command} {
    expr {[helpMatches $command *--nosync*] ? "--nosync" : ""}
}

# Whether the help of the fossil command COMMAND matches the glob PATTERN
# (what this Fossil can do, where an option is new): found once.
proc fossil::helpMatches {command pattern} {
    variable helps
    set key [list [exe] $command]
    if {![info exists helps($key)]} {
        if {[catch {exec [exe] help $command 2>@1} out]} { set out "" }
        set helps($key) $out
    }
    string match $pattern $helps($key)
}

# Whether this Fossil has the command NAME (merge-info is new in 2.26).
proc fossil::hasCommand {name} {
    variable commands
    set key [list [exe] $name]
    if {![info exists commands($key)]} {
        set commands($key) [expr {![catch {exec [exe] help $name 2>@1} out]
            && ![string match "*unknown command*" $out]}]
    }
    return $commands($key)
}

# COMMAND (a list) to run: "fossil" first replaced by the executable, and
# for a Fossil that does not take options as --NAME=VALUE (2.21 and
# older) such words split in two.  (Tktaalik writes them so: fossil.exe on
# Windows would expand a pattern of its own word into the files.)
proc fossil::command {command} {
    if {[lindex $command 0] ne "fossil"} { return $command }
    lset command 0 [exe]
    # (Windows: fossil.exe expands * and ? in its arguments against the
    # files, also in other directories (..\*, C:/*), unless the argument
    # was quoted, which exec does only for one with white space: such
    # arguments go through a file, fossil's --args.)
    if {$::tcl_platform(platform) eq "windows"} { set command [ArgsFile $command] }
    if {![eqOptions]} {
        # (Not a value that exec or Fossil would take for a redirection or
        # an option as a word of its own: then Fossil refuses the word.)
        set command [concat {*}[lmap word $command {
            expr {[regexp {^(--[A-Za-z][-A-Za-z0-9]*)=(.*)$} $word -> name value]
                && ![catch {arg $value}] ? [list $name $value] : [list $word]}
        }]]
    }
    return $command
}

# COMMAND (with the executable) with its arguments from the first to the
# last that has * or ? and no white space put into a file read by
# "--args" (a line each), if they can be: a line is an argument, unless it
# is empty or (starting with "-") has a space.  The file is deleted after
# a minute: Fossil reads it when it starts.
proc fossil::ArgsFile {command} {
    # (Only one --args: a command with its own keeps its words.)
    if {"--args" in $command} { return $command }
    set wild [lsearch -all -regexp $command {^[^\s]*[*?][^\s]*$}]
    set wild [lsearch -all -inline -not $wild 0]
    if {![llength $wild]} { return $command }
    set from [lindex $wild 0]
    set to [lindex $wild end]
    set words [lrange $command $from $to]
    foreach word $words {
        if {$word eq "" || [string first \n $word] >= 0 || [regexp {^-.* } $word]
                || [regexp {^(?:[<>|]|2>|&$)} $word]} { return $command }
    }
    set dir [tempDir]
    set path [file join $dir args]
    set f [open $path w]
    fconfigure $f -encoding utf-8 -translation lf
    puts $f [join $words \n]
    close $f
    after 60000 [list file delete -force $dir]
    lreplace $command $from $to --args $path
}

# A pipe to fossil ARGV (redirections allowed), opened with ACCESS.
proc fossil::pipe {argv {access r}} {
    open |[command [list fossil {*}$argv]] $access
}

# Whether this Fossil takes --NAME=VALUE (2.22 and newer): found once,
# from what it says to one.
proc fossil::eqOptions {} {
    variable eqOptions
    set exe [exe]
    if {![info exists eqOptions($exe)]} {
        catch {exec $exe info --repository=/nonexistent/tktaalik.fossil 2>@1} out
        set eqOptions($exe) [expr {![string match "*unrecognized*" $out]}]
    }
    return $eqOptions($exe)
}

proc fossil::run {args} {
    set opts [Options args {-dir -input}]
    set input [expr {[dict exists $opts -input] ? [dict get $opts -input] : ""}]
    if {![dict exists $opts -dir] || [dict get $opts -dir] eq ""} { return [Exec $input $args] }
    set here [pwd]
    cd [dict get $opts -dir]
    try {
        Exec $input $args
    } finally {
        cd $here
    }
}

# A name or a value from the repository as an argument of fossil::run:
# exec would take a word starting with "<", ">", "|" or "2>" for a
# redirection, and fossil one starting with "-" for an option.
proc fossil::arg {text} {
    if {$text eq "" || [regexp {^(?:[-<>|]|2>|&$)} $text]} {
        throw {FOSSIL ARG} "cannot pass \"$text\" to fossil"
    }
    return $text
}

# ------------------------------------------------------------- the layer
#
# New code runs Fossil through these, not with exec or cd of its own:
#
#   fossil::exe                the Fossil executable ($FOSSIL, else fossil)
#   fossil::command LIST        LIST with its "fossil" replaced by it (and
#                               --NAME=VALUE split for Fossil 2.21)
#   fossil::hasCommand NAME     whether this Fossil has the command NAME
#   fossil::helpMatches COMMAND PATTERN
#                               whether the help of COMMAND matches the
#                               glob PATTERN (an option this Fossil has)
#   fossil::nosync COMMAND      {--nosync} if COMMAND (merge, branch...)
#                               takes it in this Fossil, else {}
#   fossil::run ?-dir DIR? ?-input TEXT? ARG...
#                               in DIR if given (the cwd restored even on
#                               errors), stdin TEXT (default empty):
#                               {exit-code output}
#   fossil::runTo PATH ARG...  its output, as bytes, into the file PATH
#   fossil::pipe ARGV ?ACCESS?  a pipe to fossil ARGV (with redirections)
#   fossil::runIn ROOT REPO ARG...
#                               in the checkout ROOT, else with -R REPO
#   fossil::inDir DIR BODY      BODY evaluated in the caller with DIR as the
#                               cwd (restored; "": the cwd as it is)
#   fossil::start ?-dir DIR? ?-encoding ENC? ?-onOutput CMD? ?-onDone CMD?
#           ?-command LIST? ARG...
#                               fossil ARG... (or the program LIST, whole)
#                               in the background: a handle (a channel:
#                               pid works).
#                               CMD of -onOutput gets each chunk read;
#                               CMD of -onDone gets {code text stopped msg}
#                               (code 0 or 1; stopped 1 if fossil::stop)
#   fossil::stop HANDLE         its processes killed
#   fossil::stopAll             all of them (on quit)
#   fossil::running ?HANDLE?    the handles running, or whether HANDLE is
#   fossil::kill PIDS           processes killed (also for other pipes)
#   fossil::runWindow ?-w PATH? ?-dir DIR? ?-shown TEXT? ?-stop 0|1?
#           ?-onDone CMD? ?-command LIST? TITLE ARG...
#                               fossil ARG... in the background with its
#                               output in a window (Stop, Close); the
#                               command line shown (TEXT, else masked);
#                               CMD gets {code text} (code 1 if stopped):
#                               the window
#   fossil::windowJob W         the handle of the window's command ("" done)
#   fossil::mask TEXT           passwords hidden (-B, --httpauth, URLs)
#   fossil::opt NAME VALUE      --NAME=VALUE: one word, whatever VALUE is
#   fossil::valueProblem LABEL VALUE ?KIND?
#                               what is wrong with a typed value ("" if
#                               nothing): KIND any, tag, color, date, name,
#                               version (as fossil::arg)
#   fossil::argOk NAME TITLE    fossil::arg with a message instead: 1 or 0
#   fossil::autosyncSetting ?-dir DIR? ?-R REPO?
#                               the autosync setting as set ("" if not)
#   fossil::autosync ?-dir DIR? ?-R REPO? ?SUBSYSTEM?
#                               its value for SUBSYSTEM (on, off, pullonly...)
#   fossil::autosyncValue SETTING ?SUBSYSTEM?
#                               the value of the autosync setting (as
#                               "on,commit=off") for SUBSYSTEM (update,
#                               commit...)
#   fossil::urlquery TEXT ?KEEP?
#                               TEXT %-encoded (KEEP: characters kept, as /)
#   fossil::urlDecode TEXT      back (UTF-8)

namespace eval fossil {
    variable jobs {}            ;# handle -> dict {onOutput onDone text stopped}
    variable windowJobs         ;# array: window -> handle
}

proc fossil::Options {argsVar names} {
    upvar 1 $argsVar argv
    set opts {}
    while {[llength $argv] && [lindex $argv 0] in $names} {
        set argv [lassign $argv opt value]
        dict set opts $opt $value
    }
    return $opts
}

proc fossil::Exec {input argv} {
    set cmd [command [list fossil {*}$argv]]
    set code [catch {
        exec {*}$cmd << $input 2>@1
    } out opts]
    if {$code && [lindex [dict get $opts -errorcode] 0] ne "CHILDSTATUS"} {
        # Not an exit status: fossil could not be run at all.
        return [list 1 $out]
    }
    list $code [regsub {\n?child process exited abnormally$} $out ""]
}

# Run fossil with its output, as bytes, into the file PATH (for commands
# without an output option of their own in older Fossils): {exit-code
# error-output}.
proc fossil::runTo {path args} {
    set cmd [command [list fossil {*}$args]]
    if {![catch {exec {*}$cmd > $path << ""} msg opts]} { return [list 0 ""] }
    # (Only an exit status other than 0 is a failure; else output on stderr.)
    switch -- [lindex [dict get $opts -errorcode] 0] {
        NONE { return [list 0 $msg] }
        CHILDSTATUS { return [list 1 [regsub {\n?child process exited abnormally$} $msg ""]] }
        default { return [list 1 $msg] }
    }
}

proc fossil::runIn {root repo args} {
    if {$root eq ""} { return [run {*}$args -R $repo] }
    run -dir $root {*}$args
}

proc fossil::inDir {dir body} {
    if {$dir eq ""} { return [uplevel 1 $body] }
    set here [pwd]
    cd $dir
    try {
        uplevel 1 $body
    } finally {
        cd $here
    }
}

# ----------------------------------------------------------- background

proc fossil::start {args} {
    variable jobs
    set opts [Options args {-dir -encoding -onOutput -onDone -command}]
    set command [expr {[dict exists $opts -command] ? [dict get $opts -command] : [list fossil {*}$args]}]
    set dir [expr {[dict exists $opts -dir] ? [dict get $opts -dir] : ""}]
    set here [pwd]
    if {$dir ne ""} { cd $dir }
    try {
        set cmd [command $command]
        set chan [open |[list {*}$cmd << "" 2>@1] r]
    } finally {
        cd $here
    }
    fconfigure $chan -blocking 0 -translation auto
    if {[dict exists $opts -encoding]} { fconfigure $chan -encoding [dict get $opts -encoding] }
    dict set jobs $chan [dict create \
        onOutput [expr {[dict exists $opts -onOutput] ? [dict get $opts -onOutput] : ""}] \
        onDone [expr {[dict exists $opts -onDone] ? [dict get $opts -onDone] : ""}] \
        text "" stopped 0]
    fileevent $chan readable [list fossil::JobRead $chan]
    return $chan
}

proc fossil::JobRead {chan} {
    variable jobs
    if {![dict exists $jobs $chan]} return
    set chunk [read $chan]
    dict with jobs $chan { append text $chunk }
    set onOutput [dict get $jobs $chan onOutput]
    if {$chunk ne "" && $onOutput ne ""} { uplevel #0 [list {*}$onOutput $chunk] }
    if {![eof $chan]} return
    fconfigure $chan -blocking 1
    set code [catch {close $chan} msg]
    set job [dict get $jobs $chan]
    dict unset jobs $chan
    if {!$code} { set msg "" }
    set onDone [dict get $job onDone]
    if {$onDone ne ""} {
        uplevel #0 [list {*}$onDone $code [dict get $job text] [dict get $job stopped] $msg]
    }
}

proc fossil::stop {handle} {
    variable jobs
    if {![dict exists $jobs $handle]} return
    dict set jobs $handle stopped 1
    kill [pid $handle]
}

proc fossil::stopAll {} {
    variable jobs
    foreach handle [dict keys $jobs] { stop $handle }
}

proc fossil::running {{handle ""}} {
    variable jobs
    if {$handle eq ""} { return [dict keys $jobs] }
    dict exists $jobs $handle
}

# Kill the processes and what they started (a command run through sh, the
# ssh of a clone...): else a child would keep the pipe open.
proc fossil::kill {pids} {
    foreach p $pids {
        if {$::tcl_platform(platform) eq "windows"} {
            catch {exec taskkill /F /T /PID $p}
        } else {
            # The children first (they would be left to init).
            if {![catch {exec pgrep -P $p} children]} { kill [split [string trim $children] \n] }
            catch {exec kill $p}
        }
    }
}

# A command that may take long (the network), its output shown as it
# comes; the window (the path -w, or .fossilRun).
proc fossil::runWindow {args} {
    variable windowJobs
    set opts [Options args {-w -dir -shown -stop -onDone -command}]
    set title [lindex $args 0]
    set argv [lrange $args 1 end]
    if {[dict exists $opts -command]} { set argv [lrange [dict get $opts -command] 1 end] }
    set w [expr {[dict exists $opts -w] ? [dict get $opts -w] : ".fossilRun"}]
    destroy $w
    toplevel $w
    wm title $w $title
    wm transient $w .
    text $w.t -height 14 -width 80 -wrap word -font TkFixedFont -yscrollcommand [list $w.y set]
    ttk::scrollbar $w.y -command [list $w.t yview]
    ttk::frame $w.b -padding 6
    ttk::label $w.b.status -text "Running\u2026" -anchor w
    ttk::button $w.b.close -text Close -command [list destroy $w] -state disabled
    ttk::button $w.b.stop -text Stop -command [list fossil::stopWindow $w]
    if {[dict exists $opts -stop] && ![dict get $opts -stop]} { $w.b.stop state disabled }
    pack $w.b.close $w.b.stop -side right -padx {4 0}
    pack $w.b.status -side left -fill x -expand 1
    pack $w.b -side bottom -fill x
    pack $w.y -side right -fill y
    pack $w.t -fill both -expand 1
    set shown [expr {[dict exists $opts -shown] && [dict get $opts -shown] ne ""
        ? [dict get $opts -shown] : [mask "fossil [join $argv]"]}]
    $w.t insert end "$shown\n\n"
    set done [expr {[dict exists $opts -onDone] ? [dict get $opts -onDone] : ""}]
    set start [list -onOutput [list fossil::WindowOutput $w] -onDone [list fossil::WindowDone $w $done]]
    if {[dict exists $opts -dir] && [dict get $opts -dir] ne ""} { lappend start -dir [dict get $opts -dir] }
    if {[dict exists $opts -command]} { lappend start -command [dict get $opts -command] }
    set windowJobs($w) [start {*}$start {*}$argv]
    return $w
}

proc fossil::windowJob {w} {
    variable windowJobs
    expr {[info exists windowJobs($w)] ? $windowJobs($w) : ""}
}

proc fossil::stopWindow {w} {
    set handle [windowJob $w]
    if {$handle ne ""} { stop $handle }
}

proc fossil::WindowOutput {w chunk} {
    if {![winfo exists $w]} return
    $w.t insert end [string map {\r \n} $chunk]
    $w.t see end
}

proc fossil::WindowDone {w done code text stopped msg} {
    variable windowJobs
    unset -nocomplain windowJobs($w)
    if {[winfo exists $w]} {
        $w.b.status configure -text [expr {$stopped ? "Stopped" : $code ? "Failed" : "Done"}]
        $w.b.close state !disabled
        $w.b.stop state disabled
    }
    if {$stopped} { set code 1 }
    if {$done ne ""} { uplevel #0 [list {*}$done $code $text] }
}

# --------------------------------------------------------------- values

proc fossil::mask {text} {
    regsub -all {(-B\s+|--httpauth[= ]\s*)([^:\s]+):\S+} $text {\1\2:****} text
    regsub -all {([a-z]+://[^:/@\s]*):[^@/\s]*@} $text {\1:****@} text
    return $text
}

proc fossil::opt {name value} {
    return --$name=$value
}

proc fossil::valueProblem {label value {kind any}} {
    if {[string index $value 0] eq "-"} { return "$label cannot start with \"-\": $value" }
    switch -- $kind {
        tag {
            if {![regexp {^[^\s<>|"'&]+$} $value]} { return "Not a tag name: $value" }
        }
        color {
            if {![regexp {^(#[0-9A-Fa-f]{3}|#[0-9A-Fa-f]{6}|[A-Za-z]+)$} $value]} {
                return "$label: a colour is #RRGGBB or a name: $value"
            }
        }
        date {
            if {![regexp {^\d{4}-\d\d-\d\d([ T]\d\d:\d\d(:\d\d(\.\d+)?)?)?$} $value]} {
                return "$label: YYYY-MM-DD HH:MM:SS (UTC): $value"
            }
        }
        name {
            if {[regexp {[\s<>|]} $value]} { return "$label: no spaces or \"<>|\": $value" }
        }
        version {
            # (As fossil::arg: no "<", ">", "|", "2>" or a lone "&".)
            if {[catch {fossil::arg $value}]} { return "Not a version: $value" }
        }
    }
    return ""
}

proc fossil::argOk {name title} {
    if {![catch {arg $name}]} { return 1 }
    tk_messageBox -icon info -title $title -message "This name cannot be passed to fossil:" \
        -detail "\"$name\" (it starts with \"-\", \"<\", \">\" or \"|\", or is empty)."
    return 0
}

proc fossil::autosyncSetting {args} {
    set opts [Options args {-dir -R}]
    set cmd [list settings autosync --exact]
    if {[dict exists $opts -R]} { lappend cmd -R [dict get $opts -R] }
    set dir [expr {[dict exists $opts -dir] ? [dict get $opts -dir] : ""}]
    lassign [run -dir $dir {*}$cmd] code out
    foreach line [split $out \n] {
        if {[regexp {^autosync\s+(?:\([^)]*\)\s+)?(.*)$} $line -> value]} { return [string trim $value] }
    }
    return ""
}

proc fossil::autosync {args} {
    set opts [Options args {-dir -R}]
    autosyncValue [autosyncSetting {*}$opts] [lindex $args 0]
}

proc fossil::autosyncValue {setting {subsystem ""}} {
    set default on
    set value ""
    foreach entry [split $setting ", \t"] {
        if {$entry eq ""} continue
        if {[regexp {^([^=]+)=(.*)$} $entry -> cmd v]} {
            if {$cmd eq $subsystem} { set value $v }
        } else {
            set default $entry
        }
    }
    expr {$value ne "" ? $value : $default}
}

proc fossil::urlquery {text {keep ""}} {
    set out ""
    foreach byte [split [encoding convertto utf-8 $text] ""] {
        if {[string match {[A-Za-z0-9._~-]} $byte] || ($byte ne "" && [string first $byte $keep] >= 0)} {
            append out $byte
        } else {
            append out [format %%%02X [scan $byte %c]]
        }
    }
    return $out
}

proc fossil::urlDecode {text} {
    set text [string map {+ " "} $text]
    set bytes ""
    while {[regexp -indices {%([0-9A-Fa-f]{2})} $text m hex]} {
        append bytes [encoding convertto utf-8 [string range $text 0 [expr {[lindex $m 0] - 1}]]]
        append bytes [binary format H2 [string range $text {*}$hex]]
        set text [string range $text [expr {[lindex $m 1] + 1}] end]
    }
    append bytes [encoding convertto utf-8 $text]
    encoding convertfrom utf-8 $bytes
}

# Run the query on the repository, read-only.  Errors are thrown as
# {FOSSIL DB}.  Text columns must not contain the separators of
# ".mode ascii": use fossil::outcol for those that can.
proc fossil::sql {repo statement} {
    set script "[sqlMode]\n[string map {\n { } \r { }} $statement];\n"
    try {
        set out [exec [exe] sql -R $repo --readonly << $script]
    } on error msg {
        throw {FOSSIL DB} [string trim [lindex [split $msg \n] 0]]
    }
    if {$out eq ""} { return {} }
    lmap row [split [string trimright $out \x1e] \x1e] { split $row \x1f }
}

proc fossil::checkoutSql {dir statement} {
    set script "[sqlMode]\n[string map {\n { } \r { }} $statement];\n"
    set here [pwd]
    cd $dir
    try {
        set out [exec [exe] sql --readonly << $script]
    } on error msg {
        throw {FOSSIL DB} [string trim [lindex [split $msg \n] 0]]
    } finally {
        cd $here
    }
    if {$out eq ""} { return {} }
    lmap row [split [string trimright $out \x1e] \x1e] { split $row \x1f }
}

# The same in the background: fossil::sqlStart starts the query and
# returns at once; fossil::sqlFinish waits for it and returns the rows.  For
# running a slow query beside others.
proc fossil::sqlStart {repo statement} {
    set script "[sqlMode]\n[string map {\n { } \r { }} $statement];\n"
    set chan [open |[list [exe] sql -R $repo --readonly 2>@1] r+]
    fconfigure $chan -encoding utf-8 -translation lf
    puts -nonewline $chan $script
    chan close $chan write
    return $chan
}

# Fossil 2.28 and newer lost them with -R (a Fossil bug: they go to a
# connection its shell opens first, to look at the file).  Tried once.
proc fossil::hasSearch {repo} {
    variable hasSearch
    if {![info exists hasSearch]} {
        lassign [run -input "SELECT search_init('', '', '', '', 0);\n" sql -R $repo --readonly] code out
        set hasSearch [expr {![string match "*no such function*" $out]}]
    }
    return $hasSearch
}

proc fossil::card {text} {
    string map [list \\ \\\\ " " \\s \n \\n \r \\r \t \\t \v \\v \f \\f] $text
}

proc fossil::buildArtifact {repo text path} {
    set dir [tempDir]
    try {
        WriteBytes $dir/pre $text
        lassign [run md5sum $dir/pre] code out
        if {$code || ![regexp {^([0-9a-f]{32})\M} $out -> md5]} {
            throw {FOSSIL ARTIFACT} "fossil md5sum: [string trim $out]"
        }
    } finally {
        file delete -force $dir
    }
    WriteBytes $path "${text}Z $md5\n"
    hashFile $repo $path
}

proc fossil::attachRecord {repo name target src comment user} {
    # The cards of attach.c: A (no source when deleted), C, D, U, Z.
    set cards "A [card $name] [card $target][expr {$src eq "" ? "" : " $src"}]\n"
    if {[string trim $comment] ne ""} { append cards "C [card [string trim $comment]]\n" }
    # (In milliseconds, as Fossil's: a change made at once after another
    # is still the newer one.)
    set ms [clock milliseconds]
    set date [clock format [expr {$ms / 1000}] -format %Y-%m-%dT%H:%M:%S -gmt 1]
    append cards "D $date[format .%03d [expr {$ms % 1000}]]\n"
    append cards "U [card $user]\n"
    set dir [tempDir]
    try {
        set hash [buildArtifact $repo $cards $dir/artifact]
        importArtifact $repo $dir/artifact $hash
    } finally {
        file delete -force $dir
    }
    return $hash
}

proc fossil::hashFile {repo path} {
    # The hash of the repository's policy (SHA1 only where it says so).
    set policy [lindex [sql $repo "SELECT value FROM config WHERE name='hash-policy'"] 0 0]
    set sum [expr {$policy eq "sha1" ? "sha1sum" : "sha3sum"}]
    lassign [run $sum $path] code out
    if {$code || ![regexp {^([0-9a-f]{40,64})\M} $out -> hash]} {
        throw {FOSSIL ARTIFACT} "fossil $sum: [string trim $out]"
    }
    return $hash
}

# Brought in as a bundle of its own ("fossil bundle import --publish"
# checks its hash, stores it and reads it as if a sync had brought it).
# Throws {FOSSIL ARTIFACT} if it was not taken.
proc fossil::importArtifact {repo path hash} {
    set dir [tempDir]
    try {
        set code [lindex [sql $repo "SELECT value FROM config WHERE name='project-code'"] 0 0]
        # The bundle, as "fossil bundle export" makes them (bundle.c).
        set bundle $dir/post.bundle
        lassign [run -input "ATTACH [sqlstr $bundle] AS b;
            CREATE TABLE b.bconfig(bcname TEXT, bcvalue ANY);
            CREATE TABLE b.bblob(blobid INTEGER PRIMARY KEY, uuid TEXT NOT NULL, sz INT NOT NULL,
                delta ANY, notes TEXT, data BLOB);
            INSERT INTO b.bconfig VALUES('project-code', [sqlstr $code]);
            INSERT INTO b.bblob(uuid, sz, delta, notes, data) VALUES([sqlstr $hash],
                length(readfile([sqlstr $path])), NULL, 'tktaalik', compress(readfile([sqlstr $path])));
            " sql --no-repository] code out
        if {$code || [string match "*rror*" $out]} {
            throw {FOSSIL ARTIFACT} "the bundle: [string trim $out]"
        }
        lassign [run bundle import $bundle --publish -R $repo] code out
        if {$code} { throw {FOSSIL ARTIFACT} "fossil bundle import: [string trim $out]" }
    } finally {
        file delete -force $dir
    }
}

proc fossil::tempDir {} {
    foreach var {TMPDIR TEMP TMP} {
        if {[info exists ::env($var)] && [file isdirectory $::env($var)]} {
            set base $::env($var)
            break
        }
    }
    if {![info exists base]} { set base /tmp }
    set dir [file join $base tktaalik-[pid]-[clock clicks]]
    file mkdir $dir
    if {$::tcl_platform(platform) eq "unix"} { file attributes $dir -permissions 0700 }
    return $dir
}

proc fossil::WriteBytes {path text} {
    set f [open $path wb]
    puts -nonewline $f [encoding convertto utf-8 $text]
    close $f
}

# The output mode of "fossil sql" for the queries: ascii (rows and columns
# separated by control characters 30 and 31).  The SQLite shell of newer
# Fossils (2.29) writes other control characters escaped ("^B") unless
# told not to ("--escape off"); older ones (2.21) refuse that option, so
# it is asked for only where this Fossil takes it (found once).
proc fossil::sqlMode {} {
    variable sqlModes
    set exe [exe]
    if {![info exists sqlModes($exe)]} {
        set mode ".mode ascii"
        if {![catch {exec $exe sql --no-repository << ".mode ascii --escape off\nSELECT 'ok';\n" 2>@1} out]
                && [string trim $out \x1e\x1f\n] eq "ok"} {
            append mode " --escape off"
        }
        set sqlModes($exe) $mode
    }
    return $sqlModes($exe)
}

proc fossil::sqlFinish {chan} {
    set out [read $chan]
    try {
        close $chan
    } on error msg {
        throw {FOSSIL DB} [string trim [lindex [split "$out\n$msg" \n] 0]]
    }
    if {$out eq ""} { return {} }
    lmap row [split [string trimright $out \x1e] \x1e] { split $row \x1f }
}

# Text of the repository (a comment...) for showing: CR LF or CR line
# ends as LF; its first line, without them.
proc fossil::lf {text} {
    string map [list \r\n \n \r \n] $text
}

proc fossil::oneLine {text} {
    lindex [split [string trim [lf $text]] \n] 0
}

proc fossil::sqlstr {text} {
    return '[string map {' ''} $text]'
}

proc fossil::outcol {expr} {
    return "replace(replace($expr,char(30),''),char(31),'')"
}

# Text as HTML, rendered by Fossil (its test-*-render commands): wiki and
# Markdown; HTML as it is; "" for plain text, or if Fossil cannot.
proc fossil::render {repo mimetype text} {
    variable rendered
    switch -- $mimetype {
        text/x-fossil-wiki {
            # Not "[target]" as a link to a page that does not exist:
            # in tickets that is mostly Tcl, like [string repeat 0 10].
            set command {test-wiki-render --nobadlinks}
        }
        text/x-markdown    { set command test-markdown-render }
        text/html          { return $text }
        default            { return "" }
    }
    set key $repo\n$mimetype\n$text
    if {[dict exists $rendered $key]} { return [dict get $rendered $key] }
    set html ""
    set name ""
    try {
        # Through files, in UTF-8 both ways (not the system encoding).
        set f [file tempfile name]
        fconfigure $f -encoding utf-8
        puts -nonewline $f $text
        close $f
        set p [open |[list [exe] {*}$command -R $repo $name 2>@1] r]
        fconfigure $p -encoding utf-8
        set html [read $p]
        close $p
    } on error {} {
        set html ""
    } finally {
        if {$name ne ""} { file delete $name }
    }
    dict set rendered $key $html
    return $html
}

# The links of [hash] in the texts: hash -> tkt:TICKET for a ticket,
# info:ARTIFACT for another artifact (a check-in); what is not in the
# repository is left out.
proc fossil::hashLinks {repo texts} {
    set found {}
    foreach text $texts {
        foreach {- hash} [regexp -all -inline {\[([0-9a-fA-F]{4,40})\]} $text] {
            set hash [string tolower $hash]
            if {$hash ni $found} { lappend found $hash }
        }
    }
    if {![llength $found]} { return {} }
    set values [join [lmap h $found { string cat ( [sqlstr $h] ) }] ,]
    try {
        set rows [sql $repo "WITH c(h) AS (VALUES $values) SELECT h,\
            coalesce((SELECT tkt_uuid FROM ticket WHERE tkt_uuid >= h\
                AND tkt_uuid < h||'g' LIMIT 1),''),\
            coalesce((SELECT uuid FROM blob WHERE uuid >= h AND uuid < h||'g' LIMIT 1),'')\
            FROM c"]
    } trap {FOSSIL DB} {} {
        return {}
    }
    set links {}
    foreach row $rows {
        lassign $row hash ticket artifact
        if {$ticket ne ""} {
            dict set links $hash tkt:$ticket
        } elseif {$artifact ne ""} {
            dict set links $hash info:$artifact
        }
    }
    return $links
}

# The server of the repository (its remote URL without the user name), for
# opening pages in the browser; "" if there is none.
proc fossil::remoteUrl {repo} {
    if {[catch {exec [exe] remote -R $repo} url] || ![regexp {^https?://} $url]} {
        return ""
    }
    regsub {^(https?://)[^/@]*@} $url {\1} url
    string trimright $url /
}

# The user in the server URL of REPO ("" if none).
proc fossil::remoteUser {repo} {
    if {[catch {exec [exe] remote -R $repo} url] || ![regexp {^https?://([^/@:]+)(?::[^/@]*)?@} $url -> user]} {
        return ""
    }
    return $user
}

# The password Fossil saved for the server URL of REPO (last-sync-pw, as
# Fossil's own sync and chat use it), "" if none.  Fossil keeps it
# obscured, not encrypted: hex, a salt byte, then each byte XOR-ed with
# the salt and a fixed key (obscure() in Fossil's encode.c).
proc fossil::savedPassword {repo} {
    set value [lindex [sql $repo "SELECT [outcol value] FROM config WHERE name='last-sync-pw'"] 0 0]
    unobscure $value
}

proc fossil::unobscure {text} {
    # (Not obscured: as it is, as Fossil does.)
    if {[string length $text] < 2 || [string length $text] % 2 || ![string is xdigit $text]} {
        return $text
    }
    set key {0xa7 0x21 0x31 0xe3 0x2a 0x50 0x2c 0x86 0x4c 0xa4 0x52 0x25 0xff 0x49 0x35 0x85}
    binary scan [binary format H* $text] cu* bytes
    set bytes [lassign $bytes salt]
    set out {}
    set i 0
    foreach b $bytes {
        lappend out [expr {$b ^ [lindex $key [expr {$i & 15}]] ^ $salt}]
        incr i
    }
    encoding convertfrom utf-8 [binary format c* $out]
}

proc fossil::browse {url} {
    switch -- [tk windowingsystem] {
        win32   { exec {*}[auto_execok start] "" $url & }
        aqua    { exec open $url & }
        default { exec xdg-open $url & }
    }
}
