# Settings saved by Tktaalik 0.0.1 kept the view (Open, Closed...) apart
# from the search; now the view is a term of it: a saved view comes back as
# its term.
source [file join [file dirname [info script]] common.tcl]
config::put $tkbranches::configFile [dict create view closed query "core" showHidden 0]
start branches
set t .branches.main.list.t
waitUntil {[llength [$t children {}]]}
check "the saved view in the search: $tkbranches::query" {$tkbranches::query eq "core is:closed" && $tkbranches::view eq "closed"}
check "the Closed button" {"selected" in [.branches.tabs.closed state]}
done
