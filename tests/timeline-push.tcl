# Push from the Timeline (on a scratch copy; the remote another copy, by
# a file: URL): the dialog, the question of what goes, nothing sent when
# it is refused, then the command and what went.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set R $W/tk.fossil
set ::boxes {}
start timeline $R 1000x700
tktaalik::show timeline; update

# No remote: said so.
tktimeline::pull push
check "no remote: [lindex $::boxes end]" {[lindex $::boxes end] eq "The repository has no remote."
    && [dict get [lindex $::boxArgs end] -title] eq "Push"}

# The remote: a copy; local changes: a wiki page waits to go (unsent),
# a tag goes too (Fossil does not count tags as unsent).
set up $T(tmp)/up.fossil
file copy -force $R $up
exec fossil remote file://$up -R $R 2>@1
exec fossil remote add other file://$up -R $R 2>@1
set f [open $T(tmp)/page.txt w]; puts $f "Pushed."; close $f
exec fossil wiki create TkPushed $T(tmp)/page.txt -R $R 2>@1
exec fossil tag add tk-pushed main -R $R 2>@1
set labels {}
for {set i 0} {$i <= [.timeline.menu.file index end]} {incr i} {
    if {[.timeline.menu.file type $i] eq "command"} { lappend labels [.timeline.menu.file entrycget $i -label] }
}
check "File menu: Pull and Push" {"Pull…" in $labels && "Push…" in $labels}
proc remoteHas {tag} { llength [fossil::sql $::up "SELECT 1 FROM tag WHERE tagname='$tag'"] }
proc unsent {} { lindex [sql "SELECT count(*) FROM unsent"] 0 0 }
check "waiting to go: [unsent] artifacts" {[unsent] > 0 && ![remoteHas wiki-TkPushed] && ![remoteHas sym-tk-pushed]}

tktimeline::pull push
update
set w .timeline.pull
check "dialog: [wm title $w], [$w.f.l cget -text], [$w.f.b.ok cget -text]" {[wm title $w] eq "Push"
    && [$w.f.l cget -text] eq "Push to:" && [$w.f.b.ok cget -text] eq "Push"
    && [$w.f.all cget -text] eq "To all the remotes" && [string match "*Nothing is pulled*" [$w.f.into cget -text]]}
check "remotes [$w.f.r cget -values], default first" {[$w.f.r cget -values] eq {default other} && $tktimeline::pullOpt(remote) eq "default"}

# Refused: nothing run, nothing sent.
set ::boxes {}; set ::details {}
set tktimeline::pullCmd ""
set ::answer no
$w.f.b.ok invoke; update
check "asked: [lindex $::boxes end]" {[lindex $::boxes end] eq "Push from tk.fossil to default?"}
set detail [lindex $::details end]
check "the URL below: [lindex [split $detail \n] 0]" {[lindex [split $detail \n] 0] eq "default: file://$up"}
check "what goes: [lindex [split $detail \n] 2]" {[regexp -line {^Not pushed yet \(the Outgoing view\): (\d+) artifacts?} $detail -> n] && $n == [unsent]
    && [string match "*wiki: *" $detail] && [string match "*tag changes (not counted here)*" $detail]
    && [string match "*Private branches stay here.*" $detail]}
check "refused: nothing run, nothing sent" {$tktimeline::pullCmd eq "" && $tktimeline::pullChan eq "" && ![remoteHas wiki-TkPushed]}

# Confirmed: pushed, nothing waits any more.
set ::answer yes
$w.f.b.ok invoke
for {set i 0} {$i < 600 && $tktimeline::pullChan ne ""} {incr i} { after 50; update }
check "pushed: [lrange $tktimeline::pullCmd 0 end-2]" {$tktimeline::pullCmd eq [list fossil push -R $R]}
set out [$w.f.out get 1.0 end]
check "output shown: [lindex [split [string trim $out] \n] end]" {[string match "*sent*" $out] || [string match "*Push done*" $out]}
check "the page and the tag reached the remote, nothing waits: [unsent]" {[remoteHas wiki-TkPushed] && [remoteHas sym-tk-pushed] && [unsent] == 0}
check "the status line: no unpushed artifacts" {![string match "*unpushed*" $tktimeline::status]}

# Another remote, once, private too: said so in the question.
exec fossil tag add tk-pushed2 main -R $R 2>@1
set tktimeline::pullOpt(remote) other
set tktimeline::pullOpt(private) 1
set ::details {}
$w.f.b.ok invoke
for {set i 0} {$i < 600 && $tktimeline::pullChan ne ""} {incr i} { after 50; update }
check "other, once, private: [lrange $tktimeline::pullCmd 0 end-2]" {$tktimeline::pullCmd eq [list fossil push other --once --private -R $R]}
check "private said to go" {[string match "*Private branches go too.*" [lindex $::details end]]}
check "the default stays: [exec fossil remote -R $R]" {[exec fossil remote -R $R] eq "file://$up"}
check "sent: [remoteHas sym-tk-pushed2]" {[remoteHas sym-tk-pushed2]}

# Nothing waiting: said so, and asked all the same.
set tktimeline::pullOpt(remote) default
set tktimeline::pullOpt(private) 0
set ::answer no
$w.f.b.ok invoke; update
check "nothing waits: [lindex $::details end]" {[string match "*\n\nNo check-ins, wiki pages*" [lindex $::details end]]}
destroy $w

# From the File menu of another tab: the Timeline shown, the window open.
tktaalik::show tickets; update
set m .tickets.menu.file
$m invoke [$m index "Push\u2026"]; update
check "from Tickets: [winfo name [.nb select]], [wm title $w]" {[winfo name [.nb select]] eq "timeline" && [winfo exists $w] && [wm title $w] eq "Push"}
destroy $w
tktaalik::show tickets; update
$m invoke [$m index "Pull\u2026"]; update
check "Pull from Tickets: [winfo name [.nb select]], [wm title $w]" {[winfo name [.nb select]] eq "timeline" && [wm title $w] eq "Pull"}
destroy $w

# Pull's window is still Pull's.
tktimeline::pull
update
check "Pull again: [wm title $w], [$w.f.b.ok cget -text]" {[wm title $w] eq "Pull" && [$w.f.b.ok cget -text] eq "Pull" && [$w.f.l cget -text] eq "Pull from:"}
destroy $w
done
