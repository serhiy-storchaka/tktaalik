# The menu bar follows the tab (with the View, Checkout, Repository and
# Help menus of all tabs).
source [file join [file dirname [info script]] common.tcl]
start tickets "" 1200x800
proc lseq0 {n} { set r {}; for {set i 0} {$i <= $n} {incr i} { lappend r $i }; return $r }
set clone .#menubar
foreach tab {timeline tickets branches tags files commit stash wiki forum search} {
    # (Commit and Stash need a checkout: disabled here.)
    if {[.nb tab .$tab -state] eq "disabled"} continue
    tktaalik::show $tab; update
    set labels {}
    for {set i 0} {$i <= [.menubar index end]} {incr i} { lappend labels [.menubar entrycget $i -label] }
    set exp {}
    for {set i 0} {$i <= [.$tab.menu index end]} {incr i} { lappend exp [.$tab.menu entrycget $i -label] }
    # and the Repository menu of all tabs, before Help
    set exp [linsert $exp 1 View]
    set h [lsearch -exact $exp Help]
    set exp [linsert $exp [expr {$h < 0 ? "end" : $h}] Checkout Repository]
    # and a Help menu with the manual, if the tab has none
    if {$h < 0} { lappend exp Help }
    set posted {}
    for {set i 0} {$i <= [$clone index end]} {incr i} {
        $clone activate $i; $clone postcascade $i; update
        foreach w [info commands .#menubar.*] {
            if {[winfo exists $w] && [winfo ismapped $w]} { lappend posted "[$clone entrycget $i -label]:[$w index end]" }
        }
        $clone postcascade none; update
    }
    $clone activate none
    check "$tab: menu bar [join $labels /], posted $posted" {$labels eq $exp && [llength $posted] == [llength $labels]}
}
set hm [.menubar entrycget [.menubar index end] -menu]
check "the manual in Help: [$hm entrycget 0 -label], [$hm entrycget 1 -label]" {[$hm entrycget 0 -label] eq "Manual" && [string match Contents* [$hm entrycget 1 -label]]}
# The View menu: the tabs without Commit and Stash, with their keys; a
# mark at the tab shown; choosing one shows it.
set vm .menubar.view
set vl {}
for {set i 0} {$i <= [$vm index end]} {incr i} { lappend vl "[$vm entrycget $i -label]=[$vm entrycget $i -accelerator]" }
check "View: $vl" {$vl eq {Timeline=Ctrl+1 Tickets=Ctrl+2 Branches=Ctrl+3 Tags=Ctrl+4 Files=Ctrl+5 Wiki=Ctrl+8 Forum=Ctrl+9 Search=Ctrl+0}}
set us [lmap i [lseq0 [$vm index end]] {string tolower [string index [$vm entrycget $i -label] [$vm entrycget $i -underline]]}]
check "View: a letter each: $us" {[llength [lsort -unique $us]] == [llength $us]}
$vm invoke 3; update
check "View \u25b8 Tags: $tktaalik::active, mark $tktaalik::viewTab" {$tktaalik::active eq "tags" && $tktaalik::viewTab eq "tags"}
tktaalik::show forum; update
check "the mark follows the tab: $tktaalik::viewTab" {$tktaalik::viewTab eq "forum"}
# The Checkout menu: Commit and Stash, disabled without a checkout.
set cm .menubar.checkout
check "Checkout: [$cm entrycget 0 -label] [$cm entrycget 0 -accelerator], [$cm entrycget 1 -label] [$cm entrycget 1 -accelerator]" {[$cm entrycget 0 -label] eq "Commit" && [$cm entrycget 0 -accelerator] eq "Ctrl+6" && [$cm entrycget 1 -label] eq "Stash"}
check "disabled without a checkout" {[$cm entrycget 0 -state] eq "disabled" && [$cm entrycget 1 -state] eq "disabled"}
$cm invoke 0; update
check "not shown: still $tktaalik::active, mark $tktaalik::viewTab" {$tktaalik::active eq "forum" && $tktaalik::viewTab eq "forum"}
check "same menu bar throughout" {[. cget -menu] eq ".menubar"}
# the Branch menu is filled when posted
tktaalik::show branches; update
.branches.main.list.t selection set main; update
set i [lsearch -exact [lmap k {0 1 2} {.menubar entrycget $k -label}] Branch]
$clone activate $i; $clone postcascade $i; update
set w [lindex [lmap w [info commands .#menubar.*] {if {[winfo ismapped $w]} {set w} else continue}] 0]
check "Branch menu filled for main: [$w entrycget 0 -label]" {[$w entrycget 0 -label] eq "Update checkout to main"}
$clone postcascade none
done
