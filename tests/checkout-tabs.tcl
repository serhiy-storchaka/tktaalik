# Commit and Stash need a checkout: disabled with only a repository file
# (scratch copy).
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
proc state {tab} { .nb tab .$tab -state }
# The tab saved last time: Stash; with a repository file, Tickets instead.
set f [open $tktaalik::configFile w]; puts $f "tab stash"; close $f
tktaalik::main "" [list $W/tk.fossil]
update
check "a repository file: Commit, Stash disabled" {[state commit] eq "disabled" && [state stash] eq "disabled" && [state branches] eq "normal"}
check "the saved tab Stash: Tickets instead ($tktaalik::active)" {$tktaalik::active eq "tickets"}
tktaalik::show timeline; update
check "Ctrl+6 (Commit) does nothing" {![tktaalik::show commit] && $tktaalik::active eq "timeline"}
event generate . <Control-Key-6>; update
check "nor the key itself" {$tktaalik::active eq "timeline"}
# The checkout: enabled.
tktaalik::openPath $W/co; update
check "a checkout: enabled" {[state commit] eq "normal" && [state stash] eq "normal"}
check "Stash can be shown" {[tktaalik::show stash] && $tktaalik::active eq "stash"}
set cm .menubar.checkout
check "Checkout menu enabled" {[$cm entrycget 0 -state] eq "normal" && [$cm entrycget 1 -state] eq "normal"}
$cm invoke 0; update
check "Checkout \u25b8 Commit: $tktaalik::active" {$tktaalik::active eq "commit" && $tktaalik::viewTab eq "commit"}
tktaalik::show timeline; update
tktaalik::show stash; update
# The repository file again, on the Stash tab: Tickets.
tktaalik::openPath $W/tk.fossil; update
check "back to the file: disabled, Tickets shown" {[state stash] eq "disabled" && $tktaalik::active eq "tickets"}
check "Checkout menu disabled again" {[$cm entrycget 0 -state] eq "disabled" && [$cm entrycget 1 -state] eq "disabled"}
done
