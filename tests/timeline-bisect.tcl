# The Timeline in a checkout (a scratch one): is:current, branch:@current,
# desc:current; "fossil describe" in a check-in's hash tooltip; bisect:
# marking good, bad, skipped (the checkout or a check-in), the marks in
# the list and the status, undo, the options, status/log/chart, "bisect
# run", reset.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set ::boxes {}
start timeline $W/co 1000x700
tktaalik::show timeline; update
set t .timeline.main.list.t
proc sql {q} { fossil::sql $::W/tk.fossil $q }
proc co {args} { fossilIn $::W/co {*}$args }
proc rows {q} {
    set tktimeline::query $q
    tktimeline::search
    after cancel tktimeline::search
    if {[.timeline.status cget -foreground] eq "red3"} { return [list error $tktimeline::status] }
    .timeline.main.list.t children {}
}
set current [lindex [fossil::checkoutSql $W/co "SELECT value FROM vvar WHERE name='checkout'"] 0 0]
check "is:current: [rows is:current]" {[rows is:current] eq $current && "current" in [$t item $current -tags]}
set r [rows "branch:@current"]
check "branch:@current: [llength $r] on main" {[llength $r] > 0 && $current in $r}
# (main's tip: it, and what branches start from it, if any.)
set desc [lsort [concat {*}[fossil::checkoutSql $W/co "WITH RECURSIVE d(rid) AS (SELECT $current\
    UNION SELECT p.cid FROM plink p JOIN d ON p.pid=d.rid) SELECT rid FROM d"]]]
check "desc:current: it and its descendants ([llength $desc])" {[lsort [rows "desc:current"]] eq $desc && $current in $desc}
set uuid [lindex [sql "SELECT uuid FROM blob WHERE rid=$current"] 0 0]
rows ""
set tip [tktimeline::cellTip $current hash]
check "describe tooltip: $tip" {[string match "*[string range $uuid 0 5]*" $tip] || [regexp {^[-\w.]+$} $tip]}
# The same as "fossil describe" says, in the checkout and on other check-ins.
set cli [string trim [lindex [tktimeline::inCheckout describe $uuid] 1]]
check "as fossil describe: $cli" {$tip eq $cli}
set ok 1
foreach r [lrange [rows "kind:ci"] 5 12] {
    set u [lindex [sql "SELECT uuid FROM blob WHERE rid=$r"] 0 0]
    set c [string trim [lindex [tktimeline::inCheckout describe $u] 1]]
    set mine [tktimeline::describe $u]
    if {$mine ne $c} { set ok 0; puts "  $u: $mine vs $c" }
}
check "as fossil describe on other check-ins" {$ok}
set m [string trim [lindex [tktimeline::inCheckout describe --match core-* $uuid] 1]]
check "--match core-*: $m" {[tktimeline::describe $uuid core-*] eq $m}
check "kind tooltip still" {[tktimeline::cellTip $current kind] in {Check-in {}}}

set m .timeline.menu.bisect
tktimeline::bisectMenu $m
check "Bisect menu enabled; options read: [array get tktimeline::bisectOpt]" {[$m entrycget 0 -state] eq "normal" && $tktimeline::bisectOpt(auto-next) == 1 && $tktimeline::bisectOpt(display) eq "chart"}

# The checkout is bad; core-9-0-0 good: next goes half way.
tktimeline::bisect bad
set good [lindex [sql "SELECT b.uuid FROM tagxref x JOIN blob b ON b.rid=x.rid WHERE x.tagtype>0 AND x.tagid=(SELECT tagid FROM tag WHERE tagname='sym-core-9-0-0')"] 0 0]
set goodRid [lindex [sql "SELECT rid FROM blob WHERE uuid='$good'"] 0 0]
tktimeline::bisect good $good
update
set now [lindex [fossil::checkoutSql $W/co "SELECT value FROM vvar WHERE name='checkout'"] 0 0]
check "marked: $tktimeline::bisect" {[dict get $tktimeline::bisect $current] eq "bad" && [dict get $tktimeline::bisect $goodRid] eq "good"}
check "auto-next: the checkout moved ($current -> $now)" {$now ne $current && $now == $tktimeline::current}
check "status: [regexp -inline {bisect:[^\u00b7]*} $tktimeline::status]" {[regexp {bisect: 1 good, 1 bad, \d+ in between} $tktimeline::status]}
check "the bad row marked" {![$t exists $current] || "bisect-bad" in [$t item $current -tags]}
check "the bisect window: [.timeline.bisect.f.title cget -text]" {[string match "fossil bisect good*" [.timeline.bisect.f.title cget -text]] && [.timeline.bisect.f.t get 1.0 end] ne "\n"}
tktimeline::bisect skip
check "skipped: [dict get $tktimeline::bisect $now]" {[dict get $tktimeline::bisect $now] eq "skip"}
set before [dict size $tktimeline::bisect]
tktimeline::bisect undo
check "undo: no skip" {![dict exists $tktimeline::bisect $now] || [dict get $tktimeline::bisect $now] ne "skip"}

# Options
set tktimeline::bisectOpt(auto-next) 0
tktimeline::setBisectOption auto-next
check "auto-next off: [co bisect options auto-next]" {[string trim [co bisect options auto-next]] eq "off"}
set tktimeline::bisectOpt(display) log
tktimeline::setBisectOption display
check "display log: [co bisect options display]" {[string trim [co bisect options display]] eq "log"}
set tktimeline::bisectOpt(auto-next) 1
tktimeline::setBisectOption auto-next
foreach sub {status log chart} {
    tktimeline::bisectInfo $sub
    check "bisect $sub shown" {[.timeline.bisect.f.title cget -text] eq "fossil bisect $sub" && [string length [.timeline.bisect.f.t get 1.0 end]] > 10}
}
set tktimeline::bisectAll 1
tktimeline::bisectInfo status
check "status --all" {[.timeline.bisect.f.title cget -text] eq "fossil bisect status --all" && ![string match "*omitted*" [.timeline.bisect.f.t get 1.0 end]]}

# Changes in the checkout: asked before it moves.
set f [open $W/co/README.md a]; puts $f "local change"; close $f
set ::boxes {}
tktimeline::bisect next
check "asked: [lindex $::boxes 0]" {[lindex $::boxes 0] eq "The checkout has changes."}
co revert README.md

# bisect run: every check-in bad; it ends with the first bad one.
whenOpen .timeline.bisectrun {set tktimeline::bisectCmd false; set tktimeline::bisectAnswer 1}
tktimeline::bisectCommand
check "running: Stop shown" {[winfo exists .timeline.bisect.f.b.stop]}
for {set i 0} {$i < 1200 && $tktimeline::bisectChan ne ""} {incr i} { after 100; update }
set out [.timeline.bisect.f.t get 1.0 end]
check "bisect run done: [lindex [split [string trim $out] \n] end]" {$tktimeline::bisectChan eq "" && ![winfo exists .timeline.bisect.f.b.stop] && [string match "*fossil bisect run false*" [.timeline.bisect.f.title cget -text]] && [string length $out] > 20}

# Reset: asked; no marks.
set ::boxes {}
tktimeline::bisect reset
check "reset: asked, no marks" {[string match "Forget the bisect*" [lindex $::boxes 0]] && [dict size $tktimeline::bisect] == 0 && ![string match "*bisect:*" $tktimeline::status]}
co update main
done
