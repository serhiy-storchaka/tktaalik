# The Timeline after the history re-audit (on a scratch copy with a
# checkout): is:Open, cherry-pick and back-out relations, amended authors,
# describe (hash digits, forgotten after a search, the match pattern), the
# Update note, the check-in menu (merges, Advanced), merges from the
# Timeline, Bisect run (a bad command, auto-next, changes), purging a
# check-in and its undo.  Nothing is pushed.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set R $W/tk.fossil
set co $W/co
# Message boxes: recorded; the answer by message, else ok.
set ::boxes {}
set ::answers {}
set ::confirms {}
set ::confirmAnswer 1
proc tagwrite::confirm {args} { lappend ::confirms $args; return $::confirmAnswer }
proc tk_popup {args} {}
proc steps {steps} {
    if {![llength $steps]} return
    lassign $steps cond script
    if {![uplevel #0 [list expr $cond]]} {
        after 50 [list steps $steps]
        return
    }
    uplevel #0 $script
    after 50 [list steps [lrange $steps 2 end]]
}
start timeline $co 1100x750
tktaalik::show timeline; update
set t .timeline.main.list.t
set d .timeline.main.details.text
proc ridOf {uuid} { lindex [sql "SELECT rid FROM blob WHERE uuid='$uuid'"] 0 0 }
# A check-in found and shown: the text of its details.
proc showUuid {uuid} {
    set tktimeline::query hash:[string range $uuid 0 15]
    tktimeline::search; after cancel tktimeline::search
    set rid [ridOf $uuid]
    $::t selection set [list $rid]; update
    tktimeline::showDetails $rid
    $::d get 1.0 end
}
proc tip {} {
    set rid [lindex [fossil::checkoutSql $::co "SELECT value FROM vvar WHERE name='checkout'"] 0 0]
    lindex [sql "SELECT uuid FROM blob WHERE rid=$rid"] 0 0
}

# is:Open and is:open alike.
check "is:Open as is:open" {[tktimeline::where is:Open] eq [tktimeline::where is:open] && [string match "*NOT EXISTS*" [tktimeline::where is:OPEN]]}
check "is:Closed as is:closed" {[tktimeline::where is:Closed] eq [tktimeline::where is:closed] && ![string match "*NOT EXISTS*" [tktimeline::where is:CLOSED]]}

# A check-in on a branch, cherry-picked into main, then backed out.
cd $co
set f [open $co/zz-pick.txt w]; puts $f pick; close $f
exec fossil add zz-pick.txt
exec fossil commit --branch zz-pick -m "To be picked" --nosync --no-prompt
set A [tip]
exec fossil update main --nosync
exec fossil merge --cherrypick $A {*}[fossil::nosync merge]
exec fossil commit -m "Picked" --nosync --no-prompt
set C [tip]
exec fossil merge --backout $A {*}[fossil::nosync merge]
exec fossil commit -m "Backed out" --nosync --no-prompt
set D [tip]
cd $T(dir)
exec fossil amend $A --author zzauthor -R $R
set text [showUuid $C]
check "Cherry-picked from, the amended author" {[regexp "Cherry-picked from: [string range $A 0 9] \[^\n\]* zzauthor" $text]}
set text [showUuid $A]
check "Cherry-picked into, Backed out by" {[string match "*Cherry-picked into: [string range $C 0 9]*" $text] && [string match "*Backed out by: [string range $D 0 9]*" $text]}
set text [showUuid $D]
check "Backs out" {[string match "*Backs out: [string range $A 0 9]*" $text]}

# Describe: the hash as long as hash-digits says; forgotten after a search.
exec fossil settings hash-digits 8 -R $R
histops::forget
set desc [tktimeline::describe $C]
check "describe, 8 digits: $desc" {[regexp -- {-\d+-[0-9a-f]{8}$} $desc] && [string match "*-[string range $C 0 7]" $desc]}
exec fossil tag add zz-desc $C -R $R
check "kept until a search" {[tktimeline::describe $C] eq $desc}
tktimeline::search; after cancel tktimeline::search
check "after a search: [tktimeline::describe $C]" {[tktimeline::describe $C] eq "zz-desc"}

# Describe from tags matching: the File menu, kept in the settings.
set labels {}
for {set i 0} {$i <= [.timeline.menu.file index end]} {incr i} {
    if {[.timeline.menu.file type $i] eq "command"} { lappend labels [.timeline.menu.file entrycget $i -label] }
}
check "File menu: Describe from tags matching" {"Describe from tags matching\u2026" in $labels}
showUuid $C
steps {{[winfo exists .tagwrite.f.e]} {set tktimeline::matchAnswer zz-*; set tagwrite::answer 1}}
tktimeline::describeMatch
check "describeMatch saved: [dict get $tktimeline::config describeMatch]" {[dict get $tktimeline::config describeMatch] eq "zz-*"}

# Update: the note says what changes.
set ::confirmAnswer 0
showUuid $A
tktimeline::updateTo [ridOf $A]
set c [lindex $::confirms end]
check "Update note: [lindex $c 4]" {[lindex $c 3] eq "-note" && [string match "The files of the checkout change*" [lindex $c 4]]}
set ::confirmAnswer 1

# The check-in menu: merges into the checkout, Advanced.
showUuid $A
lassign [$t bbox [ridOf $A]] x y
tktimeline::contextMenu [expr {$x + 40}] [expr {$y + 4}] 0 0
proc labels {m} {
    set l {}
    for {set i 0} {$i <= [$m index end]} {incr i} {
        if {[$m type $i] in {command cascade}} { lappend l [$m entrycget $i -label] [$m entrycget $i -state] }
    }
    return $l
}
set l [labels .timeline.ctx]
check "menu: Merge, Cherry-pick, Back out" {[dict get $l "Merge into checkout\u2026"] eq "normal" && [dict get $l "Cherry-pick into checkout\u2026"] eq "normal" && [dict get $l "Back out in checkout\u2026"] eq "normal"}
set l [labels .timeline.ctx.advanced]
check "Advanced: Switch, Purge, graveyard" {[dict exists $l "Switch checkout here without merging\u2026"] && [dict exists $l "Purge this check-in and its descendants\u2026"] && [dict exists $l "Purge graveyard\u2026"]}

# A merge from the Timeline: the dialog of Branches, its dry run.
set root0 $tkbranches::root
set ::mergeShown ""
steps {{[winfo exists .branches.merge] && [.branches.merge.f.t get 1.0 end] ne "\n"} {
    set ::mergeShown [list [wm title .branches.merge] [.branches.merge.f.msg cget -text]]
    set tkbranches::mergeOpt(answer) cancel
}}
tktimeline::merge cherrypick [ridOf $A]
check "merge dialog: $::mergeShown" {[lindex $::mergeShown 0] eq "Cherry-pick" && [string match "Cherry-pick [string range $A 0 9] into the checkout (on trunk)*" [lindex $::mergeShown 1]] || [string match "Cherry-pick [string range $A 0 9] into the checkout (on main)*" [lindex $::mergeShown 1]]}
check "Branches' checkout as before" {$tkbranches::root eq $root0}
check "nothing merged" {[string trim [exec fossil changes --chdir $co]] eq ""}

# Bisect run: a bad command; auto-next off; changes.
proc bisectRun {cmd answers} {
    set ::boxes {}
    set ::answers $answers
    steps [list {[winfo exists .timeline.bisectrun]} [list set tktimeline::bisectCmd $cmd] \
        {1} {set tktimeline::bisectAnswer 1}]
    tktimeline::bisectCommand
    set ::answers {}
}
bisectRun "-x" {}
check "bad command refused: $::boxes" {[string match "The command cannot start*" [lindex $::boxes 0]] && $tktimeline::bisectChan eq ""}
exec fossil bisect options auto-next off --chdir $co
bisectRun true {"Turn auto-next on?" cancel}
check "auto-next off: asked, not run" {[lindex $::boxes 0] eq "Turn auto-next on?" && $tktimeline::bisectChan eq "" && [string match "*off*" [exec fossil bisect options auto-next --chdir $co]]}
set f [open $co/README.md a]; puts $f changed; close $f
bisectRun true {"The checkout has changes." cancel}
check "auto-next turned on; changes: asked, not run ($::boxes)" {$::boxes eq {{Turn auto-next on?} {The checkout has changes.}} && $tktimeline::bisectChan eq "" && [string match "*on*" [exec fossil bisect options auto-next --chdir $co]]}
exec fossil revert --chdir $co

# Purge a check-in (the branch's), its dry run first; the graveyard
# brings it back.
set ::confirms {}
set ::boxes {}
histops::purgeCheckins $R "" $A "x"
check "purge without a checkout: said so" {[lindex $::boxes 0] eq "Purging check-ins needs a checkout." && ![llength $::confirms]}
set before [llength [split [string trim [exec fossil purge list -R $R]] \n]]
showUuid $A
histops::purgeCheckins $R $co $A "check-in [string range $A 0 9]" tktimeline::changedHere
set c [lindex $::confirms 0]
check "purge: dry run (--explain) shown" {[string match "*Dry run*" [lindex $c 2]] && [string match "*[string range $A 0 9]*" [lindex $c 2]]}
check "purged: [llength [sql "SELECT 1 FROM event WHERE objid=[expr {[ridOf $A] ne "" ? [ridOf $A] : 0}]"]]" {[ridOf $A] eq "" || ![llength [sql "SELECT 1 FROM event WHERE objid=[ridOf $A]"]]}
histops::graveyard $R tktimeline::changedHere
update
set g .graveyard.f.t
set new [lindex [$g children {}] 0]
check "graveyard: the purge, newest first, its artifacts" {[llength [$g children {}]] == $before + 1 && [$g selection] eq $new && [lsearch -glob [lmap i [$g children $new] {$g set $i what}] "[string range $A 0 15]*"] >= 0}
histops::graveUndo $R tktimeline::changedHere
check "undone: back" {[ridOf $A] ne "" && [llength [sql "SELECT 1 FROM event WHERE objid=[ridOf $A]"]]}
check "graveyard as before" {[llength [$g children {}]] == $before && ![$g exists $new]}
destroy .graveyard
done
