# Comments with CR LF line ends (old check-ins): no CR shown, in the
# Timeline's list and details.
source [file join [file dirname [info script]] common.tcl]
tktaalik::main tickets [list $T(repo)]
update
set uuid [lindex [fossil::sql $T(repo) "SELECT b.uuid FROM event e JOIN blob b ON b.rid=e.objid WHERE e.type='ci' AND e.comment LIKE '%'||char(13)||'%' LIMIT 1"] 0 0]
if {$uuid eq ""} {
    puts "  no comment with CR here"
    done
}
tktaalik::show timeline; update
tktimeline::setQuery hash:[string range $uuid 0 15]; update
set t .timeline.main.list.t
set rid [lindex [$t children {}] 0]
$t selection set [list $rid]; update
set details [.timeline.main.details.text get 1.0 end]
check "details: no CR" {[string first \r $details] < 0 && [string length [string trim $details]] > 0}
check "list: no CR" {[string first \r [join [$t item $rid -values]]] < 0}
check "fossil::oneLine: no CR" {[string first \r [fossil::oneLine "a\r\nb"]] < 0 && [fossil::oneLine "a\r\nb"] eq "a" && [fossil::lf "a\r\nb\rc"] eq "a\nb\nc"}
done
