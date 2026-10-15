# Branches: Ctrl+C in the list and in the details' lists, and the copy
# button of the branch name; no Copy entries left in their menus.
source [file join [file dirname [info script]] common.tcl]
start branches "" 1400x840
set tkbranches::view all; tkbranches::showList; update
set t .branches.main.list.t
set nb .branches.main.details.nb
proc copied {w} {
    clipboard clear
    focus -force $w; update
    event generate $w <Control-c>; update
    if {[catch {clipboard get} s]} { return "" }
    return $s
}
proc commands {m} {
    set r {}
    for {set i 0} {$i <= [$m index end]} {incr i} {
        if {[$m type $i] eq "command"} { lappend r [$m entrycget $i -label] }
    }
    return $r
}

$t selection set {}; update
check "no branch: the copy buttons disabled" {[.branches.main.details.copy instate disabled] && [.branches.main.details.copytip instate disabled] && $tkbranches::tipHash eq ""}
$t selection set [list core-8-6-branch]; $t focus core-8-6-branch; update
check "Ctrl+C: the branch name" {[copied $t] eq "core-8-6-branch"}
$t selection set [list core-8-6-branch main]; update
check "Ctrl+C: the names selected, a line each: [list [copied $t]]" {[lsort [split [copied $t] \n]] eq {core-8-6-branch main}}
$t selection set [list core-8-6-branch]; $t focus core-8-6-branch; update
clipboard clear
.branches.main.details.copy invoke
check "the copy button: the name" {[.branches.main.details.copy instate !disabled] && [clipboard get] eq "core-8-6-branch"}
set tip [dict get $tkbranches::branches(core-8-6-branch) tip]
check "the last check-in shown: $tkbranches::tipHash" {$tkbranches::tipHash eq [string range $tip 0 9]}
.branches.main.details.copytip invoke
check "its copy button: the whole hash" {[clipboard get] eq $tip && [string length $tip] >= 40}
set m .branches.ctx
tkbranches::fillBranchMenu $m core-8-6-branch
check "branch menu: no Copy entries: [commands $m]" {[llength [commands $m]] && ![string match *Copy* [commands $m]] && [$m type end] ne "separator"}
# Add tag: the dialog, with the branch's last check-in (cancelled).
whenOpen .tagwrite { set ::tagged $tagwrite::f(checkin); set tagwrite::answer 0 }
set ::tagged ""
$m invoke [$m index "Add tag\u2026"]
check "branch menu: Add tag on its last check-in" {$::tagged eq $tip}

# The check-ins.
set c $nb.checkins.t
set ci [lindex [$c children {}] 0]
$c selection set [list $ci]; update
check "Ctrl+C in Check-ins: the hash" {[copied $c] eq $ci && [string length $ci] >= 40}
$nb select $nb.checkins; update
$c see $ci; waitUntil {[$c bbox $ci] ne ""}
lassign [$c bbox $ci] x y
tkbranches::checkinMenu [expr {$x + 5}] [expr {$y + 5}] 0 0; update
tk::MenuUnpost .branches.cictx
check "check-in menu: no Copy check-in: [commands .branches.cictx]" {[llength [commands .branches.cictx]] && ![string match *Copy* [commands .branches.cictx]]}
whenOpen .tagwrite { set ::tagged $tagwrite::f(checkin); set tagwrite::answer 0 }
set ::tagged ""
.branches.cictx invoke [.branches.cictx index "Add tag\u2026"]
check "check-in menu: Add tag on this check-in" {$::tagged eq $ci}

# The tickets.
set tk $nb.tickets.t
$nb select $nb.tickets; update
set id [lindex [$tk children {}] 0]
check "a ticket: $id" {$id ne ""}
$tk selection set [list $id]; update
check "Ctrl+C in Tickets: the id" {[copied $tk] eq $id}
set m [menu .tm -tearoff 0]
tkbranches::ticketMenu $m $id
check "ticket menu: no Copy ticket id: [commands $m]" {![string match *Copy* [commands $m]]}

# The files, of a small branch: its diff, in the tab.
set small [lindex [lmap n [$t children {}] {
    if {[dict get $tkbranches::branches($n) checkins] in {2 3}} { set n } else continue
}] 0]
$t selection set [list $small]; $t focus $small; update
$nb select $nb.files; update
set p $nb.files
set f $p.p.files.t
waitUntil {![dict exists $diffview::data($p) chan] && [llength [$f children {}]]}
set n [llength [$f children {}]]
check "Files of $small: its diff, $n files: [$p.status cget -text]" {[string match "*@@*" [$p.p.diff.u get 1.0 end]] && [$nb tab $nb.files -text] eq "Files ($n)"}
check "the diff's Options menu" {[winfo exists $p.bar.options]}
$f selection set [$f children {}]; update
set want [join [lmap i [$f children {}] { $f set $i file }] \n]
check "Ctrl+C in Files of $small: the paths: [list [copied $f]]" {[copied $f] eq $want && $want ne ""}
# Another branch: emptied, then its own diff when the tab is shown again.
$nb select $nb.checkins; update
set other [lindex [lmap b [$t children {}] { if {$b ne $small && [dict get $tkbranches::branches($b) checkins] in {2 3 4}} { set b } else continue }] 0]
$t selection set [list $other]; $t focus $other; update
check "another branch: emptied" {[llength [$f children {}]] == 0 && [$nb tab $nb.files -text] eq "Files"}
$nb select $nb.files; update
waitUntil {![dict exists $diffview::data($p) chan] && [llength [$f children {}]]}
check "its diff: [$p.status cget -text]" {[dict get $diffview::data($p) args] eq [list -R $tkbranches::repo --branch [fossil::arg $other]]}
# Compared with: its base, a target, a name typed; kept for the others.
set c $p.bar.compared
proc choose {text} {
    $::c set $text
    tkbranches::compareWith
    waitUntil {![dict exists $diffview::data($::p) chan]}
    update
}
set base [dict get $tkbranches::branches($other) base]
check "the choices name the base: [$c cget -values]" {$base ne "" && [lindex [$c cget -values] 0] eq "where it started" && "$base (its base)" in [$c cget -values]}
choose "$base (its base)"
check "against $base: [dict get $diffview::data($p) args]" {[dict get $diffview::data($p) args] eq [list -R $tkbranches::repo --from [fossil::arg $base] --to [fossil::arg $other]] && [string match "Files (*)" [$nb tab $nb.files -text]]}
tkbranches::saveConfig
check "kept in the settings" {[dict get [config::get $tkbranches::configFile branches tkbranches.conf] compared] eq "base"}
choose core-8-6-2
check "a tag typed: [dict get $diffview::data($p) args]" {[dict get $diffview::data($p) args] eq [list -R $tkbranches::repo --from core-8-6-2 --to [fossil::arg $other]] && [$c get] eq "core-8-6-2"}
$t selection set [list $small]; $t focus $small; update
waitUntil {![dict exists $diffview::data($p) chan] && [llength [$f children {}]]}
check "kept for $small: [dict get $diffview::data($p) args]" {[lrange [dict get $diffview::data($p) args] 2 3] eq {--from core-8-6-2}}
choose "where it started"
check "where it started: the branch's diff" {"--branch" in [dict get $diffview::data($p) args]}
# A branch made from no other (the first): no base to choose.
set root [lindex [lmap b [$t children {}] { if {[tkbranches::baseOf $b] eq ""} { set b } else continue }] 0]
$t selection set [list $root]; $t focus $root; update
check "$root: no base among [$c cget -values]" {$root ne "" && ![string match "*its base*" [$c cget -values]]}
# The branch menu: no diff entries; a double-click does nothing.
tkbranches::fillBranchMenu .branches.ctx $small
check "no diff entries in the branch menu" {[lsearch -glob -nocase [commands .branches.ctx] *diff*] < 0}
check "no double-click on a branch" {[bind $t <Double-1>] eq ""}
# The Tickets tab: the status with its icon and resolution.
$t selection set [list core-8-6-branch]; $t focus core-8-6-branch; update
set k $nb.tickets.t
set first [lindex [$k children {}] 0]
set status [string trim [$k set $first status]]
if {[package vsatisfies [package provide Tk] 9]} {
    check "Tickets: an icon in the status cell ($status)" {[llength [lsearch -all -glob [$k tag names] icon:st-*]] && [lsearch -glob [lmap tag [lsearch -all -inline -glob [$k tag names] icon:*] { $k tag cell has $tag }] "*$first status*"] >= 0 && [string match "*\u00b7*" $status]}
} else {
    check "Tickets: a sign before the status ($status)" {[regexp {^[^\x00-\x7f]+ \w} $status] && [string match "*\u00b7*" $status]}
}
set open [lmap i [$k children {}] { if {[string match "*Open*" [$k set $i status]]} { set i } else continue }]
set closed [lmap i [$k children {}] { if {[string match "*Closed*" [$k set $i status]]} { set i } else continue }]
check "Tickets: not open in grey, open not ([llength $open] open)" {[llength $closed] && [lsort -unique [lmap i $closed { $k tag has inactive $i }]] eq 1 && [lsort -unique [lmap i $open { $k tag has inactive $i }]] in {0 {}}}
done
