# Go to in a checkout: current, prev (through "fossil whatis", in the
# checkout); only reads the scratch copy.
source [file join [file dirname [info script]] common.tcl]
need scratch
set co $T(scratch)/co
tktaalik::main tickets [list $co]
update
set cur [lindex [fossil::checkoutSql $co "SELECT uuid FROM blob WHERE rid=(SELECT value FROM vvar WHERE name='checkout')"] 0 0]
set items [goto::find current]
check "current: [lindex $items 0 1]" {[llength $items] == 1 && [lindex $items 0 0] eq "Check-in" && [string match "current ([string range $cur 0 9])" [lindex $items 0 1]]}
set prev [lindex [fossil::checkoutSql $co "SELECT b.uuid FROM plink p JOIN blob b ON b.rid=p.pid WHERE p.cid=(SELECT value FROM vvar WHERE name='checkout') AND p.isprim"] 0 0]
set items [goto::find prev]
check "prev: [lindex $items 0 1]" {[string match "prev ([string range $prev 0 9])" [lindex $items 0 1]]}
goto::window; update
set goto::text current
goto::go; update
check "shown: [list $tktimeline::query]" {$tktaalik::active eq "timeline" && $tktimeline::query eq "hash:[string range $cur 0 15]"}
done
