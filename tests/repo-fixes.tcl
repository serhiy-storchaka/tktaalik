# Fixes and additions of the repository operations (re-audit): known
# repositories not pruned, "~" in typed paths, backup not onto the
# repository, the clone's password not shown, one form at a time, close
# checkout when "changes" fails, pull configuration by remote name,
# export asking before replacing, Stop and stopping everything, "fossil
# ui" following the repository, remote URLs checked, init with a
# description and a template, configuration reset, known checkouts and
# their changes, the page of what is shown.  On scratch copies.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set D $T(tmp)
set ::boxes {}
set ::answer ok
set ::browsed {}
tktaalik::main tickets [list $W/co]
update
proc answer {values} {
    after 200 [list ::apply {{values} {
        foreach {k v} $values { set ::repoops::f($k) $v }
        set ::repoops::done ok
    }} $values]
}
proc waitRun {} {
    after 100 {set ::tick 1}; vwait ::tick
    waitUntil {$::repoops::running eq ""}
    update
}
set G $::env(FOSSIL_HOME)/.fossil
# (fossil sql reads its SQL from stdin.)
proc knownInConfig {} {
    exec fossil sql --no-repository << "ATTACH '$::G' AS g;\nSELECT substr(name,6) FROM g.global_config WHERE name GLOB 'repo:*';\n"
}

# 1. Known repositories: one not found now stays known.
file copy $W/tk.fossil $D/gone.fossil
exec fossil all add $D/gone.fossil
file rename $D/gone.fossil $D/gone.moved
.tickets.menu.file.known configure -postcommand {}
repoops::knownMenu .tickets.menu.file.known
set labels {}
for {set i 0} {$i <= [.tickets.menu.file.known index end]} {incr i} { lappend labels [.tickets.menu.file.known entrycget $i -label] }
check "known: the one not found not listed ([llength $labels])" {[lsearch -glob $labels *gone*] < 0}
check "but still known in ~/.fossil (not pruned)" {[string first gone.fossil [knownInConfig]] >= 0}
file rename $D/gone.moved $D/gone.fossil
repoops::knownMenu .tickets.menu.file.known
set labels {}
for {set i 0} {$i <= [.tickets.menu.file.known index end]} {incr i} { lappend labels [.tickets.menu.file.known entrycget $i -label] }
check "back: listed again" {[lsearch -glob $labels *gone.fossil] >= 0}
# Known checkouts, and their changes.
.tickets.menu.file.checkouts configure -postcommand {}
repoops::knownMenu .tickets.menu.file.checkouts 1
set labels {}
for {set i 0} {$i <= [.tickets.menu.file.checkouts index end]} {incr i} {
    if {[.tickets.menu.file.checkouts type $i] eq "command"} { lappend labels [.tickets.menu.file.checkouts entrycget $i -label] }
}
check "known checkouts: the scratch one ([join $labels /])" {[lsearch -exact $labels [file normalize $W/co]] >= 0 && [lsearch -glob $labels "Changes in all*"] >= 0}
set f [open $W/co/README.md a]; puts $f "a change"; close $f
repoops::allChanges; update
set text [.repoopsChanges.t get 1.0 end]
check "changes in all checkouts: README.md" {[string match "*[file normalize $W/co]*README.md*" $text] && [string first gone.fossil [knownInConfig]] >= 0}
destroy .repoopsChanges

# 3. "~" in typed paths.
check "~: [repoops::path ~/x.fossil]" {[repoops::path ~/x.fossil] eq [file join $::env(HOME) x.fossil]}
check "relative: from the folder Tktaalik is in" {[repoops::path x.fossil] eq [file join [pwd] x.fossil]}

# 4. Back up: not onto the repository itself.
proc tk_getSaveFile {args} { return $::W/tk.fossil }
set before [file mtime $W/tk.fossil]
set size [file size $W/tk.fossil]
repoops::backup; update
check "backup onto itself refused: [lindex $::boxes end]" {[lindex $::boxes end] eq "That is the repository itself." && [file size $W/tk.fossil] == $size}

# 5. Clone: the password not shown; a relative source resolved here.
# (A small repository to clone: a clone of tk.fossil takes a minute.)
exec fossil init $W/small.fossil
set rel [file join .. small.fossil]
answer [list url $rel file $D/cl.fossil auth "u:secret" once 1]
repoops::clone; waitRun
set shown [.repoopsRun.t get 1.0 end]
check "clone: password not shown" {[string first secret $shown] < 0 && [string first "u:****" $shown] >= 0}
check "clone: relative source resolved, --once: [file exists $D/cl.fossil]" {[file exists $D/cl.fossil] && [string first [file normalize $W/small.fossil] $shown] >= 0 && [string first --once $shown] >= 0}
destroy .repoopsRun
tktaalik::openPath $W/co; update

# 9. One form at a time: another refused, the first kept.
whenOpen .repoopsForm {
    set ::repoops::f(url) "first"
    repoops::newRepository
    set ::second [winfo exists .repoopsForm]
    set ::kept $::repoops::f(url)
    set ::repoops::done cancel
}
repoops::clone; update
check "one form at a time: the first kept ($::kept)" {$::second && $::kept eq "first"}

# 8. Close checkout: "fossil changes" failing is not "changes".
rename repoops::runFossil repoops::realRunFossil
proc repoops::runFossil {dir args} {
    if {[lindex $args 0] eq "changes"} { return [list 1 "database is locked"] }
    if {[lindex $args 0] eq "close"} { set ::closed 1 }
    repoops::realRunFossil $dir {*}$args
}
set ::closed 0
repoops::closeCheckout; update
check "close: refused when changes fails ([lindex $::boxes end])" {!$::closed && [string match "Cannot tell*" [lindex $::boxes end]] && $tktaalik::root ne ""}
rename repoops::runFossil {}
rename repoops::realRunFossil repoops::runFossil

# 6. Pull configuration: a named remote by its name (its password).
exec fossil remote add mirror https://example.invalid/tk -R $W/tk.fossil << ""
rename repoops::runShown repoops::realRunShown
proc repoops::runShown {title cmd args} { set ::pulled $cmd; return "" }
answer {area ticket remote mirror}
repoops::pullConfiguration; update
check "pull configuration: by name ($::pulled)" {[lsearch -exact $::pulled mirror] >= 0 && [string first example.invalid $::pulled] < 0}
# Chat archive: the command (no server here).
answer [list file $D/chat.db all 1]
set ::pulled ""
exec fossil remote https://example.invalid/tk -R $W/tk.fossil << ""
repoops::chatArchive; update
check "chat archive: $::pulled" {[lrange $::pulled 0 3] eq [list fossil chat pull --out] && "--all" in $::pulled}
rename repoops::runShown {}
rename repoops::realRunShown repoops::runShown
exec fossil remote off -R $W/tk.fossil

# Export: asks before replacing a file.
set f [open $D/exists.cfg w]; puts $f old; close $f
set ::answer no
whenOpen .repoopsForm {
    set ::repoops::f(area) ticket
    set ::repoops::f(file) $::D/exists.cfg
    set ::repoops::done ok
    after 300 { set ::repoops::done cancel }
}
repoops::exportConfiguration; update
set ::answer ok
set f [open $D/exists.cfg]; set content [read $f]; close $f
check "export: not replaced when said no" {[string trim $content] eq "old"}

# Stop: a long command stopped.
repoops::runShown "Long" [list sh -c "sleep 30"] {::apply {{code out} { set ::longCode $code }}}
after 300 {set ::tick 1}; vwait ::tick
repoops::stopRunning
waitRun
check "stopped: [.repoopsRun.b.status cget -text]" {[.repoopsRun.b.status cget -text] eq "Stopped" && $::longCode == 1}
destroy .repoopsRun

# fossil ui: what is shown; stopped for another repository, and on quit.
set uuid [lindex [fossil::sql $W/tk.fossil "SELECT tkt_uuid FROM ticket ORDER BY tkt_mtime DESC LIMIT 1"] 0 0]
tktsearch::showTicket $uuid; update
check "the page of what is shown: [repoops::currentPage]" {[repoops::currentPage] eq "tktview/$uuid"}
repoops::openLocally
waitUntil {$::repoops::uiUrl ne ""} 10000
check "served, opened at the ticket: [lindex $::browsed end]" {[string match "http://localhost:*/tktview/$uuid" [lindex $::browsed end]]}
set pids [pid $::repoops::uiChan]
tktaalik::openPath $D/cl.fossil; update
check "another repository: stopped" {$::repoops::uiChan eq ""}
after 300 {set ::tick 1}; vwait ::tick
check "its process gone" {![file exists /proc/[lindex $pids 0]]}

# Remote URLs: no redirections.
tkremotes::window; update
whenOpen .remotes.add {
    set tkremotes::addName mirror2
    set tkremotes::addUrl ">x"
    set tkremotes::addDone ok
    after 300 { set tkremotes::addDone cancel }
}
set ::boxes {}
tkremotes::add; update
check "URL \">x\" refused ([lindex $::boxes 0])" {[string match "A URL cannot start*" [lindex $::boxes 0]] && ![file exists x] && ![file exists [file join [pwd] x]]}
wm withdraw .remotes

# init with a description and a template.
answer [list file $D/t2.fossil name "Two" desc "The second" template $W/tk.fossil]
set ::answer no
repoops::newRepository; update
set ::answer ok
check "init --project-desc: [lindex [fossil::sql $D/t2.fossil {SELECT value FROM config WHERE name='project-description'}] 0 0]" {[lindex [fossil::sql $D/t2.fossil "SELECT value FROM config WHERE name='project-description'"] 0 0] eq "The second"}
check "init --template: a setting copied" {[llength [fossil::sql $D/t2.fossil "SELECT 1 FROM config WHERE name='ticket-table'"]]}

# Configuration reset, exported first.
tktaalik::openPath $D/t2.fossil; update
exec fossil sql -R $D/t2.fossil "INSERT OR REPLACE INTO config(name,value,mtime) VALUES('css','/* mine */',now())"
proc tk_getSaveFile {args} { return $::D/skin.cfg }
answer {area skin export 1}
repoops::resetConfiguration; update
check "reset: exported first" {[file exists $D/skin.cfg]}
check "reset: the skin's css gone" {![llength [fossil::sql $D/t2.fossil "SELECT 1 FROM config WHERE name='css' AND value='/* mine */'"]]}

# Quit: everything stopped (no exit here).
repoops::runShown "Long" [list sh -c "sleep 30"] {::apply {{code out} {}}}
set lp [pid $::repoops::running]
repoops::stopAll
waitRun
check "stopAll: the running one stopped" {$::repoops::running eq "" && ![file exists /proc/[lindex $lp 0]]}
done
