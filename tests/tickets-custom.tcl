# The repository's own ticket fields (a column the application does not
# know): a column of the list, a search key, a value in the details,
# editable in the Edit dialog.  On a scratch copy.
source [file join [file dirname [info script]] common.tcl]
need scratch
set W $T(scratch)
if {![string match $W/* $::env(FOSSIL_HOME)]} { puts "FOSSIL_HOME is not the scratch one"; exit 1 }
set R $W/tk.fossil
exec fossil sql -R $R "ALTER TABLE ticket ADD COLUMN fix_version TEXT"
exec fossil sql -R $R "ALTER TABLE ticketchng ADD COLUMN fix_version TEXT"
set ::boxes {}
proc tktsearch::confirm {args} { return 1 }
start tickets $R
check "a field of its own: $::tickets::custom" {"fix_version" in $::tickets::custom}
check "a column: [dict get $::tickets::columns fix_version heading]" {[dict get $::tickets::columns fix_version heading] eq "Fix version"}
set uuid [lindex [fossil::sql $R "SELECT tkt_uuid FROM ticket ORDER BY tkt_mtime DESC LIMIT 1"] 0 0]
tktsearch::showTicket $uuid; update
# Edit: the field in the dialog.
tktsearch::editTicket $uuid; update
set f .tickets.edit.f
check "in the Edit dialog: [$f.lfix_version cget -text]" {[winfo exists $f.efix_version] && [$f.lfix_version cget -text] eq "Fix version"}
$f.efix_version delete 0 end
$f.efix_version insert 0 "9.0.4"
tktsearch::saveEdit $uuid [dict create fix_version ""]; update
set v [lindex [fossil::sql $R "SELECT coalesce(fix_version,'') FROM ticket WHERE tkt_uuid='$uuid'"] 0 0]
check "saved: $v" {$v eq "9.0.4"}
catch {destroy .tickets.edit}
# The details: the field and its value (a link).
tktsearch::showTicket $uuid; update
set h .tickets.main.details.head
check "in the details: [string range [$h get 1.0 end] 0 200]" {[string first "Fix version: 9.0.4" [$h get 1.0 end]] >= 0}
# Search by it.
set tktsearch::query "fix_version:9.0.4"
tktsearch::search; update
check "searched: [llength [.tickets.main.list.t children {}]]" {[.tickets.main.list.t children {}] eq [list $uuid]}
# New ticket: the field too, written with the ticket.
tktsearch::newTicket; update
set f .tickets.new.f
check "in New ticket" {[winfo exists $f.efix_version]}
$f.etitle insert 0 "A custom one"
$f.efix_version insert 0 "9.1"
[formattext::widget $f.editor] insert end "The description."
update
tktsearch::createTicket; update
set v [lindex [fossil::sql $R "SELECT coalesce(fix_version,'') FROM ticket WHERE title='A custom one'"] 0 0]
check "created with it: $v" {$v eq "9.1"}
done
