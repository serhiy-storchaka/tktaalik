# The Search tab: Fossil's full-text search over check-ins, tickets, wiki,
# technotes and forum at once, ranked together; a result opens in its tab.
source [file join [file dirname [info script]] common.tcl]
needSearch
start tickets "" 1100x800
proc wait {} {
    waitUntil {![dict size $tkfulltext::running]}
    update
}
check "a tab: [.nb tab .search -text]" {[.nb tab .search -text] eq "Search"}
# Ctrl+Shift+F from another tab.
focus -force .tickets.top.q; update
event generate .tickets.top.q <Control-F>; update
check "Ctrl+Shift+F: the Search tab" {$tktaalik::active eq "search" && [focus] eq ".search.top.q"}
set tkfulltext::query menubutton
tkfulltext::search; wait
set r $tkfulltext::results
set kinds [lsort -unique [lmap row $r {lindex $row 0}]]
check "results: [llength $r], kinds $kinds; $tkfulltext::status" {[llength $r] > 20 && "c" in $kinds && "t" in $kinds}
set scores [lmap row $r {lindex $row 4}]
check "ranked by score" {$scores eq [lsort -decreasing -real $scores]}
set d .search.main.text
check "matches marked" {[llength [$d tag ranges mark]] > 0 && [string equal -nocase [$d get {*}[lrange [$d tag ranges mark] 0 1]] menubutton]}
check "no control characters left" {![regexp {[\x02\x03]} [$d get 1.0 end]]}
# Compared with the ticket search's own: the tickets titled so are found.
set n [lindex [fossil::sql $T(repo) "SELECT count(*) FROM ticket WHERE title LIKE '%menubutton%'"] 0 0]
set tk [llength [lsearch -all -index 0 $r t]]
check "tickets: $tk (titled: $n)" {$tk >= min($n, $tkfulltext::limit)}
# Only some kinds.
set tkfulltext::use(c) 0
tkfulltext::search; wait
check "without check-ins" {"c" ni [lsort -unique [lmap row $tkfulltext::results {lindex $row 0}]] && [llength $tkfulltext::results]}
set tkfulltext::use(c) 1
# Wiki pages.
set tkfulltext::query "migrating scripts"
tkfulltext::search; wait
set w [lsearch -inline -index 0 $tkfulltext::results w]
check "wiki: [lindex $w 2]" {[lindex $w 1] eq "wiki-Migrating scripts to Tk 9"}
# Open: the page in the Wiki tab; Back returns to the search.
set i [lsearch -index 0 $tkfulltext::results w]
tkfulltext::openResult $i; update; update
after 300 {set ::w 1}; vwait ::w
check "opened in Wiki: $tkwiki::shown" {$tktaalik::active eq "wiki" && $tkwiki::shown eq "wiki-Migrating scripts to Tk 9"}
tktaalik::goBack; update; wait
check "Back: the search again" {$tktaalik::active eq "search" && $tkfulltext::searched eq "migrating scripts"}
# A ticket: the Tickets tab; with the keyboard.
set tkfulltext::query menubutton
tkfulltext::search; wait
set i [lsearch -index 0 $tkfulltext::results t]
set tkfulltext::current [expr {$i - 1}]
focus -force $d; update
event generate $d <Down>; update
event generate $d <Return>; update
check "Return opens the ticket" {$tktaalik::active eq "tickets" && $tktsearch::shownTicket eq [lindex $tkfulltext::results $i 1]}
tktaalik::show search; update
# A phrase; nothing.
set tkfulltext::query "zzqqnothing"
tkfulltext::search; wait
check "nothing: $tkfulltext::status" {![llength $tkfulltext::results] && [string match "Nothing found*" $tkfulltext::status]}
set tkfulltext::query "\"native menu\""
tkfulltext::search; wait
check "a phrase: [llength $tkfulltext::results]" {[llength $tkfulltext::results] > 0}
# A forum.
if {$T(forum) ne ""} {
    tktaalik::openPath $T(forum); update
    tktaalik::show search; update
    set tkfulltext::query "fossil export git"
    tkfulltext::search; wait
    set f [lsearch -inline -index 0 $tkfulltext::results f]
    check "forum posts: [llength [lsearch -all -index 0 $tkfulltext::results f]]" {$f ne ""}
    tkfulltext::openResult [lsearch -index 0 $tkfulltext::results f]; update
    check "opened in Forum" {$tktaalik::active eq "forum" && $tkforum::selected ne ""}
}
done
