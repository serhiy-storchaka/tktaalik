# Tickets: the search bar (Searches, Save, Clear, Help).
source [file join [file dirname [info script]] common.tcl]
set ::boxes {}
proc labels {m} { set l {}; for {set i 0} {$i <= [$m index end]} {incr i} { lappend l [expr {[$m type $i] eq "separator" ? "--" : [$m entrycget $i -label]}] }; return $l }
tktaalik::main tickets [list $T(repo) {state:open type:bug}]
wm geometry . 1200x800+0+0
update
set m .tickets.top.searches.m
check "no Searches in the menu bar: [lmap i {0 1 2 3} {catch {.tickets.menu entrycget $i -label} l; set l}]" {"Searches" ni [lmap i {0 1 2 3} {catch {.tickets.menu entrycget $i -label} l; set l}]}
check "button left of the entry" {[lindex [pack slaves .tickets.top] 0] eq ".tickets.top.searches" && [winfo x .tickets.top.searches] < [winfo x .tickets.top.q]}
puts "  order: [lmap w [lsort -command {apply {{a b} {expr {[winfo x $a] - [winfo x $b]}}}} [pack slaves .tickets.top]] {winfo name $w}]"
puts "  presets: [labels $m]"
check "presets in the pop-up" {"Open bugs" in [labels $m] && "Never answered" in [labels $m]}
$m invoke "Open patches"; update
check "a preset searches: $tktsearch::query" {$tktsearch::query eq "is:open type:patch"}
# save
set tktsearch::query {is:open subsystem:text}; tktsearch::search; update
whenOpen .tickets.save {set tktsearch::saveName "Text widget"; set tktsearch::answer 1}
.tickets.top.save invoke; update
check "saved: [labels $m]" {"Text widget" in [labels $m] && "Remove saved search" in [labels $m]}
set f [open $T(tmp)/tktsearch.conf]; set c [read $f]; close $f
check "in the settings at once" {[dict size [dict get $c saved]] == 1 && [dict get $c saved {Text widget}] eq "is:open subsystem:text"}
# the same name: replace after asking
set tktsearch::query {is:open subsystem:canvas}
whenOpen .tickets.save {set tktsearch::saveName "Text widget"; set tktsearch::answer 1}
.tickets.top.save invoke; update
check "replace asked: [lindex $::boxes end]" {[string match "Replace the saved search*" [lindex $::boxes end]] && [dict get $tktsearch::saved {Text widget}] eq {is:open subsystem:canvas}}
# cancel
set tktsearch::query {is:closed}
whenOpen .tickets.save {set tktsearch::answer 0}
.tickets.top.save invoke; update
check "cancel saves nothing" {[dict size $tktsearch::saved] == 1}
# use a saved one
$m invoke "Text widget"; update
check "saved search runs: $tktsearch::query" {$tktsearch::query eq {is:open subsystem:canvas}}
# empty search
set tktsearch::query "  "
.tickets.top.save invoke; update
check "empty not saved: [lindex $::boxes end]" {[lindex $::boxes end] eq "The search is empty."}
# clear
set tktsearch::query {is:open type:bug}; tktsearch::search; update
.tickets.top.clear invoke; update
check "clear: all tickets, $tktsearch::status" {$tktsearch::query eq "" && $tktsearch::state eq "all"}
# remove
$m.remove invoke "Text widget"; update
check "removed: [labels $m]" {"Text widget" ni [labels $m] && "Remove saved search" ni [labels $m]}
# kept over a restart
set tktsearch::saved {Mine {involves:@me}}; tktsearch::saveConfig
# id: with several prefixes: any of them.
set two [lmap r [sql "SELECT substr(tkt_uuid,1,10) FROM ticket ORDER BY tkt_mtime DESC LIMIT 2"] { lindex $r 0 }]
tktsearch::setQuery id:[join $two ,]; update
check "id:A,B: the two tickets" {[llength [.tickets.main.list.t children {}]] == 2}
tktsearch::setQuery "id:[lindex $two 0],"; update
check "id:A, (an empty one): the one" {[llength [.tickets.main.list.t children {}]] == 1}
# involves:A,B: the tickets of either.
set rare [lmap r [sql "SELECT submitter FROM ticket WHERE submitter GLOB '\[a-z\]*' AND submitter NOT GLOB '*\[^a-z\]*'
    GROUP BY 1 HAVING count(*) BETWEEN 2 AND 5 ORDER BY 1 LIMIT 2"] { lindex $r 0 }]
set found {}
foreach who $rare {
    tktsearch::setQuery involves:$who; update
    lappend found {*}[.tickets.main.list.t children {}]
}
tktsearch::setQuery involves:[join $rare ,]; update
check "involves:[join $rare ,]: the tickets of either" {[llength $rare] == 2 && [llength $found] > 0
    && [lsort [.tickets.main.list.t children {}]] eq [lsort -unique $found]}
# involves: also who changed a ticket (a comment, a field), not only the
# people in its fields.
lassign [lindex [sql "SELECT c.login, t.tkt_uuid FROM ticketchng c JOIN ticket t USING (tkt_id)
    WHERE c.login GLOB '\[a-z\]*' AND c.login NOT GLOB '*\[^a-z\]*'
    AND lower(c.login) NOT IN (lower(coalesce(t.submitter,'')), lower(coalesce(t.assignee,'')), lower(coalesce(t.closer,'')))
    ORDER BY (SELECT count(*) FROM ticketchng d WHERE d.login=c.login), 1 LIMIT 1"] 0] who changed
tktsearch::setQuery involves:$who; update
check "involves:$who: a ticket $who only changed" {$changed ne "" && [.tickets.main.list.t exists $changed]}
set tickets::changers 0
tktsearch::setQuery involves:$who; update
check "involves:$who: without logins in the changes, not it" {![.tickets.main.list.t exists $changed]}
set tickets::changers 1
set tktsearch::saved {}
set c [tktsearch::loadConfig]
puts "  conf: $c"
check "settings keep the saved searches" {[dict get [dict get $c saved] Mine] eq "involves:@me"}
done
