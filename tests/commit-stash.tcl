# Stashing some files only and a snapshot (the changes kept), from the
# Commit tab; the Stash tab's diff options, dropping all (scratch copy).
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
proc edit {path text} { set f [open $::co/$path a]; puts $f $text; close $f }

# Stashing is in the Commit tab: its Stash button stashes the checked
# files (the dialog's form answered).
start commit $co 1000x700
edit README.md "one"
edit license.terms "two"
tkcommit::refresh; update
set tkcommit::checked(license.terms) 0
whenOpen .commit.stashpart {set ::ui::f(comment) "only the readme"; set ::ui::done ok}
.commit.bottom.buttons.stash invoke; update
check "only README.md stashed: [changes]" {[changes] eq "EDITED     license.terms"}
check "a stash: [stashes]" {[llength [stashes]] == 1 && [lindex [stashes] 0 1] eq "only the readme"}
# A snapshot: the changes stay.
set tkcommit::checked(license.terms) 1
whenOpen .commit.stashpart {set ::ui::f(comment) "<a snapshot"; set ::ui::f(snapshot) 1; set ::ui::done ok}
.commit.bottom.buttons.stash invoke; update
check "snapshot: the change kept ([changes])" {[changes] eq "EDITED     license.terms"}
check "snapshot: a second stash, its comment as typed: [stashes]" {[llength [stashes]] == 2 && [lindex [stashes] 1 1] eq "<a snapshot"}
# No Stash changes in the Stash tab any more.
tktaalik::show stash; update
check "no Stash changes in the Stash tab" {![winfo exists .stash.bar] && [catch {.stash.menu.stash index "Stash changes\u2026"}]}
# The diff options go to the diff of the details.
.stash.main.list.t selection set [lindex [.stash.main.list.t children {}] 0]; update
set diffopts::ignoreSpace 1
tkstash::showStashDiff [tkstash::selected]
set ran [dict get $diffview::data(.stash.main.details.diff) args]
check "diff options: $ran" {[lrange $ran end-1 end] eq {-i -w}}
set diffopts::ignoreSpace 0
tkstash::showStashDiff [tkstash::selected]
set labels {}
for {set i 0} {$i <= [.stash.menu.stash index end]} {incr i} { catch {lappend labels [.stash.menu.stash entrycget $i -label]} }
check "the Diff options and Drop all menu entries" {"Diff options" in $labels && "Drop all\u2026" in $labels}
# Drop all.
set ::boxes {}
tkstash::dropAll
check "drop all: asked ($::boxes)" {[string match "Drop all 2 stashes?" [lindex $::boxes 0]]}
check "dropped all: [stashes], [.stash.main.list.t children {}]" {[llength [stashes]] == 0 && [llength [.stash.main.list.t children {}]] == 0}
done
