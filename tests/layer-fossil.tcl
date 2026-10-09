# The fossil:: layer (lib/fossil.tcl): run in a directory, with input;
# runIn; background jobs with their output, stopped, all stopped; the run
# window; values checked, options, masking, autosync, URL encoding.  On a
# repository made here.
source [file join [file dirname [info script]] common.tcl]
set D $T(tmp)
set ::boxes {}

# run, runIn, inDir.
lassign [fossil::run init $D/r.fossil] code out
check "run: init ($code)" {$code == 0 && [file exists $D/r.fossil]}
file mkdir $D/co
lassign [fossil::run -dir $D/co open $D/r.fossil] code out
# (The checkout's database: _FOSSIL_ on Windows.)
check "run -dir: opened there ($code)" {$code == 0 && ([file exists $D/co/.fslckout] || [file exists $D/co/_FOSSIL_])}
set here [pwd]
lassign [fossil::run -dir $D/co info] code out
check "run -dir: the cwd restored" {[pwd] eq $here && [string match "*checkout:*" $out]}
catch {fossil::run -dir $D/nowhere info}
check "run -dir: restored after an error" {[pwd] eq $here}
lassign [fossil::run -input "SELECT 6*7;\n" sql -R $D/r.fossil] code out
check "run -input: [string trim $out]" {$code == 0 && [string trim $out] eq "42"}
lassign [fossil::run nosuchcommand] code out
check "run: the exit code of a failure ($code)" {$code == 1 && ![string match "*child process exited*" $out]}
lassign [fossil::runIn $D/co $D/r.fossil info] code out
check "runIn a checkout" {$code == 0 && [string match "*checkout:*" $out]}
lassign [fossil::runIn "" $D/r.fossil info] code out
check "runIn without one: -R" {$code == 0 && ![string match "*checkout:*" $out] && [string match "*project-name:*" $out]}
set got [fossil::inDir $D/co { file tail [pwd] }]
check "inDir: $got" {$got eq "co" && [pwd] eq $here}

# start: output, onDone, stop, stopAll.
set ::chunks ""
set h [fossil::start -dir $D/co -onOutput {::apply {{c} { append ::chunks $c }}} \
    -onDone {::apply {{code text stopped msg} { set ::job [list $code $stopped $text] }}} info]
check "start: running" {[fossil::running $h] && $h in [fossil::running]}
waitUntil {[info exists ::job]} 10000
check "start: done ([lrange $::job 0 1])" {[lrange $::job 0 1] eq {0 0} && [string match "*checkout:*" [lindex $::job 2]] && $::chunks eq [lindex $::job 2] && ![fossil::running $h]}
unset ::job
set h [fossil::start -command [list sleep 30] -onDone {::apply {{code text stopped msg} { set ::job [list $code $stopped] }}}]
set p [pid $h]
after 200 {set ::tick 1}; vwait ::tick
fossil::stop $h
waitUntil {[info exists ::job]} 10000
check "stop: stopped ($::job)" {[lindex $::job 1] == 1 && ![file exists /proc/[lindex $p 0]]}
unset ::job
set a [fossil::start -command [list sleep 30]]
set b [fossil::start -command [list sleep 30] -onDone {::apply {args { set ::job 1 }}}]
set pids [concat [pid $a] [pid $b]]
fossil::stopAll
waitUntil {[info exists ::job] && ![llength [fossil::running]]} 10000
check "stopAll: all gone" {![llength [fossil::running]] && ![file exists /proc/[lindex $pids 0]] && ![file exists /proc/[lindex $pids 1]]}

# runWindow.
set w [fossil::runWindow -w .lr -dir $D/co -onDone {::apply {{code text} { set ::win $code }}} Info info]
update
check "runWindow: the command shown" {[string match "fossil info*" [$w.t get 1.0 2.0]] && [fossil::windowJob $w] ne ""}
waitUntil {[info exists ::win]} 10000
check "runWindow: done ([.lr.b.status cget -text])" {$::win == 0 && [.lr.b.status cget -text] eq "Done" && [fossil::windowJob $w] eq "" && [string match "*checkout:*" [.lr.t get 1.0 end]]}
unset ::win
fossil::runWindow -w .lr -command [list sleep 30] -onDone {::apply {{code text} { set ::win $code }}} Long
after 200 {set ::tick 1}; vwait ::tick
.lr.b.stop invoke
waitUntil {[info exists ::win]} 10000
check "runWindow: Stop ([.lr.b.status cget -text])" {$::win == 1 && [.lr.b.status cget -text] eq "Stopped"}
fossil::runWindow -w .lr -stop 0 Version version; update
check "runWindow -stop 0: no Stop" {[.lr.b.stop instate disabled]}
check "runWindow: passwords masked" {[string first secret [.lr.t get 1.0 end]] < 0}
fossil::runWindow -w .lr2 Clone clone https://me:secret@example.invalid/x $D/x.fossil; update
check "runWindow: the URL's password masked: [.lr2.t get 1.0 1.end]" {[string first secret [.lr2.t get 1.0 end]] < 0 && [string first "me:****@" [.lr2.t get 1.0 end]] >= 0}
fossil::stopAll; destroy .lr .lr2

# Values.
check "mask -B" {[fossil::mask "clone -B u:pw x"] eq "clone -B u:**** x"}
check "mask --httpauth=" {[fossil::mask "pull --httpauth=u:pw"] eq "pull --httpauth=u:****"}
check "opt" {[fossil::opt user "<x"] eq "--user=<x"}
check "valueProblem: a leading -" {[string match "Tag cannot start*" [fossil::valueProblem Tag -x]]}
check "valueProblem: tag" {[fossil::valueProblem Tag "a b" tag] ne "" && [fossil::valueProblem Tag ab tag] eq ""}
check "valueProblem: color" {[fossil::valueProblem C #12 color] ne "" && [fossil::valueProblem C #123 color] eq "" && [fossil::valueProblem C red color] eq ""}
check "valueProblem: date" {[fossil::valueProblem D 2026-1-1 date] ne "" && [fossil::valueProblem D "2026-10-07 12:00" date] eq ""}
check "valueProblem: name" {[fossil::valueProblem N "a|b" name] ne "" && [fossil::valueProblem N ab name] eq ""}
check "valueProblem: version" {[fossil::valueProblem V ">x" version] ne "" && [fossil::valueProblem V trunk version] eq ""}
set ::boxes {}
check "argOk: refused with a message" {![fossil::argOk "<x" T] && [lindex $::boxes 0] eq "This name cannot be passed to fossil:"}
check "argOk: passed" {[fossil::argOk trunk T]}
check "autosyncValue" {[fossil::autosyncValue "on,commit=off" commit] eq "off" && [fossil::autosyncValue "on,commit=off" update] eq "on" && [fossil::autosyncValue "" update] eq "on" && [fossil::autosyncValue pullonly] eq "pullonly"}
fossil::run -dir $D/co settings autosync off
check "autosyncSetting -dir: [fossil::autosyncSetting -dir $D/co]" {[fossil::autosyncSetting -dir $D/co] eq "off" && [fossil::autosync -dir $D/co update] eq "off"}
fossil::run settings autosync "pullonly,commit=off" -R $D/r.fossil
check "autosync -R: [fossil::autosync -R $D/r.fossil commit]" {[fossil::autosync -R $D/r.fossil commit] eq "off" && [fossil::autosync -R $D/r.fossil update] eq "pullonly"}
set s "a b/[encoding convertfrom utf-8 \xc3\xa9]"
check "urlquery: [fossil::urlquery $s]" {[fossil::urlquery $s] eq "a%20b%2F%C3%A9" && [fossil::urlquery $s /] eq "a%20b/%C3%A9"}
check "urlDecode" {[fossil::urlDecode "a%20b+%2F%C3%A9"] eq "a b /[encoding convertfrom utf-8 \xc3\xa9]"}
# Control characters in the results as they are (newer Fossils' SQLite
# shell escapes them unless told not to: fossil::sqlMode).
check "sql: control characters kept ([fossil::sqlMode])" {
    [lindex [fossil::sql $T(repo) "SELECT 'a'||char(2)||'b'||char(1)"] 0 0] eq "a\x02b\x01"}

# Windows: words with * or ? (and no white space, which exec quotes) go
# to an --args file, which fossil.exe does not expand against files
# (fossil::ArgsFile; tried here with this Fossil).
set c [fossil::ArgsFile [list [fossil::exe] test-echo a ..\\* *.md {b c} x]]
set echoed [lmap l [split [exec {*}$c] \n] { if {[regexp {^argv\[(\d+)\] = \[(.*)\]$} $l -> i a] && $i >= 2} { set a } else continue }]
check "ArgsFile: [lrange $c 1 end] -> $echoed" {[lindex $c 2] eq "a" && [lindex $c 3] eq "--args"
    && [lindex $c end] eq "x" && $echoed eq [list a ..\\* *.md {b c} x]}
check "ArgsFile: none without wildcards, nor with --args" {[fossil::ArgsFile {fossil diff a}] eq {fossil diff a}
    && [fossil::ArgsFile {fossil ticket --args f *}] eq {fossil ticket --args f *}}
check "ArgsFile: a word that cannot be a line: unchanged" {[fossil::ArgsFile {fossil grep * {-x y} *}] eq {fossil grep * {-x y} *}}

# (The wrapper is a shell script: not on Windows.)
if {$::tcl_platform(platform) ne "windows"} {
    # FOSSIL: the executable to run, for every way of running it.
    set real [auto_execok fossil]
    set log $T(tmp)/calls.log
    set wrapper $T(tmp)/myfossil
    set f [open $wrapper w]
    puts $f "#!/bin/sh\necho \"\$1\" >> $log\nexec [list {*}$real] \"\$@\""
    close $f
    file attributes $wrapper -permissions 0755
    set saved [expr {[info exists ::env(FOSSIL)] ? $::env(FOSSIL) : ""}]
    set ::env(FOSSIL) $wrapper
    check "exe: \$FOSSIL" {[fossil::exe] eq $wrapper && [fossil::command {fossil diff -i}] eq [list $wrapper diff -i]
        && [fossil::command {patch -p0}] eq {patch -p0}}
    fossil::run version
    fossil::sql $T(repo) "SELECT 1"
    set done 0
    fossil::start -onDone {::apply {{args} { set ::done 1 }}} version
    vwait ::done
    set f [open $log]; set calls [split [string trim [read $f]] \n]; close $f
    check "run (after info, to find its options), sql (once more, its mode), start through it: $calls" {$calls eq {info version sql sql version}}
    unset ::env(FOSSIL)
    check "unset: fossil from PATH" {[fossil::exe] eq "fossil"}
    if {$saved ne ""} { set ::env(FOSSIL) $saved }
}
done
