# Branches: a new branch with a colour, update to a check-in, merge of a
# check-in (--nosync); in the scratch checkout.
source [file join [file dirname [info script]] common.tcl]
need scratch
set co $T(scratch)/co
start branches $co 1400x840
set tkbranches::view all; tkbranches::showList; update
set t .branches.main.list.t
# Confirmations answered, outputs recorded.
set ::answers {yesno no}
set ::outputs {}
proc tkbranches::showOutput {title message text {ok ""} {option {}}} { lappend ::outputs [list $title $message $text]; expr {$ok ne ""} }
set ::calls {}
rename tkbranches::inCheckout tkbranches::realInCheckout
proc tkbranches::inCheckout {args} { lappend ::calls $args; tkbranches::realInCheckout {*}$args }
proc checkout {} {
    lindex [fossil::checkoutSql $::co "SELECT uuid FROM blob WHERE rid=(SELECT value FROM vvar WHERE name='checkout')"] 0 0
}

# A new branch with a colour, through the dialog.
set tip [dict get $tkbranches::branches(main) tip]
whenOpen .branches.newbranch {
    set tkbranches::newName test-colour
    tkbranches::setColor .branches.newbranch #8080ff
    set ::swatch [.branches.newbranch.f.color.swatch cget -background]
    set ::shown [.branches.newbranch.f.color.name cget -text]
    set tkbranches::answer 1
}
tkbranches::newBranch $tip "the last check-in of main"
update
check "dialog: swatch $::swatch, $::shown" {$::swatch eq "#8080ff" && $::shown eq "#8080ff"}
check "created: [$t exists test-colour]" {[$t exists test-colour]}
set bg [fossil::sql $T(scratch)/tk.fossil "SELECT x.value FROM tagxref x JOIN tag t ON t.tagid=x.tagid
    WHERE t.tagname='bgcolor' AND x.rid=(SELECT x2.rid FROM tagxref x2 WHERE x2.tagid=(SELECT tagid FROM tag WHERE tagname='sym-test-colour') AND x2.tagtype>0 ORDER BY x2.mtime DESC LIMIT 1)"]
check "its colour in the repository: $bg" {[lindex $bg 0 0] eq "#8080ff"}
check "the confirmation names it" {[string match "*colour #8080ff*" [lindex $::boxArgs end]]}

# Update to a check-in (an earlier one of main).
$t selection set main; update
set c .branches.main.details.nb.checkins.t
set target [lindex [$c children {}] 3]
tkbranches::updateTo $target "check-in [string range $target 0 9]"
check "updated to [string range $target 0 9]: [string range [checkout] 0 9]" {[checkout] eq $target}
proc calls {cmd} { lmap c $::calls { if {[lindex $c 0] ne $cmd} continue; set c } }
set u [calls update]
check "  --nosync, dry run first: $u" {[llength $u] == 2 && "-n" in [lindex $u 0] && "--nosync" in [lindex $u 0] && "--nosync" in [lindex $u 1] && "-n" ni [lindex $u 1]}
check "  the message: [lindex $::outputs end 1]" {[lindex $::outputs end 1] eq "Updated to check-in [string range $target 0 9]."}
tkbranches::updateTo main
check "back to main" {[checkout] eq $tip}

# Merge a check-in of another open branch, not merged into main.
set other ""
foreach name [$t children {}] {
    set b $tkbranches::branches($name)
    if {$name ne "main" && ![dict get $b closed] && [dict get $b merged main] == 0 && [dict get $b checkins] > 1} { set other $name; break }
}
set ::calls {}
set uuid [dict get $tkbranches::branches($other) tip]
# (The merge dialog: OK when its dry run is there.)
whenOpen .branches.merge {
    set ::dryText [.branches.merge.f.t get 1.0 end]
    set tkbranches::mergeOpt(answer) ok
}
tkbranches::merge checkin $uuid
check "the dry run in the dialog, with -v" {[string match "*Dry run:*" $::dryText]}
cd $co; set changes [exec fossil changes --merge]
check "merged $other's [string range $uuid 0 9]: [lindex [split $changes \n] 0]" {[string first $uuid $changes] >= 0}
set m [calls merge]
check "  --nosync, no --cherrypick, dry run (-v) first: $m" {[llength $m] == 2 && "-n" in [lindex $m 0] && "-v" in [lindex $m 0] && "--nosync" in [lindex $m 1] && "--cherrypick" ni [lindex $m 1]}
exec fossil revert
done
