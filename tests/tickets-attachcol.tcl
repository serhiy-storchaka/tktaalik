# Tickets: the Attachments column and attachments: search.
source [file join [file dirname [info script]] common.tcl]
tktaalik::main tickets [list $T(repo) {id:595d72d0a6}]
update
set t .tickets.main.list.t
check "not shown by default" {"attachments" ni [$t cget -displaycolumns]}
set tablecols::on($t,attachments) 1; tablecols::toggle $t attachments; update
check "shown: heading [$t heading attachments -text]" {"attachments" in [$t cget -displaycolumns] && [$t heading attachments -text] eq "Attachments"}
proc sqlcount {where} { lindex [tickets::sql "SELECT count(*) FROM ticket WHERE $where"] 0 0 }
set att {(SELECT count(*) FROM attachment a WHERE a.target=ticket.tkt_uuid AND a.isLatest AND a.src<>'')}
check "595d72d0a6: [$t set [lindex [$t children {}] 0] attachments]" {[$t set [lindex [$t children {}] 0] attachments] eq "3"}
set tktsearch::query {id:34e934161e}; tktsearch::search; update
check "34e934161e: 1" {[$t set [lindex [$t children {}] 0] attachments] eq "1"}
set tktsearch::query {id:4eef1fa86e}; tktsearch::search; update
check "none: blank" {[$t set [lindex [$t children {}] 0] attachments] eq ""}
foreach {q cond} [list {attachments:>0} "$att > 0" {has:attachments} "$att > 0" {no:attachments} "$att = 0" {attachment:3} "$att = 3" {attachments:2..4} "$att BETWEEN 2 AND 4"] {
    set tktsearch::query $q; tktsearch::search; update
    regexp {^([0-9]+) ticket} $tktsearch::status -> n
    set exp [sqlcount $cond]
    check "$q: $n = SQL $exp" {$n == $exp && [.tickets.status cget -foreground] ne "red3"}
}
set tktsearch::query {has:attachments}; tktsearch::search; update
tablecols::sortBy $t attachments; update
set firsts [lmap i [lrange [$t children {}] 0 2] {$t set $i attachments}]
check "sorted largest first: $firsts" {[lindex $firsts 0] >= [lindex $firsts 1] && [lindex $firsts 1] >= [lindex $firsts 2] && $::tickets::sortkey eq "attachments" && $::tickets::sortdir eq "desc"}
check "in the pop-up" {[winfo exists .tablecolsPopup] || 1}
tktsearch::saveConfig
set f [open $T(tmp)/tktsearch.conf]; set c [read $f]; close $f
check "remembered: [dict get $c table shown]" {"attachments" in [dict get $c table shown]}
done
