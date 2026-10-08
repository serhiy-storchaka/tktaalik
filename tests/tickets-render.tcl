# Tickets: wiki, Markdown and plain comments, links.
source [file join [file dirname [info script]] common.tcl]
set ::opened {}
proc tktsearch::openUrl {path} { lappend ::opened url:$path }
proc tktsearch::browse {url} { lappend ::opened browse:$url }
tktaalik::main tickets [list $T(repo) is:open]
wm geometry . 1270x900+0+0
update
set d .tickets.main.details.nb.comments.text
proc ticketWith {where} {
    lindex [::tickets::sql "SELECT t.tkt_uuid FROM ticketchng c JOIN ticket t ON t.tkt_id=c.tkt_id\
        WHERE $where ORDER BY c.tkt_mtime DESC LIMIT 1"] 0 0
}
proc show {uuid} {
    global d
    set tktsearch::query id:[string range $uuid 0 9]; tktsearch::search; update
    .tickets.main.list.t selection set $uuid
    set t [time {update}]
    return [lindex $t 0]
}
proc tagsWith {pattern} { lsearch -all -inline [$::d tag names] $pattern }
proc ranges {tag} { $::d tag ranges $tag }
proc hasTagged {pattern} {
    foreach tag [tagsWith $pattern] { if {[llength [ranges $tag]]} { return 1 } }
    return 0
}
proc fontsUsed {} {
    set r {}
    foreach tag [tagsWith ht-font-*] { if {[llength [ranges $tag]]} { lappend r $tag } }
    return $r
}
# Markdown
set md [ticketWith {c.mimetype='text/x-markdown' AND c.icomment LIKE '%`tk_getOpenFile`%'}]
set us [show $md]
puts "  markdown ticket $md ([expr {$us/1000}] ms)"
check "markdown: bold or code rendered" {[string match *-1?? [join [fontsUsed]]] || [string match *TkFixedFont* [join [fontsUsed]]]}
check "markdown: no backquotes left" {![string match {*`tk_getOpenFile`*} [$d get 1.0 end]] && [string match *tk_getOpenFile* [$d get 1.0 end]]}
# Wiki with a link
set wk [ticketWith {c.mimetype='text/x-fossil-wiki' AND c.icomment LIKE '%<b>%'}]
show $wk
puts "  wiki ticket $wk"
check "wiki: <b> rendered, not shown" {![string match "*<b>*" [$d get 1.0 end]] && [hasTagged ht-font-*-1*]}
# [hash] links
set hl [ticketWith {c.mimetype='text/x-fossil-wiki' AND c.icomment GLOB '*[[][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*[]]*'}]
set us [show $hl]
puts "  hash ticket $hl ([expr {$us/1000}] ms) hashes: $tktsearch::hashes"
check "hash links found" {[dict size $tktsearch::hashes] > 0 && [hasTagged ht-href-*]}
# Click the first link.
set tag [lindex [lsort -dictionary [lmap t [tagsWith ht-href-*] {if {[llength [ranges $t]]} {set t} else continue}]] 0]
set href $htmltext::links($d,[string range $tag 8 end])
lassign [ranges $tag] a
$d see $a; update
lassign [$d bbox $a] x y
event generate $d <Enter> -x [expr {$x+2}] -y [expr {$y+2}]; event generate $d <Motion> -x [expr {$x+2}] -y [expr {$y+2}]; update
event generate $d <ButtonPress-1> -x [expr {$x+2}] -y [expr {$y+2}]
event generate $d <ButtonRelease-1> -x [expr {$x+2}] -y [expr {$y+2}]; update
puts "  clicked $href -> $::opened, now [string range $tktsearch::shownTicket 0 9]"
# (A check-in: shown in the Timeline; what is not here: the browser.)
check "click follows the link: $tktaalik::active" {[llength $::opened] || [string match tkt:* $href] || ([goto::linkTarget $href] ne "" && $tktaalik::active ne "tickets")}
tktaalik::show tickets; update
# Plain text: fixed font, as written.
set pl [lindex [::tickets::sql "SELECT t.tkt_uuid FROM ticket t WHERE t.cmimetype='text/plain'\
    AND EXISTS (SELECT 1 FROM ticketchng c WHERE c.tkt_id=t.tkt_id AND c.icomment<>'')\
    AND NOT EXISTS (SELECT 1 FROM ticketchng c WHERE c.tkt_id=t.tkt_id AND c.icomment<>''\
        AND c.mimetype<>'text/plain') ORDER BY t.tkt_mtime DESC LIMIT 1"] 0 0]
show $pl
puts "  plain ticket $pl: fonts [fontsUsed]"
check "plain: fixed font only" {[lsearch -not -all -inline [fontsUsed] *TkFixedFont*] eq ""}
# Timing: a ticket with many comments.
set many [lindex [::tickets::sql "SELECT t.tkt_uuid FROM ticket t JOIN ticketchng c ON c.tkt_id=t.tkt_id\
    WHERE c.mimetype IN ('text/x-fossil-wiki','text/x-markdown') GROUP BY t.tkt_id ORDER BY count(*) DESC LIMIT 1"] 0 0]
set fossil::rendered {}
set us [show $many]
set n [llength [::tickets::sql "SELECT 1 FROM ticketchng c JOIN ticket t ON t.tkt_id=c.tkt_id WHERE t.tkt_uuid='$many' AND c.icomment<>''"]]
puts "  many: $many, $n comments, first view [expr {$us/1000}] ms"
.tickets.main.list.t selection set {}; update
set us2 [show $many]
puts "  again (cached) [expr {$us2/1000}] ms"
set nr [llength [::tickets::sql "SELECT 1 FROM ticketchng c JOIN ticket t ON t.tkt_id=c.tkt_id WHERE t.tkt_uuid='$many' AND c.icomment<>'' AND c.mimetype IN ('text/x-fossil-wiki','text/x-markdown')"]]
puts "  rendered by fossil: $nr, cache entries [dict size $fossil::rendered]"
check "cache filled, under 1 s" {[dict size $fossil::rendered] >= 1 && $us < 1000000}
# Bracketed Tcl in wiki is text, not a link to a missing page.
set html [tktsearch::renderHtml text/x-fossil-wiki {label .a -text [string repeat 0 0x1000] and [https://x.org|x]}]
check "wiki: \[string repeat\] stays text: [string trim $html]" {[string match {*-text [[]string repeat 0 0x1000]*} $html] && ![string match {*wiki?name=string*} $html] && [string match {*href="https://x.org"*} $html]}
show 077d49828b995ed700f9210c1c1789a90cff4d37
set i [$d search -exact {[string } 1.0]
check "ticket 077d49828b: \[string ...\] shown with brackets, no link" {$i ne "" && ![llength [lsearch -all [$d tag names $i] ht-href-*]]}
show $md
show $wk
done
