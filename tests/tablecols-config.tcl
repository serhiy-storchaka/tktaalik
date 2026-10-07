# Table columns and order saved as Tcl lists.
source [file join [file dirname [info script]] common.tcl]
fconfigure stdout -buffering line
set tktsearch::configFile $T(tmp)/tickets.conf
config::put $T(tmp)/tickets.conf {query is:open table {shown {type priority assignee} order {title assignee id type priority} sort {priority asc}}} table
tktaalik::main tickets [list $T(repo)]
update
set t .tickets.main.list.t
check "lists read: [$t cget -displaycolumns], sort $::tickets::sortkey $::tickets::sortdir" {[$t cget -displaycolumns] eq {title assignee id type priority} && $::tickets::sortkey eq "priority" && $::tickets::sortdir eq "asc"}
tablecols::sortBy $t updated desc; update
tktsearch::saveConfig
set f [open $T(tmp)/tickets.conf]; puts [read $f]; close $f
set c [config::get $T(tmp)/tickets.conf tickets]
check "saved as lists" {[dict get $c table shown] eq {type priority assignee} && [dict get $c table order] eq {title assignee id type priority} && [dict get $c table sort] eq {updated desc}}
done
