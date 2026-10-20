# Strings that look like numbers stay as they are: expr turns them into
# numbers (the ticket id 8413e79232... into Inf, 007 into 7, 0x10 into 16)
# or fails on NaN, so the code chooses strings with if, not with ?:.
source [file join [file dirname [info script]] common.tcl]
start tickets
set t .tickets.main.list.t
waitUntil {[llength [$t children {}]]}
set odd {8413e79232 007 NaN 0x10 1e5}
tablecols::fill $t [lmap s $odd {
    list $s-item [dict create id $s title $s] {} {}
}]
update
check "table cells: [lmap i [$t children {}] {$t set $i id}]" {
    [lsort [lmap i [$t children {}] {$t set $i id}]] eq [lsort $odd]
    && [lsort [lmap i [$t children {}] {$t set $i title}]] eq [lsort $odd]}
$t selection set 8413e79232-item
clipboard clear
focus -force $t; update
event generate $t <Control-c>; update
check "Ctrl+C: [clipboard get]" {[clipboard get] eq "8413e79232-item"}
set sql "SELECT [join [lmap s $odd {fossil::sqlstr $s}] {, }]"
check "fossil::sql" {[lindex [fossil::sql $T(repo) $sql] 0] eq $odd}
check "fossil::sql, one value" {[fossil::sql $T(repo) "SELECT '8413e79232'"] eq "8413e79232"}
set got ""
fossil::sqlAsync $T(repo) "SELECT '8413e79232'" {::apply {{code rows} { set ::got [list $code $rows] }}}
waitUntil {$got ne ""}
check "fossil::sqlAsync, one value: $got" {$got eq {0 8413e79232}}
check "settings values" {[lmap s $odd {tktaalik::getdef [dict create k $s] k ""}] eq $odd
    && [lmap s $odd {tkbranches::getdef {} k $s}] eq $odd}
done
