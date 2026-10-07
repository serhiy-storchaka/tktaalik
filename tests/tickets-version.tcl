# version: (Found in) matched as versions: a line, comparisons, ranges;
# text for the rest; the link of the details searches the number.
source [file join [file dirname [info script]] common.tcl]
tktaalik::main tickets [list $T(repo)]
update
# The rules, on values given.
set vals {8.6 8.6b1 8.6.1 8.6.18 8.6.10 8.6.13 8.6.9 "obsolete: 8.6b1.1" "final: 8.0.5"
    core-8-6-branch core-8-5-branch trunk main revised_text None 8.5.19 9.0 9.0b2}
rename tickets::versionTexts tickets::realVersionTexts
proc tickets::versionTexts {} { return $::vals }
proc sel {v} { lsort [tickets::versionValues $v] }
check "8.6: [sel 8.6]" {[sel 8.6] eq [lsort {8.6 8.6b1 8.6.1 8.6.18 8.6.10 8.6.13 8.6.9 {obsolete: 8.6b1.1} core-8-6-branch}]}
check "8.6 matches 8.6b1" {"8.6b1" in [sel 8.6]}
check "8.6.1: [sel 8.6.1] (not 8.6.18)" {[sel 8.6.1] eq "8.6.1" && "8.6.18" ni [sel 8.6.1]}
check ">=8.6.10: [sel >=8.6.10]" {[sel >=8.6.10] eq [lsort {8.6.10 8.6.13 8.6.18 core-8-6-branch 9.0 9.0b2 trunk main}]}
check "8.6.9..8.6.13: [sel 8.6.9..8.6.13]" {[sel 8.6.9..8.6.13] eq [lsort {8.6.9 8.6.10 8.6.13}]}
check "a beta before its release: [sel <9.0]" {"9.0b2" in [sel <9.0] && "9.0" ni [sel <9.0]}
check "<8.6: [sel <8.6]" {[sel <8.6] eq [lsort {8.6b1 {obsolete: 8.6b1.1} {final: 8.0.5} 8.5.19 core-8-5-branch}]}
check "text: none" {[tickets::versionValues revised_text] eq "none" && [tickets::versionValues 8.6*] eq "none"}
rename tickets::versionTexts {}
rename tickets::realVersionTexts tickets::versionTexts
# The search on the repository: more than the exact "8.6".
set exact [lindex [fossil::sql $T(repo) "SELECT count(*) FROM ticket WHERE trim(foundin)='8.6'"] 0 0]
set tktsearch::query "version:8.6 is:open,closed,pending,deleted"
tktsearch::search; update
set n [llength [.tickets.main.list.t children {}]]
check "version:8.6: $n tickets (exactly 8.6: $exact)" {$n > $exact}
set tktsearch::query "version:revised_text"
tktsearch::search; update
check "text still: [llength [.tickets.main.list.t children {}]]" {[llength [.tickets.main.list.t children {}]] > 0}
# The link of "obsolete: X": version:X.
set row [lindex [fossil::sql $T(repo) "SELECT tkt_uuid, foundin FROM ticket WHERE foundin GLOB 'obsolete: \[0-9\]*' LIMIT 1"] 0]
lassign $row uuid found
set tktsearch::query ""
tktsearch::showDetails $uuid; update
set h .tickets.main.details.head
set tag ""
foreach t [$h tag names] {
    if {[string match fl-* $t] && [llength [$h tag ranges $t]] && [$h get {*}[$h tag ranges $t]] eq $found} { set tag $t }
}
set i [lindex [$h tag ranges $tag] 0]
lassign [$h bbox $i] x y
event generate $h <Motion> -x [expr {$x + 1}] -y [expr {$y + 1}]; update
event generate $h <1> -x [expr {$x + 1}] -y [expr {$y + 1}]
event generate $h <ButtonRelease-1> -x [expr {$x + 1}] -y [expr {$y + 1}]; update
check "link of \"$found\": [list $tktsearch::query]" {$tktsearch::query eq "version:[string range $found 10 end]"}
done
