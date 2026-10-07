# The Stash tab's options: stashing some files only, a snapshot (the
# changes kept), the diff options, dropping all (scratch copy).
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set co $W/co
set ::boxes {}
proc changes {} {
    set here [pwd]; cd $::co
    catch {exec fossil changes --classify} out
    cd $here
    return [string trim $out]
}
proc stashes {} { fossil::checkoutSql $::co "SELECT stashid, comment FROM stash ORDER BY stashid" }
# The save dialog answered: SCRIPT, then Stash.
proc answerSave {script} {
    after 50 [list apply {{script} {
        if {![winfo exists .stash.save]} { after 50 [info level 0]; return }
        update
        uplevel #0 $script
        set ::tkstash::answer 1
    }} $script]
}
proc edit {path text} { set f [open $::co/$path a]; puts $f $text; close $f }

start stash $co 1000x700
tktaalik::show stash; update
edit README.md "one"
edit license.terms "two"
# Only README.md stashed.
answerSave {
    set ::listed [.stash.save.f.files.t children {}]
    set tkstash::message "only the readme"
    tkstash::saveToggle license.terms
}
tkstash::save
check "save: the files listed ($::listed)" {[lsort $::listed] eq {README.md license.terms}}
check "only README.md stashed: [changes]" {[changes] eq "EDITED     license.terms"}
check "a stash: [stashes]" {[llength [stashes]] == 1 && [lindex [stashes] 0 1] eq "only the readme"}
# A snapshot: the changes stay.
answerSave {set tkstash::message "a snapshot"; set tkstash::snapshot 1}
tkstash::save
check "snapshot: the change kept ([changes])" {[changes] eq "EDITED     license.terms"}
check "snapshot: a second stash" {[llength [stashes]] == 2}
# The diff options go to the diffs of stashes.
set ::ran {}
rename diffview::run realRun
proc diffview::run {args} { set ::ran $args }
.stash.main.list.t selection set [lindex [.stash.main.list.t children {}] 0]; update
set diffopts::ignoreSpace 1
tkstash::showDiff
check "diff options: $::ran" {[lrange $::ran end-1 end] eq {-i -w}}
tkstash::showDiff checkout
check "against the checkout too: $::ran" {[lindex $::ran end] eq "-w" && [string match "*stash diff*" $::ran]}
set diffopts::ignoreSpace 0
rename diffview::run {}
rename realRun diffview::run
set labels {}
for {set i 0} {$i <= [.stash.menu.stash index end]} {incr i} { catch {lappend labels [.stash.menu.stash entrycget $i -label]} }
check "the Diff options and Drop all menu entries" {"Diff options" in $labels && "Drop all\u2026" in $labels}
# Drop all.
set ::boxes {}
tkstash::dropAll
check "drop all: asked ($::boxes)" {[string match "Drop all 2 stashes?" [lindex $::boxes 0]]}
check "dropped all: [stashes], [.stash.main.list.t children {}]" {[llength [stashes]] == 0 && [llength [.stash.main.list.t children {}]] == 0}
done
