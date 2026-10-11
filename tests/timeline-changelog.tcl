# Timeline: Compare releases (in:NEW -in:OLD) and the changelog of a
# search -- the tickets the check-ins name, by type (Bug fixes, New
# features, Other tickets), then the other check-ins; merges left out
# unless asked; links to the server; nothing written to the repository.
# On a small repository made here.
source [file join [file dirname [info script]] common.tcl]
set D $T(tmp)/cl
file delete -force $D
file mkdir $D/co
set R $D/cl.fossil
exec fossil init $R
fossilIn $D/co open $R --nosync
# Each change in a file of its own (merged without conflicts).
proc edit {text} {
    set f [open $::D/co/$text.txt w]; puts $f $text; close $f
    fossilIn $::D/co add $text.txt
}
proc tkt {type title status} {
    regexp {succeeded for ([0-9a-f]+)} [exec fossil ticket add title $title type $type status $status -R $::R] -> u
    return $u
}
edit start
fossilIn $D/co commit --nosync -m "First" --tag rel-1
set bug [tkt Bug {Crash on [empty] input} Closed]
set rfe [tkt RFE "Add a frobnicate option" Open]
set other [tkt Support "Question about docs" Closed]
# A fix on a branch, merged back; a feature and a tidy-up on trunk.
edit fix
fossilIn $D/co commit --nosync -m "Fix \[[string range $bug 0 9]\]: no crash" --branch fix-crash
fossilIn $D/co update --nosync trunk
edit feature
fossilIn $D/co commit --nosync -m "Implement \[[string range $rfe 0 9]\], see also \[[string range $other 0 9]\]"
edit tidy
fossilIn $D/co commit --nosync -m "Tidy up \[sic\] the code"
fossilIn $D/co merge fix-crash
fossilIn $D/co commit --nosync -m "Merge fix-crash" --tag rel-2
# The bug's ticket named again later: still once.
edit again
fossilIn $D/co commit --nosync -m "More for \[[string range $bug 0 9]\]"
set before [lindex [exec fossil sql --readonly -R $R "SELECT count(*) FROM blob"] 0]

start timeline $R 1100x700
tktaalik::show timeline; update
check "File menu: Compare releases, Changelog" {[.timeline.menu.file index "Compare releases*"] ne "none"
    && [.timeline.menu.file index "Changelog of the search*"] ne "none"}

# Compare releases: the newest tag and the one before by default.
tktimeline::compareReleases; update
check "compare: rel-2 and rel-1 by default" {$tktimeline::cl(to) eq "rel-2" && $tktimeline::cl(from) eq "rel-1"}
set tktimeline::cl(from) nosuchtag
set ::boxes {}
tktimeline::compareDone 0; update
check "an unknown name: said, the window stays" {[winfo exists .timeline.compare] && [string match "*nosuchtag*" [lindex $::boxes end]]}
set tktimeline::cl(from) rel-2
set ::boxes {}
tktimeline::compareDone 0; update
check "the same check-in: said" {[string match "*same check-in*" [lindex $::boxes end]]}
set tktimeline::cl(from) rel-1
tktimeline::compareDone 0; update
check "Show: the search [list $tktimeline::query]" {![winfo exists .timeline.compare] && $tktimeline::query eq "in:rel-2 -in:rel-1 kind:ci"}
check "the check-ins between: 4 (not First, not the later one)" {[llength [.timeline.main.list.t children {}]] == 4}

# The changelog of that search.
tktimeline::changelog; update
set e .timeline.changelog.f.editor
set text [formattext::get $e]
set b10 [string range $bug 0 9]; set r10 [string range $rfe 0 9]; set o10 [string range $other 0 9]
check "sections in order" {[regexp {^# Bug fixes\n.*\n\n# New features\n.*\n\n# Other tickets\n.*\n\n# Other changes\n} $text]}
check "the bug: its title (brackets escaped), its link" {[string first " - \[Crash on \\\[empty\\\] input\](/tktview/$b10)" $text] >= 0}
check "the bug once, though named twice" {[regexp -all "tktview/$b10" $text] == 1}
check "the RFE: a new feature, still open" {[string first " - \[Add a frobnicate option\](/tktview/$r10) (still open)" $text] >= 0}
check "the support ticket: other tickets" {[regexp "# Other tickets\n - \\\[Question about docs\\\]\\(/tktview/$o10\\)" $text]}
check "the tidy-up: other changes, with its check-in" {[regexp {# Other changes\n - Tidy up \\\[sic\\\] the code \(\[[0-9a-f]{10}\]\(/info/[0-9a-f]{10}\)\)} $text]}
check "the merge left out" {[string first "Merge fix-crash" $text] < 0}
# Merges too; no other check-ins; another server.
set tktimeline::cl(merges) 1
tktimeline::changelogAgain; update
check "merges too" {[string first "Merge fix-crash" [formattext::get $e]] >= 0}
set tktimeline::cl(others) 0
tktimeline::changelogAgain; update
check "no other changes" {[string first "# Other changes" [formattext::get $e]] < 0}
set tktimeline::cl(base) https://example.org/repo/
tktimeline::changelogAgain; update
check "links to the server" {[string first "(https://example.org/repo/tktview/$b10)" [formattext::get $e]] >= 0}
# Edits kept unless the question is answered yes.
[formattext::widget $e] insert 1.0 "My intro\n"
set ::answer cancel
set tktimeline::cl(others) 1
tktimeline::changelogAgain; update
check "edited: kept when not confirmed" {[string match "My intro*" [formattext::get $e]]}
set ::answer ok
tktimeline::changelogAgain; update
check "confirmed: made again" {![string match "My intro*" [formattext::get $e]]}
# Saved to a file.
set ::saveFile $D/changes.md
proc tk_getSaveFile {args} { return $::saveFile }
tktimeline::changelogSave
set f [open $D/changes.md]; fconfigure $f -encoding utf-8; set saved [read $f]; close $f
check "saved" {$saved eq [formattext::get $e]}
check "nothing written to the repository" {[lindex [exec fossil sql --readonly -R $R "SELECT count(*) FROM blob"] 0] == $before}
destroy .timeline.changelog

# The release before: the same name but the last number, else the next.
check "previous of core-9-0-3: core-9-0-2, not the newer 8.6 one" {
    [tktimeline::previousTag core-9-0-3 {core-9-0-3 core-8-6-17 core-9-0-2 core-9-0-1}] eq "core-9-0-2"}
check "previous of a name without a number: the next" {[tktimeline::previousTag beta {beta alpha}] eq "alpha"}
check "previous of the oldest: none" {[tktimeline::previousTag rel-1 {rel-2 rel-1}] eq ""}
# The Event menu of a released check-in; not of another one.
set t .timeline.main.list.t
set tktimeline::query "kind:ci"; tktimeline::search 1; after cancel tktimeline::search; update
set rel2 [lindex [sql "SELECT x.rid FROM tagxref x JOIN tag t USING(tagid) WHERE t.tagname='sym-rel-2' AND x.tagtype=1" $R] 0 0]
set m .timeline.menu.event
proc entries {m} { set l {}; for {set i 0} {$i <= [$m index end]} {incr i} { catch {lappend l [$m entrycget $i -label]} }; return $l }
$m delete 0 end
tktimeline::fillEventMenu $m $rel2
check "Event menu of rel-2: Compare [lsearch -inline -glob [entries $m] Compare*]" {"Compare rel-2 with the previous release\u2026" in [entries $m]}
set other [lindex [sql "SELECT objid FROM event WHERE type='ci' AND comment GLOB 'Tidy*'" $R] 0 0]
$m delete 0 end
tktimeline::fillEventMenu $m $other
check "not for a check-in without a release tag" {[lsearch -glob [entries $m] Compare*] < 0}
$m delete 0 end
tktimeline::fillEventMenu $m $rel2
$m invoke [lsearch -glob [entries $m] Compare*]; update
check "it opens the window: rel-2 and rel-1" {[winfo exists .timeline.compare] && $tktimeline::cl(to) eq "rel-2" && $tktimeline::cl(from) eq "rel-1"}
destroy .timeline.compare
# The Tags tab: on a tag, the same; the window in the Timeline.
tktaalik::show tags; update
waitUntil {[winfo exists .tags.main.list.t] && [llength [.tags.main.list.t children {}]]}
set tm .tags.menu.tag
$tm delete 0 end
tktags::popupMenu $tm rel-2
check "Tags: Compare with the previous release" {"Compare with the previous release\u2026" in [entries $tm]
    && [$tm entrycget [lsearch -exact [entries $tm] "Compare with the previous release\u2026"] -state] eq "normal"}
$tm invoke [lsearch -exact [entries $tm] "Compare with the previous release\u2026"]; update
check "from Tags: the Timeline, the window with rel-2 and rel-1" {$tktaalik::active eq "timeline"
    && [winfo exists .timeline.compare] && $tktimeline::cl(to) eq "rel-2" && $tktimeline::cl(from) eq "rel-1"}
tktimeline::compareDone 0; update
check "Show: the range" {$tktimeline::query eq "in:rel-2 -in:rel-1 kind:ci"}
done
