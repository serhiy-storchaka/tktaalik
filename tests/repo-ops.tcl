# Repository and checkout operations of the menus: a new repository, a
# clone with a checkout, closing and opening a checkout, a backup, the
# known repositories, the configuration (export, import, pull), the
# unversioned files downloaded, fossil ui, the chat.  Only scratch
# repositories made here; nothing is pushed.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set D $T(tmp)
set ::boxes {}
set ::browsed {}
tktaalik::main tickets [list $W/co]
update
# Fill the form shown (repoops::form) and press OK.
proc answer {values} {
    after 200 [list apply {{values} {
        foreach {k v} $values { set ::repoops::f($k) $v }
        set ::repoops::done ok
    }} $values]
}
proc waitRun {} {
    after 100 {set ::tick 1}; vwait ::tick
    waitUntil {$::repoops::running eq ""}
    update
}
# New repository.
answer [list file $D/new.fossil name "Test project" admin tester]
repoops::newRepository; update
check "new repository: [lindex $::boxes end]" {[file exists $D/new.fossil] && $tktaalik::repo eq [file normalize $D/new.fossil]}
check "its project name" {[lindex [fossil::sql $D/new.fossil "SELECT value FROM config WHERE name='project-name'"] 0 0] eq "Test project"}
# A file in it to clone, unversioned.
set f [open $D/u.txt w]; puts $f hello; close $f
exec fossil uv add $D/u.txt --as u.txt -R $D/new.fossil -U tester
# Clone it, with a checkout.
answer [list url $D/new.fossil file $D/cl.fossil workdir $D/clco]
repoops::clone; waitRun
check "cloned: [lindex $::boxes end]" {[file exists $D/cl.fossil] && [string match "Cloned*" [lindex $::boxes end]]}
check "shown with its checkout: $tktaalik::root" {$tktaalik::root eq [file normalize $D/clco]}
# Close the checkout: the repository shown.
repoops::closeCheckout; update
check "closed: root [list $tktaalik::root], repo [file tail $tktaalik::repo]" {$tktaalik::root eq "" && [file tail $tktaalik::repo] eq "cl.fossil" && ![file exists $D/clco/.fslckout]}
check "Close checkout disabled now" {[.menubar.checkout entrycget [.menubar.checkout index "Close checkout…"] -state] eq "disabled"}
# A new checkout of it.
answer [list dir $D/co2 version "" setmtime 1]
repoops::newCheckout; update
check "new checkout: $tktaalik::root" {$tktaalik::root eq [file normalize $D/co2] && ([file exists $D/co2/.fslckout] || [file exists $D/co2/_FOSSIL_])}
# Back up.
proc tk_getSaveFile {args} { return $::D/backup.fossil }
repoops::backup; update
check "backup: [lindex $::boxes end]" {[file exists $D/backup.fossil] && [file size $D/backup.fossil] > 0}
# Known repositories.
.tickets.menu.file.known configure -postcommand {}
repoops::knownMenu .tickets.menu.file.known
set known {}
for {set i 0} {$i <= [.tickets.menu.file.known index end]} {incr i} { lappend known [.tickets.menu.file.known entrycget $i -label] }
check "known repositories: [llength $known]" {[file normalize $D/cl.fossil] in $known}
# The configuration: export, import, pull (from the remote: the clone's
# source, a file).
answer [list area ticket file $D/ticket.cfg]
repoops::exportConfiguration; update
set fh [open $D/ticket.cfg]; set cfg [read $fh]; close $fh
check "exported" {[string match "*ticket*" $cfg]}
answer [list file $D/ticket.cfg merge 1]
repoops::importConfiguration; update
check "imported: [lindex $::boxes end]" {[string match "Imported*" [lindex $::boxes end]]}
answer [list area ticket remote default overwrite 0]
repoops::pullConfiguration; waitRun
check "configuration pulled" {[string match "*Pull done*" [.repoopsRun.t get 1.0 end]] || [string match "*Round-trips*" [.repoopsRun.t get 1.0 end]]}
destroy .repoopsRun
# Unversioned files: download from the remote (the source repository).
exec fossil uv rm u.txt -R $D/cl.fossil -U tester
tkuv::window; update
check "no u.txt here" {![.uv.list.t exists u.txt]}
tkuv::download; waitRun
tkuv::reload; update
check "downloaded: u.txt" {[.uv.list.t exists u.txt]}
destroy .repoopsRun
wm withdraw .uv
# fossil ui: served here, the browser opened at it; stopped.
repoops::openLocally
waitUntil {[llength $::browsed]} 10000
check "served locally: [lindex $::browsed end]" {[string match "http://localhost:*" [lindex $::browsed end]]}
repoops::stopLocal
check "stopped" {$::repoops::uiChan eq ""}
# The chat: the remote is a file here, no chat.
set ::boxes {}
repoops::openChat
check "chat without a web remote: [lindex $::boxes end]" {[string match "*no remote with a chat*" [lindex $::boxes end]]}
done
