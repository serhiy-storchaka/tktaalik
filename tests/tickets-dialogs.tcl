# Tickets: the edit and new-ticket dialogs (icon menus; nothing is written).
source [file join [file dirname [info script]] common.tcl]
# Never write: record what would be written.
proc tktsearch::needUser {} { return 1 }
proc tktsearch::confirm {args} { return 1 }
proc tktsearch::write {mode uuid fields} { set ::written [list $mode $uuid $fields]; return x }
proc tktsearch::showTicket {args} {}
tktaalik::main tickets [list $T(repo) {is:closed resolution:fixed priority:9 severity:critical}]
wm geometry . 1270x840+0+0
update
set uuid [lindex [.tickets.main.list.t children {}] 0]
tktsearch::editTicket $uuid; update
set f .tickets.edit.f
foreach fld {status resolution priority severity} {
    check "$fld is a menubutton: [winfo class $f.e$fld]" {[winfo class $f.e$fld] eq "TMenubutton"}
}
check "type and subsystem stay comboboxes" {[winfo class $f.etype] eq "TCombobox" && [winfo class $f.esubsystem] eq "TCombobox"}
check "status shown: [$f.estatus cget -text], fixed icon" {[$f.estatus cget -text] eq "Closed" && [$f.estatus cget -image] eq [icons::get st-fixed row]}
check "priority shown: [$f.epriority cget -text]" {[string match 9* [$f.epriority cget -text]] && [$f.epriority cget -image] eq [icons::get pr-9 row]}
check "severity shown: [$f.eseverity cget -text]" {[$f.eseverity cget -text] eq "Critical" && [$f.eseverity cget -image] eq [icons::get sv-critical row]}
set m $f.epriority.m
proc entries {m opt} { set r {}; for {set i 0} {$i <= [$m index end]} {incr i} { lappend r [$m entrycget $i $opt] }; return $r }
set labels [entries $m -label]
check "priority choices: $labels" {[llength $labels] >= 5}
check "menu entries have icons" {"" ni [entries $m -image]}
# Choose from the menus, as a click would.
$m invoke [lsearch -exact $labels "1 Zero"]; update
check "chosen priority shown: [$f.epriority cget -text]" {[$f.epriority cget -text] eq "1 Zero" && [$f.epriority cget -image] eq [icons::get pr-low row]}
set sm $f.estatus.m
for {set i 0} {$i <= [$sm index end]} {incr i} { if {[$sm entrycget $i -label] eq "Open"} { $sm invoke $i } }
update
check "status open icon: [$f.estatus cget -text]" {[$f.estatus cget -image] eq [icons::get st-open row]}
for {set i 0} {$i <= [$sm index end]} {incr i} { if {[$sm entrycget $i -label] eq "Closed"} { $sm invoke $i } }
check "edit: severity order [entries $f.eseverity.m -label]" {[entries $f.eseverity.m -label] eq {Cosmetic Minor Important Severe Critical}}
set rm $f.eresolution.m
check "resolution shown: [$f.eresolution cget -text], fixed icon" {[$f.eresolution cget -text] eq "Fixed" && [$f.eresolution cget -image] eq [icons::get st-fixed row]}
check "resolution menu icons: None blank, Wont Fix rejected" {[$rm entrycget [$rm index None] -image] eq [tktsearch::blankIcon] && [$rm entrycget [$rm index "Wont Fix"] -image] eq [icons::get st-rejected row]}
$rm invoke [$rm index None]; update
check "None: blank resolution, status plain closed" {[$f.eresolution cget -image] eq [tktsearch::blankIcon] && [$f.estatus cget -image] eq [icons::get st-closed row]}
$rm invoke [$rm index Duplicate]; update
check "resolution chosen: [$f.eresolution cget -text]" {[$f.eresolution cget -image] eq [icons::get st-duplicate row]}
check "resolution changes the status icon" {[$f.estatus cget -image] eq [icons::get st-duplicate row]}
for {set i 0} {$i <= [$sm index end]} {incr i} { if {[$sm entrycget $i -label] eq "Pending"} { $sm invoke $i } }
$f.buttons.save invoke; update
lassign $::written mode wuuid fields
check "saved: $fields" {$mode eq "set" && [dict get $fields status] eq "Pending" && [dict get $fields priority] eq "1 Zero" && [dict get $fields resolution] eq "Duplicate" && ![dict exists $fields severity]}
# The new-ticket dialog: no values yet.
tktsearch::newTicket; update
set f .tickets.new.f
check "new: severity menubutton [list [$f.eseverity cget -text]], no status or priority" {[winfo class $f.eseverity] eq "TMenubutton" && ![winfo exists $f.estatus] && ![winfo exists $f.epriority]}
check "new: severity order [entries $f.eseverity.m -label]" {[entries $f.eseverity.m -label] eq {(none) Cosmetic Minor Important Severe Critical}}
set sv $f.eseverity.m
for {set i 0} {$i <= [$sv index end]} {incr i} { if {[$sv entrycget $i -label] eq "Minor"} { $sv invoke $i } }
check "new: severity value [tktsearch::fieldValue $f.eseverity]" {[tktsearch::fieldValue $f.eseverity] eq "Minor"}
check "new: title still an entry: [tktsearch::fieldValue $f.etitle]" {[tktsearch::fieldValue $f.etitle] eq ""}
# A screenshot with the status menu posted.
destroy .tickets.new
tktsearch::editTicket $uuid; update
set f .tickets.edit.f
wm geometry .tickets.edit +0+0; update
tk_popup $f.eresolution.m [winfo rootx $f.eresolution] [expr {[winfo rooty $f.eresolution] + [winfo height $f.eresolution]}]
update; after 300 {set ::w 1}; vwait ::w
puts "heights: status [winfo height $f.estatus] type [winfo height $f.etype]"
done
