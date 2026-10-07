# Pull from the Timeline (on a scratch copy; the remote another copy, by
# a file: URL): the dialog's remotes and options, the command, what came.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set R $W/tk.fossil
set ::boxes {}
start timeline $R 1000x700
tktaalik::show timeline; update

# No remote: said so.
tktimeline::pull
check "no remote: [lindex $::boxes end]" {[lindex $::boxes end] eq "The repository has no remote."}

# The remote: a copy with a new tag (a tag change event).
set up $T(tmp)/up.fossil
file copy -force $R $up
exec fossil tag add tk-pulled main -R $up 2>@1
exec fossil remote file://$up -R $R 2>@1
exec fossil remote add other file://$up -R $R 2>@1
set labels {}
for {set i 0} {$i <= [.timeline.menu.file index end]} {incr i} {
    if {[.timeline.menu.file type $i] eq "command"} { lappend labels [.timeline.menu.file entrycget $i -label] }
}
check "File menu: Pull" {"Pull\u2026" in $labels}
# A local change: never sent.
exec fossil tag add tk-local main -R $R 2>@1
tktimeline::pull
update
set w .timeline.pull
check "dialog: remotes [$w.f.r cget -values], default first" {[$w.f.r cget -values] eq {default other} && $tktimeline::pullOpt(remote) eq "default" && [$w.f.url cget -text] eq "file://$up"}
check "All remotes: enabled with two" {![$w.f.all instate disabled]}
set tktimeline::pullOpt(private) 1
set tktimeline::pullOpt(verbose) 1
$w.f.b.ok invoke
for {set i 0} {$i < 600 && $tktimeline::pullChan ne ""} {incr i} { after 50; update }
check "pulled: [lrange $tktimeline::pullCmd 0 end-2]" {$tktimeline::pullCmd eq [list fossil pull --private -v -R $R]}
set out [$w.f.out get 1.0 end]
check "output shown: [lindex [split [string trim $out] \n] end]" {[string match "*received*" $out] || [string match "*Pull done*" $out]}
check "the tag change came: [llength [sql "SELECT 1 FROM tag WHERE tagname='sym-tk-pulled'"]]" {[llength [sql "SELECT 1 FROM tag WHERE tagname='sym-tk-pulled'"]] == 1}
# (A file: pull is not recorded with an address: the All view, which has it.)
set new [lindex [sql "SELECT e.objid FROM event e JOIN tagxref x ON x.srcid=e.objid WHERE x.tagid=(SELECT tagid FROM tag WHERE tagname='sym-tk-pulled')"] 0 0]
check "view: $tktimeline::view, the change listed" {$tktimeline::view eq "all" && [.timeline.main.list.t exists $new]}
check "Back to before the pull" {[llength $tktaalik::back] > 0}

# Another remote, once; all remotes; options.
set tktimeline::pullOpt(remote) other
set tktimeline::pullOpt(private) 0
set tktimeline::pullOpt(verbose) 0
set tktimeline::pullOpt(ipv4) 1
set tktimeline::pullOpt(verily) 1
set tktimeline::pullOpt(auth) "user:secret"
$w.f.b.ok invoke
for {set i 0} {$i < 600 && $tktimeline::pullChan ne ""} {incr i} { after 50; update }
check "other, once: [lrange $tktimeline::pullCmd 0 end-2]" {$tktimeline::pullCmd eq [list fossil pull other --once --ipv4 --verily --httpauth=user:secret -R $R]}
check "the default stays: [exec fossil remote -R $R]" {[exec fossil remote -R $R] eq "file://$up"}
set tktimeline::pullOpt(all) 1
set tktimeline::pullOpt(auth) "bad auth"
set ::boxes {}
$w.f.b.ok invoke
check "bad auth refused" {[string match "HTTP auth*" [lindex $::boxes end]]}
set tktimeline::pullOpt(auth) ""
set tktimeline::pullOpt(ipv4) 0
set tktimeline::pullOpt(verily) 0
$w.f.b.ok invoke
for {set i 0} {$i < 600 && $tktimeline::pullChan ne ""} {incr i} { after 50; update }
check "all: [lrange $tktimeline::pullCmd 0 end-2]" {$tktimeline::pullCmd eq [list fossil pull --all -R $R]}
# Not a redirection: refused, nothing run.
foreach auth {<x:y |x:y >x:y} {
    set ::boxes {}
    set tktimeline::pullCmd ""
    set tktimeline::pullOpt(auth) $auth
    $w.f.b.ok invoke
    check "auth $auth refused" {[string match "HTTP auth*" [lindex $::boxes end]] && $tktimeline::pullCmd eq ""}
}
set tktimeline::pullOpt(auth) ""
check "Stop: disabled when not pulling" {[$w.f.b.stop instate disabled] && ![$w.f.b.ok instate disabled]}
# Stop: a pull under way (here a long sleep in its place) is killed, the
# dialog as after a pull.
set tktimeline::pullBefore [lindex [sql "SELECT coalesce(max(rcvid),0) FROM rcvfrom"] 0 0]
set tktimeline::pullChan [open |[list sleep 60 2>@1] r]
set pids [pid $tktimeline::pullChan]
fconfigure $tktimeline::pullChan -blocking 0
fileevent $tktimeline::pullChan readable tktimeline::pullOutput
$w.f.b.ok state disabled; $w.f.b.stop state !disabled
$w.f.b.stop invoke
for {set i 0} {$i < 100 && $tktimeline::pullChan ne ""} {incr i} { after 50; update }
check "Stop: killed ([catch {exec kill -0 {*}$pids}])" {$tktimeline::pullChan eq "" && [catch {exec kill -0 {*}$pids}] && [$w.f.b.stop instate disabled]}
# On quit (tktimeline::stopAll): the pull and a bisect run.
set tktimeline::pullChan [open |[list sleep 60] r]
set tktimeline::bisectChan [open |[list sleep 60] r]
set pids [concat [pid $tktimeline::pullChan] [pid $tktimeline::bisectChan]]
tktimeline::stopAll
after 300
# (Killed: gone, or a zombie until its pipe is closed.)
proc dead {p} {
    if {[catch {open /proc/$p/stat} f]} { return 1 }
    set state [lindex [regsub {^.*\) } [read $f] ""] 0]
    close $f
    expr {$state eq "Z"}
}
check "stopAll: both killed" {[dead [lindex $pids 0]] && [dead [lindex $pids 1]]}
catch {close $tktimeline::pullChan}; catch {close $tktimeline::bisectChan}
set tktimeline::pullChan ""; set tktimeline::bisectChan ""
destroy $w
# Nothing is ever pushed: the remote has no artifact of ours.
check "the local change not pushed" {[llength [fossil::sql $up "SELECT 1 FROM tag WHERE tagname='sym-tk-local'"]] == 0 && [llength [sql "SELECT 1 FROM tag WHERE tagname='sym-tk-local'"]] == 1}
done
