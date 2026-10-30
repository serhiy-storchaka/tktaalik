# The graphics of the tabs, on a small repository made here: the graph of
# the check-ins in the Timeline (its layout, the images of the rows, shown
# only newest first), the lines added and deleted (the Timeline's details,
# the Commit tab), the versions of a file per period (Files), the strip of
# a bisect.
source [file join [file dirname [info script]] common.tcl]

# The layout alone: a branch from 3, merged into 1.
#   1 trunk (merges 5)   2 feature   3 trunk   4 ticket   5 feature   6 trunk
lassign [graph::layout {
    {r1 1 blue {{r3 1} {r5 0}}}
    {r2 1 red {{r5 1}}}
    {r3 1 blue {{r6 1}}}
    {r4 0 "" {}}
    {r5 1 red {{r6 1}}}
    {r6 1 blue {{r0 1}}}
}] lanes drawing
proc part {id kind} { lsearch -all -inline -index 0 [dict get $::drawing $id] $kind }
check "lanes: $lanes" {$lanes == 3}
check "trunk in lane 0: [part r1 node] [part r3 node] [part r6 node]" {[lindex [part r1 node] 0 1] == 0
    && [lindex [part r3 node] 0 1] == 0 && [lindex [part r6 node] 0 1] == 0}
check "the merge: a thin grey line across" {[lsearch -index 3 [part r1 across] $graph::merge] >= 0
    && [lindex [part r1 across] 0 4] == 1}
check "the branch in a lane of its own: [part r2 node]" {[lindex [part r2 node] 0 1] > 0}
check "the ticket change: only lines through it" {[llength [part r4 node]] == 0 && [llength [part r4 full]] >= 2}
check "the branch joins its parent: [part r6 top]" {[llength [part r6 top]] == 2 && [llength [part r6 across]] == 1}
check "a parent not shown: a stub" {[llength [part r6 stub]] == 1 && [llength [part r6 bottom]] == 0}
set img [graph::rowImage [dict get $drawing r1] $lanes 12 20 1]
check "a row's image: [image width $img]x[image height $img]" {[image width $img] == 38 && [image height $img] == 20
    && ![$img transparency get 7 10] && [$img transparency get 30 2]}

# The repository: a branch and its merge, at fixed times.
set D $T(tmp)/g
file mkdir $D/co
set R $D/g.fossil
exec fossil init $R
fossilIn $D/co open $R --nosync
# (Files written within a second of an update: changed by their content.)
fossilIn $D/co settings mtime-changes off
proc write {name lines} {
    set f [open $::D/co/$name w]
    puts -nonewline $f [join $lines \n]\n
    close $f
}
set n 0
proc commit {msg args} {
    # (Older than the empty check-in of "fossil init", made now.)
    set out [fossilIn $::D/co commit --nosync --allow-older -m $msg \
        --date-override [format "2025-0%d-01 12:00:00" [incr ::n]] {*}$args]
    regexp {New_Version: ([0-9a-f]+)} $out -> hash
    return $hash
}
write a.txt {one two three}
fossilIn $D/co add a.txt
commit "First"
write a.txt {one two three four}
set second [commit "Second"]
write b.txt {b1 b2}
fossilIn $D/co add b.txt
commit "On the branch" --branch feature
# (Not "trunk": its newest check-in is the empty one.)
fossilIn $D/co update --nosync $second
write a.txt {zero one two three four}
commit "Third"
fossilIn $D/co merge feature
commit "Merge feature"
write a.txt {zero one TWO three four}

start timeline $D/co
set t .timeline.main.list.t
set tktimeline::query ""
tktimeline::search; update
set checkins [lmap i [$t children {}] { if {[dict get $tktimeline::rows($i) type] ne "ci"} continue; set i }]
check "the graph shown: [$t cget -show]" {"tree" in [$t cget -show] && [$t column #0 -width] > 0}
check "an image on each row" {[llength [lmap i [$t children {}] { if {[$t item $i -image] eq ""} continue; set i }]] == [llength [$t children {}]]}
set rowheight [ttk::style lookup Treeview -rowheight]
check "as high as a row: $rowheight" {[image height [$t item [lindex $checkins 0] -image]] == $rowheight}
# (The empty check-in of "fossil init" is the newest: made now.)
proc byComment {text} {
    foreach i $::checkins { if {[dict get $::tktimeline::rows($i) comment] eq $text} { return $i } }
}
set merge [byComment "Merge feature"]
check "the merge: found, with its image" {$merge ne "" && [$t item $merge -image] ne ""}
tablecols::sortBy $t user; update
check "sorted by user: no graph" {"tree" ni [$t cget -show]}
tablecols::sortBy $t date; update
if {[dict get [tablecols::state $t] sort] ne {date desc}} { tablecols::sortBy $t date; update }
check "newest first again: the graph" {"tree" in [$t cget -show]}
set tktimeline::showGraph 0
tktimeline::search; update
check "turned off" {"tree" ni [$t cget -show] && [$t item $merge -image] eq ""}
set tktimeline::showGraph 1
tktimeline::search; update

# The lines of the merge in its details.
$t selection set $merge; update
set d .timeline.main.details.text
waitUntil {[llength [$d tag ranges statadd]]} 10000
set text [$d get 1.0 end]
# (Against its primary parent: the merge brings only b.txt.)
check "lines in the details: [regexp -inline {\d+ files?[^\n]*} $text]" {[regexp {1 file  \+2 \u22120 lines} $text]
    && [regexp {changed\tb\.txt\t\+2 \u22120\t} $text]}
# In columns: the counts and the bars at the same tab stops on each line.
check "columns: [$d tag cget files -tabs]" {[llength [$d tag cget files -tabs]] == 3
    && [lsearch -exact [$d tag names [lindex [$d tag ranges baradd] 0]] files] >= 0}

# The Commit tab: the lines of the change in the checkout.
tktaalik::show commit; update
set ct .commit.main.files.t
waitUntil {[$ct exists a.txt] && [$ct set a.txt stat] ne ""} 10000
check "Lines: [$ct set a.txt stat]" {[$ct set a.txt stat] eq "+1 −1"}

# Files: the versions of a.txt per month.
tktaalik::show files; update
set tkfiles::file a.txt
tkfiles::showHistory; update
set chart .files.main.right.nb.history.chart
waitUntil {[dict get $charts::spec($chart) -type] eq "bars"}
set months [dict get $charts::spec($chart) -categories]
check "versions per month from [lindex $months 0]: [lindex [dict get $charts::spec($chart) -series] 1]" {[lindex $months 0] eq "2025-01"
    && [tcl::mathop::+ {*}[lindex [dict get $charts::spec($chart) -series] 1]] == [llength [.files.main.right.nb.history.t children {}]]}
tkfiles::historyAt 2025-04 Versions; update
set h .files.main.right.nb.history.t
check "a bar: its version selected" {[string match 2025-04* [$h set [lindex [$h selection] 0] date]]}

# A bisect: the strip of the check-ins between good and bad.
fossilIn $D/co revert
fossilIn $D/co bisect bad
set first [byComment First]
fossilIn $D/co bisect good [dict get $tktimeline::rows($first) uuid]
tktaalik::show timeline; update
tktimeline::bisectInfo status; update
set strip .timeline.bisect.f.strip
waitUntil {[dict get $charts::spec($strip) -type] eq "grid"}
set states [lmap {r c v k tip} [dict get $charts::spec($strip) -cells] {set v}]
check "the strip: $states" {[lindex $states 0] eq "good" && [lindex $states end] eq "bad" && [llength $states] >= 3}
fossilIn $D/co bisect reset
done
